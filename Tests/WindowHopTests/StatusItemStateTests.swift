import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

/// The menu bar item's state is derived from the switcher preference and the
/// Accessibility grant, and every state must be distinguishable without color:
/// by symbol shape and by accessibility label.
struct StatusItemStateTests {
    @Test func resolutionTable() {
        #expect(StatusItemState.resolve(switcherEnabled: true, accessibilityGranted: true) == .active)
        #expect(StatusItemState.resolve(switcherEnabled: false, accessibilityGranted: true) == .paused)
        // enabling cannot help until access is granted, so missing permission wins
        #expect(
            StatusItemState.resolve(switcherEnabled: true, accessibilityGranted: false) == .accessibilityRequired)
        #expect(
            StatusItemState.resolve(switcherEnabled: false, accessibilityGranted: false) == .accessibilityRequired)
    }

    @Test func statesHaveDistinctShapesAndLabels() {
        let states = StatusItemState.allCases
        #expect(Set(states.map(\.symbolName)).count == states.count)
        #expect(Set(states.map(\.accessibilityLabel)).count == states.count)
    }

    @Test func labelsNameTheAppAndTheState() {
        for state in StatusItemState.allCases {
            #expect(state.accessibilityLabel.hasPrefix("WindowHop"))
        }
        #expect(StatusItemState.paused.accessibilityLabel.localizedCaseInsensitiveContains("paused"))
        #expect(
            StatusItemState.accessibilityRequired.accessibilityLabel
                .localizedCaseInsensitiveContains("Accessibility"))
    }

    @Test func onlyNonActiveStatesExplainThemselves() {
        #expect(StatusItemState.active.statusText == nil)
        #expect(StatusItemState.paused.statusText != nil)
        #expect(StatusItemState.accessibilityRequired.statusText != nil)
        #expect(StatusItemState.allCases.filter(\.offersAccessibilitySetup) == [.accessibilityRequired])
    }

    /// Guards the deployment floor: a symbol missing on the running macOS
    /// would leave the menu bar item blank.
    @Test func everySymbolResolves() {
        for state in StatusItemState.allCases {
            #expect(
                NSImage(systemSymbolName: state.symbolName, accessibilityDescription: nil) != nil, "\(state.symbolName)"
            )
        }
    }
}
