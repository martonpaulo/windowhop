import AppKit
import XCTest
@testable import WindowHopCore

/// The app menu's About item opens Settings › About, WindowHop's one About
/// surface. Selecting a pane that way is remembered like a click on it, and
/// a plain show keeps whichever pane was last selected.
@MainActor
final class SettingsPaneSelectionTests: XCTestCase {
    private static let selectedPaneKey = "settingsSelectedPaneIdentifier"
    private var autosaveName: String!
    private var savedSelection: Any?
    private var windows: [NSWindow] = []

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        autosaveName = "WindowHopSettingsPaneTest-\(UUID().uuidString)"
        savedSelection = UserDefaults.standard.object(forKey: Self.selectedPaneKey)
        UserDefaults.standard.set(SettingsPane.general.rawValue, forKey: Self.selectedPaneKey)
    }

    override func tearDown() {
        for window in windows {
            window.setFrameAutosaveName("")
            window.close()
        }
        windows = []
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(autosaveName!)")
        UserDefaults.standard.set(savedSelection, forKey: Self.selectedPaneKey)
        super.tearDown()
    }

    private func prepare(_ controller: SettingsWindowController,
                         selecting pane: SettingsPane?) throws -> SettingsTabViewController {
        let window = controller.preparedWindow(selecting: pane)
        windows.append(window)
        return try XCTUnwrap(window.contentViewController as? SettingsTabViewController)
    }

    func testAboutEntryPointSelectsAndRemembersTheAboutPane() throws {
        let controller = SettingsWindowController(frameAutosaveName: autosaveName)
        let tabs = try prepare(controller, selecting: .about)
        XCTAssertEqual(tabs.selectedPane, .about)
        XCTAssertEqual(UserDefaults.standard.string(forKey: Self.selectedPaneKey), "about")
    }

    func testAboutEntryPointSwitchesAnAlreadyOpenWindow() throws {
        let controller = SettingsWindowController(frameAutosaveName: autosaveName)
        XCTAssertEqual(try prepare(controller, selecting: nil).selectedPane, .general)
        XCTAssertEqual(try prepare(controller, selecting: .about).selectedPane, .about)
    }

    func testPlainShowKeepsTheLastSelectedPane() throws {
        let controller = SettingsWindowController(frameAutosaveName: autosaveName)
        _ = try prepare(controller, selecting: .about)
        XCTAssertEqual(try prepare(controller, selecting: nil).selectedPane, .about)
    }
}
