import ServiceManagement

/// "Open at login" through the system Login Items list (visible in System Settings).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Returns a message for the user when something needs attention, nil on success.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if needsApproval {
                    SMAppService.openSystemSettingsLoginItems()
                    return tr("Разрешите запуск Islet в Системных настройках → Основные → Объекты входа.",
                              "Allow Islet in System Settings → General → Login Items.")
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            Log.system.error("Login item: \(error.localizedDescription, privacy: .public)")
            return tr("Не удалось изменить автозапуск: ", "Could not change the login item: ") + error.localizedDescription
        }
    }
}
