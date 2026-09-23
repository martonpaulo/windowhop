import AppKit
import Testing

@testable import WindowHopCore

extension SharedAppState {
    /// The app menu's About item opens Settings › About, WindowHop's one About
    /// surface. Selecting a pane that way is remembered like a click on it, and
    /// a plain show keeps whichever pane was last selected.
    @MainActor
    final class SettingsPaneSelectionTests {
        private static let selectedPaneKey = "settingsSelectedPaneIdentifier"
        private var autosaveName = ""
        private var savedSelection: Any?
        private var windows: [NSWindow] = []
        private var isolated: IsolatedPreferences!

        init() throws {
            _ = NSApplication.shared
            isolated = try IsolatedPreferences()
            autosaveName = "WindowHopSettingsPaneTest-\(UUID().uuidString)"
            savedSelection = UserDefaults.standard.object(forKey: Self.selectedPaneKey)
            UserDefaults.standard.set(SettingsPane.general.rawValue, forKey: Self.selectedPaneKey)
        }

        isolated deinit {
            for window in windows {
                window.setFrameAutosaveName("")
                window.close()
            }
            windows = []
            isolated.remove()
            isolated = nil
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(autosaveName)")
            UserDefaults.standard.set(savedSelection, forKey: Self.selectedPaneKey)
        }

        private func makeController() -> SettingsWindowController {
            SettingsWindowController(
                dependencies: isolated.settingsDependencies,
                registerOwnWindow: { _ in },
                frameAutosaveName: autosaveName)
        }

        private func prepare(
            _ controller: SettingsWindowController,
            selecting pane: SettingsPane?
        ) throws -> SettingsTabViewController {
            let window = controller.preparedWindow(selecting: pane)
            windows.append(window)
            return try #require(window.contentViewController as? SettingsTabViewController)
        }

        @Test func aboutEntryPointSelectsAndRemembersTheAboutPane() throws {
            let controller = makeController()
            let tabs = try prepare(controller, selecting: .about)
            #expect(tabs.selectedPane == .about)
            #expect(UserDefaults.standard.string(forKey: Self.selectedPaneKey) == "about")
        }

        @Test func aboutEntryPointSwitchesAnAlreadyOpenWindow() throws {
            let controller = makeController()
            #expect(try prepare(controller, selecting: nil).selectedPane == .general)
            #expect(try prepare(controller, selecting: .about).selectedPane == .about)
        }

        @Test func aPaneSavedByTwoPointZeroOpensWhereItsControlsMoved() throws {
            UserDefaults.standard.set("appearance", forKey: Self.selectedPaneKey)
            #expect(try prepare(makeController(), selecting: nil).selectedPane == .switcher)
        }

        @Test func plainShowKeepsTheLastSelectedPane() throws {
            let controller = makeController()
            _ = try prepare(controller, selecting: .about)
            #expect(try prepare(controller, selecting: nil).selectedPane == .about)
        }
    }
}
