import Foundation

/// Interface language. "System" follows the first preferred language (Russian or English).
enum AppLanguage: String, CaseIterable, Codable {
    case system, ru, en

    var resolved: AppLanguage {
        guard self == .system else { return self }
        let first = Locale.preferredLanguages.first ?? "en"
        return first.hasPrefix("ru") ? .ru : .en
    }
}

/// Current language, updated from settings. Views also read `settings.language`, so they redraw on change.
var currentLanguage: AppLanguage = AppLanguage.system.resolved

/// Picks the Russian or English text. Strings stay next to the code that uses them.
func tr(_ ru: String, _ en: String) -> String {
    currentLanguage == .ru ? ru : en
}
