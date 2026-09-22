/// Which window, if any, WindowHop shows when it launches or is opened again while
/// running (owner decision on issue #80, option C). Settings opens at a normal launch
/// only when WindowHop has no other visible surface, because the menu bar item and the
/// Dock icon are both hidden by default. Missing Accessibility opens onboarding on every
/// launch, login included: native ⌘Tab keeps working silently, so nothing else would
/// reveal that WindowHop is inert. docs/architecture.md "Launch and reopen" holds the table.
public enum LaunchPresentation: Equatable {
    case none
    case settings
    case onboarding

    public enum Trigger: Equatable {
        /// Started from the Finder, Spotlight, the Dock or the command line.
        case normalLaunch
        /// Started by the system as a login item.
        case loginItemLaunch
        /// Opened again while already running.
        case reopen
    }

    public static func decide(trigger: Trigger,
                              permissionGranted: Bool,
                              isFirstRun: Bool,
                              menuBarItemVisible: Bool,
                              dockIconVisible: Bool) -> LaunchPresentation {
        guard permissionGranted else { return .onboarding }
        switch trigger {
        case .reopen:
            return .settings
        case .loginItemLaunch:
            return .none
        case .normalLaunch:
            let hasOtherSurface = menuBarItemVisible || dockIconVisible
            return isFirstRun || !hasOtherSurface ? .settings : .none
        }
    }
}
