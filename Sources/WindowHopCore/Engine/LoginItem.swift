import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+).
///
/// `SMAppService.mainApp` is documented as the *main application's* login
/// service, so it only means anything when the running binary really is an
/// application bundle. Registering a bare executable — a `swift build` product
/// run from a terminal — schedules that executable at login, which pops a
/// terminal window on the next login. WindowHop therefore refuses to enable
/// outside a bundle; disabling stays available, so a registration made before
/// this guard can still be removed. Failures are reported, never fatal.
public enum LoginItem {
    /// The ServiceManagement boundary. Substituted in tests so no automated run
    /// can ever touch the machine's real login items.
    struct Service {
        var isEnabled: () -> Bool
        var register: () throws -> Void
        var unregister: () throws -> Void

        static let system = Service(
            isEnabled: { SMAppService.mainApp.status == .enabled },
            register: { try SMAppService.mainApp.register() },
            unregister: { try SMAppService.mainApp.unregister() })
    }

    public static var isEnabled: Bool { Service.system.isEnabled() }

    @discardableResult
    public static func set(_ enabled: Bool) -> Bool {
        set(enabled, bundle: .main, service: .system)
    }

    /// A real application bundle: `…/Something.app` with an identifier. The
    /// extension alone is not enough — a directory can be named `x.app`.
    static func isBundledApplication(_ bundle: Bundle) -> Bool {
        bundle.bundleURL.pathExtension == "app" && bundle.bundleIdentifier != nil
    }

    @discardableResult
    static func set(_ enabled: Bool, bundle: Bundle, service: Service) -> Bool {
        // checked before the no-op shortcut: an unbundled build must report
        // failure rather than silently agreeing that it is already enabled
        if enabled && !isBundledApplication(bundle) { return false }
        guard service.isEnabled() != enabled else { return true }
        do {
            try enabled ? service.register() : service.unregister()
            return true
        } catch {
            return false
        }
    }
}
