import AppKit
import ServiceManagement

/// `SMAppService.mainApp` registration, driven by `SettingsStore.launchAtLogin`.
///
/// Registration genuinely fails in the real world — an unsigned build, a copy still
/// sitting in `~/Downloads`, a user who disabled the item in System Settings. The
/// error is returned rather than swallowed so the UI can revert the toggle and say
/// what happened.
@MainActor
enum LaunchAtLoginManager {

    /// What the system currently believes, independent of our persisted flag.
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user has turned the login item off in System Settings behind
    /// our back — worth telling them, because our toggle can't override it.
    static var isBlockedByUser: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers or unregisters, throwing whatever `SMAppService` throws.
    static func apply(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }

    /// One short sentence for the inline `danger` caption under the toggle.
    static func explain(_ error: Error) -> String {
        if isBlockedByUser {
            return "Turn WriteBetter on in System Settings → General → Login Items."
        }
        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain {
            return "macOS refused to register the login item (code \(nsError.code)). "
                 + "Move WriteBetter to /Applications and try again."
        }
        return "macOS refused to register the login item. Move WriteBetter to /Applications and try again."
    }
}
