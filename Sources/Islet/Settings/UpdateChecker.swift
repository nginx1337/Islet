import AppKit
import Foundation
import IsletCore
import Observation

/// "Check for updates" in Settings. Nothing runs on its own: only the button makes one https request
/// to the GitHub API for the latest commit on main and compares it with the commit this build was made
/// from. "Update…" opens Terminal with the bundled update script, which shows the version, asks, and
/// builds the new version from source on this Mac.
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(sha: String, date: String, title: String)
        case failed(String)
    }

    static let latestCommitURL = URL(string: "https://api.github.com/repos/nginx1337/Islet/commits/main")

    private(set) var state: State = .idle

    /// Commit this build was made from (written into Info.plist by scripts/build-app.sh), if known.
    let currentCommit: String? = UpdateChecker.commit(Bundle.main.object(forInfoDictionaryKey: "IsletCommit") as? String)

    @ObservationIgnored private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["Accept": "application/vnd.github+json", "User-Agent": "Islet"]
        return URLSession(configuration: config)
    }()

    func check() {
        guard state != .checking else { return }
        state = .checking
        Task { [weak self] in
            guard let self else { return }
            self.state = await self.fetchLatest()
        }
    }

    /// Opens Terminal with the update script, so every step is visible and can be stopped.
    func update() {
        guard let script = Bundle.main.url(forResource: "update", withExtension: "command") else {
            state = .failed(tr("В этой сборке нет скрипта обновления", "This build has no update script"))
            return
        }
        NSWorkspace.shared.open(script)
    }

    private func fetchLatest() async -> State {
        guard let url = Self.latestCommitURL else { return .failed("URL") }
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                return .failed(tr("GitHub ответил ошибкой", "GitHub returned an error") + " (\(status))")
            }
            guard data.count < 2_000_000,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sha = Self.commit(json["sha"] as? String)
            else { return .failed(tr("Непонятный ответ GitHub", "Unexpected answer from GitHub")) }
            if sha == currentCommit { return .upToDate }
            let commit = json["commit"] as? [String: Any]
            let date = ((commit?["committer"] as? [String: Any])?["date"] as? String) ?? ""
            let message = (commit?["message"] as? String) ?? ""
            let title = TimeFormat.displayName(message.components(separatedBy: "\n").first ?? "", limit: 80)
            return .available(sha: sha, date: String(date.prefix(10)), title: title)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// A full lowercase commit hash, or nil.
    private static func commit(_ value: String?) -> String? {
        let digits: ClosedRange<Unicode.Scalar> = "0"..."9"
        let letters: ClosedRange<Unicode.Scalar> = "a"..."f"
        guard let value, value.count == 40,
              value.unicodeScalars.allSatisfy({ digits.contains($0) || letters.contains($0) })
        else { return nil }
        return value
    }
}
