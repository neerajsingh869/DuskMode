import ServiceManagement

/// Registers DuskMode to start automatically at login via `SMAppService` — the
/// modern public ServiceManagement API (macOS 13+, matches our deployment
/// target). No login-item plist, no Accessibility permission, no private
/// symbols (rule #2). The OS is the source of truth: `status` is read fresh
/// each time rather than mirrored into a pref, so it can't drift from what
/// System Settings → General → Login Items actually shows.
protocol LaunchAtLoginControlling: AnyObject {
    var isLaunchAtLoginEnabled: Bool { get }
    @discardableResult
    func setLaunchAtLoginEnabled(_ enabled: Bool) -> Bool
}

final class LaunchAtLogin: LaunchAtLoginControlling {
    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    func setLaunchAtLoginEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
