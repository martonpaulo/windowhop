import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+). Registration only works when
/// running from a real .app bundle; failures are reported, never fatal.
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    public static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
