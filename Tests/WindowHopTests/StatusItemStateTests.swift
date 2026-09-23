import AppKit
import XCTest

@testable import WindowHopCore
@testable import WindowHopKit

/// The menu bar item's state is derived from the switcher preference and the
/// Accessibility grant, and every state must be distinguishable without color:
/// by symbol shape and by accessibility label.
final class StatusItemStateTests: XCTestCase {
    func testResolutionTable() {
        XCTAssertEqual(StatusItemState.resolve(switcherEnabled: true, accessibilityGranted: true), .active)
        XCTAssertEqual(StatusItemState.resolve(switcherEnabled: false, accessibilityGranted: true), .paused)
        // enabling cannot help until access is granted, so missing permission wins
        XCTAssertEqual(
            StatusItemState.resolve(switcherEnabled: true, accessibilityGranted: false),
            .accessibilityRequired)
        XCTAssertEqual(
            StatusItemState.resolve(switcherEnabled: false, accessibilityGranted: false),
            .accessibilityRequired)
    }

    func testStatesHaveDistinctShapesAndLabels() {
        let states = StatusItemState.allCases
        XCTAssertEqual(Set(states.map(\.symbolName)).count, states.count)
        XCTAssertEqual(Set(states.map(\.accessibilityLabel)).count, states.count)
    }

    func testLabelsNameTheAppAndTheState() {
        for state in StatusItemState.allCases {
            XCTAssertTrue(state.accessibilityLabel.hasPrefix("WindowHop"))
        }
        XCTAssertTrue(StatusItemState.paused.accessibilityLabel.localizedCaseInsensitiveContains("paused"))
        XCTAssertTrue(
            StatusItemState.accessibilityRequired.accessibilityLabel
                .localizedCaseInsensitiveContains("Accessibility"))
    }

    func testOnlyNonActiveStatesExplainThemselves() {
        XCTAssertNil(StatusItemState.active.statusText)
        XCTAssertNotNil(StatusItemState.paused.statusText)
        XCTAssertNotNil(StatusItemState.accessibilityRequired.statusText)
        XCTAssertEqual(StatusItemState.allCases.filter(\.offersAccessibilitySetup), [.accessibilityRequired])
    }

    /// Guards the deployment floor: a symbol missing on the running macOS
    /// would leave the menu bar item blank.
    func testEverySymbolResolves() {
        for state in StatusItemState.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: state.symbolName, accessibilityDescription: nil),
                state.symbolName)
        }
    }
}
