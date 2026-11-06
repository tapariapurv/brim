import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginSetting {
    static let failureMessage = "macOS wouldn't update Launch at Login. Check System Settings → Login Items."
    private static let turnedOffKey = "launchAtLoginTurnedOff"

    private(set) var isEnabled: Bool
    private(set) var errorMessage: String?

    private let currentStatus: () -> Bool
    private let setSystemEnabled: (Bool) throws -> Void
    private let canRegister: () -> Bool
    private let defaults: UserDefaults

    init(
        currentStatus: @escaping () -> Bool = { SMAppService.mainApp.status == .enabled },
        setEnabled: @escaping (Bool) throws -> Void = { enabled in
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        },
        // `.requiresApproval` means the user turned Brim off in System Settings; only they can undo that.
        canRegister: @escaping () -> Bool = { SMAppService.mainApp.status == .notRegistered },
        defaults: UserDefaults = .standard
    ) {
        self.currentStatus = currentStatus
        self.setSystemEnabled = setEnabled
        self.canRegister = canRegister
        self.defaults = defaults
        self.isEnabled = currentStatus()
    }

    /// Runs on every app open: adds the login item unless the user turned it off in Settings.
    func registerOnOpen() {
        guard !defaults.bool(forKey: Self.turnedOffKey), canRegister() else { return }
        update(to: true)
    }

    func refreshStatus() {
        let enabled = currentStatus()
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        errorMessage = nil
    }

    func update(to enabled: Bool) {
        guard enabled != isEnabled else { return }
        do {
            try setSystemEnabled(enabled)
            defaults.set(!enabled, forKey: Self.turnedOffKey)
            isEnabled = currentStatus()
            errorMessage = nil
        } catch {
            AppLog.error(
                .config,
                "Launch at Login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)"
            )
            isEnabled = currentStatus()
            errorMessage = Self.failureMessage
        }
    }
}
