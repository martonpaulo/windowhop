import AppKit
import XCTest
@testable import WindowHopCore

/// Selecting a Settings pane must never resize the window: General used to be
/// tall enough to run off a laptop display while Updates was a third of it.
/// Every pane renders into the one shared canvas.
@MainActor
final class SettingsPaneLayoutTests: XCTestCase {
    func testEveryPaneRendersIntoTheSameCanvas() {
        _ = NSApplication.shared
        let canvas = CGSize(width: DesignTokens.settingsPaneWidth,
                            height: DesignTokens.settingsPaneHeight)
        XCTAssertGreaterThan(SettingsPane.allCases.count, 1)
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude,
                               height: CGFloat.greatestFiniteMagnitude)
        for pane in SettingsPane.allCases {
            XCTAssertEqual(pane.makeViewController().sizeThatFits(in: unbounded), canvas,
                           "the \(pane.rawValue) pane resizes the Settings window")
        }
    }

    func testPaneIdentifiersAreUnique() {
        // the selected pane is restored by identifier, so duplicates would make
        // reopening Settings land on the wrong pane
        let identifiers = SettingsPane.allCases.map(\.rawValue)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }
}
