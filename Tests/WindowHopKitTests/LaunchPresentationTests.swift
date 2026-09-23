import Foundation
import Testing

@testable import WindowHopKit

/// The launch and reopen contract decided on issue #80 (option C), one row per
/// condition in docs/architecture.md "Launch and reopen".
struct LaunchPresentationTests {
    private struct Row {
        let name: String
        let trigger: LaunchPresentation.Trigger
        let granted: Bool
        let firstRun: Bool
        let menuBarItem: Bool
        let dockIcon: Bool
        let expected: LaunchPresentation
    }

    private let rows: [Row] = [
        // normal launch, granted
        Row(
            name: "first run, icons hidden", trigger: .normalLaunch, granted: true,
            firstRun: true, menuBarItem: false, dockIcon: false, expected: .settings),
        Row(
            name: "first run, menu bar item shown", trigger: .normalLaunch, granted: true,
            firstRun: true, menuBarItem: true, dockIcon: false, expected: .settings),
        Row(
            name: "later run, menu bar item shown", trigger: .normalLaunch, granted: true,
            firstRun: false, menuBarItem: true, dockIcon: false, expected: .none),
        Row(
            name: "later run, Dock icon shown", trigger: .normalLaunch, granted: true,
            firstRun: false, menuBarItem: false, dockIcon: true, expected: .none),
        Row(
            name: "later run, both shown", trigger: .normalLaunch, granted: true,
            firstRun: false, menuBarItem: true, dockIcon: true, expected: .none),
        Row(
            name: "later run, both hidden", trigger: .normalLaunch, granted: true,
            firstRun: false, menuBarItem: false, dockIcon: false, expected: .settings),
        // login-item launch, granted: silent whatever is visible
        Row(
            name: "login, both hidden", trigger: .loginItemLaunch, granted: true,
            firstRun: false, menuBarItem: false, dockIcon: false, expected: .none),
        Row(
            name: "login, menu bar item shown", trigger: .loginItemLaunch, granted: true,
            firstRun: false, menuBarItem: true, dockIcon: false, expected: .none),
        Row(
            name: "login, first run", trigger: .loginItemLaunch, granted: true,
            firstRun: true, menuBarItem: false, dockIcon: false, expected: .none),
        // not granted: onboarding on any launch, login included (recorded exception)
        Row(
            name: "normal, not granted, icon shown", trigger: .normalLaunch, granted: false,
            firstRun: false, menuBarItem: true, dockIcon: true, expected: .onboarding),
        Row(
            name: "normal, not granted, first run", trigger: .normalLaunch, granted: false,
            firstRun: true, menuBarItem: false, dockIcon: false, expected: .onboarding),
        Row(
            name: "login, not granted", trigger: .loginItemLaunch, granted: false,
            firstRun: false, menuBarItem: false, dockIcon: false, expected: .onboarding),
        Row(
            name: "login, not granted, icon shown", trigger: .loginItemLaunch, granted: false,
            firstRun: false, menuBarItem: true, dockIcon: false, expected: .onboarding),
        // reopen while running: unchanged, visibility never matters
        Row(
            name: "reopen, granted, icons shown", trigger: .reopen, granted: true,
            firstRun: false, menuBarItem: true, dockIcon: true, expected: .settings),
        Row(
            name: "reopen, granted, icons hidden", trigger: .reopen, granted: true,
            firstRun: false, menuBarItem: false, dockIcon: false, expected: .settings),
        Row(
            name: "reopen, not granted", trigger: .reopen, granted: false,
            firstRun: false, menuBarItem: true, dockIcon: false, expected: .onboarding),
    ]

    @Test func everyLaunchAndReopenCondition() {
        for row in rows {
            let actual = LaunchPresentation.decide(
                trigger: row.trigger,
                permissionGranted: row.granted,
                isFirstRun: row.firstRun,
                menuBarItemVisible: row.menuBarItem,
                dockIconVisible: row.dockIcon)
            #expect(actual == row.expected, "\(row.name)")
        }
    }

    /// Hidden icons must never leave the user without a route back: reopening
    /// always shows a window, whatever the rest of the state is.
    @Test func reopenAlwaysShowsAWindow() {
        for granted in [true, false] {
            for firstRun in [true, false] {
                for menuBarItem in [true, false] {
                    for dockIcon in [true, false] {
                        let result = LaunchPresentation.decide(
                            trigger: .reopen, permissionGranted: granted,
                            isFirstRun: firstRun, menuBarItemVisible: menuBarItem,
                            dockIconVisible: dockIcon)
                        #expect(result != .none)
                    }
                }
            }
        }
    }
}
