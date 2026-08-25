import SwiftUI
import ServiceManagement

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var launchAtLogin: Bool = false {
        didSet {
            // Don't react to programmatic syncs (initial load / failure revert)
            guard !isSyncing else { return }
            updateLaunchAtLogin()
        }
    }

    /// Non-nil when the last register/unregister failed
    @Published var launchAtLoginError: String?

    /// True while we're writing `launchAtLogin` ourselves, so `didSet` no-ops
    private var isSyncing = false

    init() {
        loadSettings()
    }

    private func loadSettings() {
        guard #available(macOS 13.0, *) else { return }
        setLaunchAtLoginSilently(SMAppService.mainApp.status == .enabled)
    }

    private func setLaunchAtLoginSilently(_ value: Bool) {
        isSyncing = true
        launchAtLogin = value
        isSyncing = false
    }

    private func updateLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            // Registration failed — surface it and revert the toggle to the real
            // OS state so the checkbox doesn't lie about what actually happened
            launchAtLoginError = error.localizedDescription
            setLaunchAtLoginSilently(SMAppService.mainApp.status == .enabled)
            NSLog("[WS] Launch-at-login update failed: \(error.localizedDescription)")
        }
    }
}
