import AppKit
import Testing

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// Every Settings pane has the one pane width and is as tall as its content,
    /// up to the display's usable height (#121). General used to be taller than
    /// a laptop display, so the cap is part of the contract.
    @MainActor
    final class SettingsPaneLayoutTests {
        private var isolated: IsolatedPreferences!

        init() throws {
            isolated = try IsolatedPreferences()
        }

        isolated deinit {
            isolated.remove()
            isolated = nil
        }

        private static let unbounded = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)

        private func size(of pane: SettingsPane) -> CGSize {
            pane.makeViewController(isolated.settingsDependencies).sizeThatFits(in: Self.unbounded)
        }

        /// The tallest a pane may be on this machine's main display.
        private func heightCap() throws -> CGFloat {
            let usable = try #require(NSScreen.main).visibleFrame.height
            return max(
                usable - DesignTokens.settingsWindowChromeAllowance, DesignTokens.settingsPaneMinimumHeight)
        }

        @Test func everyPaneHasThePaneWidthAndFitsTheDisplay() throws {
            _ = NSApplication.shared
            let cap = try heightCap()
            for pane in SettingsPane.allCases {
                let size = size(of: pane)
                #expect(size.width == DesignTokens.settingsPaneWidth, "the \(pane.rawValue) pane width")
                #expect(size.height > 0)
                #expect(size.height <= cap, "the \(pane.rawValue) pane runs off the display")
            }
        }

        /// Panes differ in height: a fixed canvas left Shortcuts and Updates
        /// half empty in 2.0.0.
        @Test func panesFitTheirContent() {
            _ = NSApplication.shared
            let heights = Set(SettingsPane.allCases.map { size(of: $0).height })
            #expect(heights.count > 1)
        }

        /// The preview-only rows appear in Window Previews and nowhere else. On
        /// a display too short for the App Icons layout (a CI runner), both
        /// layouts stop at the cap and scroll instead.
        @Test func switcherPaneGrowsForWindowPreviews() throws {
            _ = NSApplication.shared
            let cap = try heightCap()
            isolated.preferences.appearanceMode = .appIcons
            let icons = size(of: .switcher).height
            isolated.preferences.appearanceMode = .windowPreviews
            let previews = size(of: .switcher).height
            if icons < cap {
                #expect(previews > icons)
            } else {
                #expect(previews == cap)
            }
        }

        @Test func paneIdentifiersAreUnique() {
            // the selected pane is restored by identifier, so duplicates would make
            // reopening Settings land on the wrong pane
            let identifiers = SettingsPane.allCases.map(\.rawValue)
            #expect(Set(identifiers).count == identifiers.count)
        }

        /// 2.0.0 saved one of six identifiers; each reopens the pane that holds
        /// its controls now.
        @Test func savedIdentifiersFromTwoPointZeroMapToTheirNewPanes() {
            let expected: [String: SettingsPane] = [
                "general": .general, "shortcuts": .shortcuts, "windows": .switcher,
                "appearance": .switcher, "updates": .about, "about": .about, "switcher": .switcher,
            ]
            for (saved, pane) in expected {
                #expect(SettingsPane(savedIdentifier: saved) == pane, "\(saved)")
            }
            #expect(SettingsPane(savedIdentifier: "unknown") == nil)
        }
    }
}
