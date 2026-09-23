import Foundation
import WindowHopKit

/// The General pane's launch-at-login state: the login-item status macOS
/// reports plus whether the last requested change failed.
///
/// `refresh()` only reads — it runs when the pane appears and when WindowHop
/// becomes active, so a change made in System Settings shows up without any
/// polling, and opening Settings can never register a login item. `request(_:)`
/// is the only path that changes the registration, and it records the
/// person's intent in `Preferences.launchAtLogin` only when the change did not
/// fail.
@MainActor
final class LaunchAtLoginModel: ObservableObject {
    @Published private(set) var status: LoginItemStatus
    @Published private(set) var failed = false

    private let preferences: Preferences
    private let readStatus: () -> LoginItemStatus
    private let change: (Bool) -> LoginItemChange
    private let openLoginItemsSettingsAction: () -> Void

    init(preferences: Preferences = .shared,
         readStatus: @escaping () -> LoginItemStatus = { LoginItem.status },
         change: @escaping (Bool) -> LoginItemChange = { LoginItem.set($0) },
         openLoginItemsSettings: @escaping () -> Void = LoginItem.openLoginItemsSettings) {
        self.preferences = preferences
        self.readStatus = readStatus
        self.change = change
        self.openLoginItemsSettingsAction = openLoginItemsSettings
        status = readStatus()
    }

    /// A status that changed since the failed request supersedes its message.
    func refresh() {
        let current = readStatus()
        guard current != status else { return }
        status = current
        failed = false
    }

    func request(_ on: Bool) {
        let result = change(on)
        status = result.status
        failed = result.failed
        if !result.failed {
            preferences.launchAtLogin = on
        }
    }

    func openLoginItemsSettings() {
        openLoginItemsSettingsAction()
    }
}
