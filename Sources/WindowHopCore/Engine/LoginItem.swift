import Foundation
import ServiceManagement
import WindowHopKit

/// Launch-at-login via SMAppService (macOS 13+).
///
/// `SMAppService.mainApp` is documented as the *main application's* login
/// service, so it only means anything when the running binary really is an
/// application bundle. Registering a bare executable — a `swift build` product
/// run from a terminal — schedules that executable at login, which pops a
/// terminal window on the next login. WindowHop therefore refuses to enable
/// outside a bundle; disabling stays available, so a registration made before
/// this guard can still be removed. Failures are reported, never fatal.
///
/// Every result is read back from `SMAppService.Status`, never assumed from
/// the request: https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum
public enum LoginItem {
    /// The ServiceManagement boundary. Substituted in tests so no automated run
    /// can ever touch the machine's real login items.
    struct Service {
        var status: () -> SMAppService.Status
        var register: () throws -> Void
        var unregister: () throws -> Void
        var openLoginItemsSettings: () -> Void

        static var system: Service {
            Service(
                status: { SMAppService.mainApp.status },
                register: { try SMAppService.mainApp.register() },
                unregister: { try SMAppService.mainApp.unregister() },
                openLoginItemsSettings: { SMAppService.openSystemSettingsLoginItems() })
        }
    }

    /// Reads the registration; never registers or unregisters anything.
    public static var status: LoginItemStatus { status(bundle: .main, service: .system) }

    /// Only a user-initiated change, or the first-launch intent, calls this.
    @discardableResult
    public static func set(_ enabled: Bool) -> LoginItemChange {
        set(enabled, bundle: .main, service: .system)
    }

    /// The native recovery destination for `requiresApproval`.
    public static func openLoginItemsSettings() {
        Service.system.openLoginItemsSettings()
    }

    static func status(bundle: Bundle, service: Service) -> LoginItemStatus {
        status(service.status(), bundled: AppBundle.isApplication(bundle))
    }

    /// `notFound` does not prove a bundled app cannot register: on macOS 26 an
    /// application bundle that has never registered reads `notFound`, not
    /// `notRegistered`. Mapping it to unavailable would lock the toggle for
    /// good, so a bundled app shows Off and lets `register()` decide; a failed
    /// attempt is then reported as a failure. Outside a bundle nothing can be
    /// registered, so an unregistered bare executable is unavailable.
    static func status(_ status: SMAppService.Status, bundled: Bool) -> LoginItemStatus {
        switch status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return bundled ? .disabled : .unavailable
        @unknown default: return bundled ? .disabled : .unavailable
        }
    }

    /// Performs the change, then reads the status back: the result is what
    /// macOS holds, never the requested value. A thrown error matters only when
    /// the status read afterwards does not match the request — a registration
    /// that waits for approval is not a failure.
    @discardableResult
    static func set(_ enabled: Bool, bundle: Bundle, service: Service) -> LoginItemChange {
        let current = status(bundle: bundle, service: service)
        // checked before the no-op shortcut: an unbundled build must report
        // failure rather than silently agreeing that it is already enabled
        if enabled && !AppBundle.isApplication(bundle) {
            return LoginItemChange(status: current, failed: true)
        }
        guard current.isOn != enabled else {
            return LoginItemChange(status: current, failed: false)
        }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // the status read below decides whether the request took effect
        }
        let after = status(bundle: bundle, service: service)
        return LoginItemChange(status: after, failed: after.isOn != enabled)
    }
}
