import Foundation
import Testing

@testable import WindowHopKit

struct WindowEligibilityTests {
    private func standardWindow(size: CGSize = CGSize(width: 800, height: 600)) -> WindowFacts {
        WindowFacts(
            role: "AXWindow", subrole: "AXStandardWindow", size: size,
            title: "Document", bundleIdentifier: "com.example.app",
            localizedAppName: "Example")
    }

    // MARK: - isActualWindow

    @Test func standardWindowIsActual() {
        #expect(WindowEligibility.isActualWindow(standardWindow()))
    }

    @Test func dialogIsActual() {
        var facts = standardWindow()
        facts.subrole = "AXDialog"
        #expect(WindowEligibility.isActualWindow(facts))
    }

    @Test func missingSizeIsRejected() {
        var facts = standardWindow()
        facts.size = nil
        #expect(!WindowEligibility.isActualWindow(facts))
    }

    @Test func tinySurfacesAreRejected() {
        #expect(!WindowEligibility.isActualWindow(standardWindow(size: CGSize(width: 90, height: 400))))
        #expect(!WindowEligibility.isActualWindow(standardWindow(size: CGSize(width: 400, height: 40))))
    }

    @Test func tooltipsAndMenusAreRejected() {
        for subrole in ["AXUnknown", "AXSystemDialog", nil] {
            var facts = standardWindow()
            facts.subrole = subrole
            #expect(!WindowEligibility.isActualWindow(facts), "subrole \(subrole ?? "nil")")
        }
    }

    @Test func jetbrainsNonWindowsWithoutTitleAreRejected() {
        var facts = standardWindow()
        facts.bundleIdentifier = "com.jetbrains.intellij"
        facts.subrole = "AXDialog"
        facts.title = ""
        #expect(!WindowEligibility.isActualWindow(facts))
        facts.title = "UserResourceMapper.java"
        #expect(WindowEligibility.isActualWindow(facts))
    }

    @Test func steamWindowsNeedTitleAndRole() {
        var facts = standardWindow()
        facts.bundleIdentifier = "com.valvesoftware.steam"
        facts.subrole = "AXUnknown"
        facts.title = "Library"
        #expect(WindowEligibility.isActualWindow(facts))
        facts.title = ""
        #expect(!WindowEligibility.isActualWindow(facts))
    }

    @Test func firefoxFullscreenVideoNeedsHeight() {
        var facts = standardWindow()
        facts.bundleIdentifier = "org.mozilla.firefox"
        facts.subrole = "AXUnknown"
        facts.size = CGSize(width: 1200, height: 300)
        #expect(!WindowEligibility.isActualWindow(facts))
        facts.size = CGSize(width: 1200, height: 800)
        #expect(WindowEligibility.isActualWindow(facts))
    }

    // MARK: - shouldDisplay

    private func visibleState() -> WindowDisplayState {
        WindowDisplayState(
            isMinimized: false, isAppHidden: false, isOwnWindow: false,
            isOnCurrentSpace: true, isOnActiveDisplay: true)
    }

    @Test func visibleWindowIsDisplayed() {
        #expect(WindowEligibility.shouldDisplay(visibleState(), policy: .init()))
    }

    @Test func minimizedWindowsFollowThePolicy() {
        var state = visibleState()
        state.isMinimized = true
        #expect(!WindowEligibility.shouldDisplay(state, policy: .init()))
        #expect(
            WindowEligibility.shouldDisplay(
                state, policy: .init(includeMinimizedWindows: true)))
    }

    @Test func hiddenAppWindowsFollowThePolicy() {
        var state = visibleState()
        state.isAppHidden = true
        #expect(!WindowEligibility.shouldDisplay(state, policy: .init()))
        #expect(
            WindowEligibility.shouldDisplay(
                state, policy: .init(includeHiddenApplicationWindows: true)))
    }

    @Test func ownWindowsAreNeverDisplayed() {
        var state = visibleState()
        state.isOwnWindow = true
        #expect(!WindowEligibility.shouldDisplay(state, policy: .init()))
        #expect(
            !WindowEligibility.shouldDisplay(
                state,
                policy: .init(
                    includeMinimizedWindows: true,
                    includeHiddenApplicationWindows: true,
                    includePictureInPictureWindows: true)))
    }

    @Test func pictureInPictureWindowsFollowThePolicy() {
        var state = visibleState()
        state.isPictureInPicture = true
        #expect(!WindowEligibility.shouldDisplay(state, policy: .init()))
        #expect(
            WindowEligibility.shouldDisplay(
                state, policy: .init(includePictureInPictureWindows: true)))
    }

    @Test func otherSpaceWindowsFollowTheSetting() {
        var state = visibleState()
        state.isOnCurrentSpace = false
        #expect(WindowEligibility.shouldDisplay(state, policy: .init()))
        #expect(
            !WindowEligibility.shouldDisplay(
                state, policy: .init(includeOtherSpaces: false)))
    }

    @Test func otherDisplayWindowsFollowTheSetting() {
        var state = visibleState()
        state.isOnActiveDisplay = false
        #expect(WindowEligibility.shouldDisplay(state, policy: .init()))
        #expect(
            !WindowEligibility.shouldDisplay(
                state, policy: .init(includeOtherDisplays: false)))
    }

    /// The #38 snapshot trace counts exclusions by the first rule that applies.
    @Test func exclusionReasonNamesTheFirstRuleThatApplies() {
        let strict = WindowInclusionPolicy(includeOtherSpaces: false, includeOtherDisplays: false)
        let offSpaceAndDisplay = WindowDisplayState(
            isMinimized: false, isAppHidden: false, isOwnWindow: false,
            isOnCurrentSpace: false, isOnActiveDisplay: false)
        #expect(WindowEligibility.exclusionReason(offSpaceAndDisplay, policy: strict) == .otherSpace)
        #expect(
            WindowEligibility.exclusionReason(offSpaceAndDisplay, policy: .init()) == nil,
            "the default policy shows other Spaces and displays")
        let minimizedTab = WindowDisplayState(
            isMinimized: true, isAppHidden: false, isOwnWindow: false,
            isTabbed: true, isOnCurrentSpace: true, isOnActiveDisplay: true)
        #expect(WindowEligibility.exclusionReason(minimizedTab, policy: .init()) == .minimized)
    }

    @Test func everyUserFacingPolicyCombination() {
        for stateBits in 0..<32 {
            let state = WindowDisplayState(
                isMinimized: stateBits & 1 != 0,
                isAppHidden: stateBits & 2 != 0,
                isOwnWindow: false,
                isPictureInPicture: stateBits & 4 != 0,
                isOnCurrentSpace: stateBits & 8 == 0,
                isOnActiveDisplay: stateBits & 16 == 0)

            for policyBits in 0..<32 {
                let policy = WindowInclusionPolicy(
                    includeMinimizedWindows: policyBits & 1 != 0,
                    includeHiddenApplicationWindows: policyBits & 2 != 0,
                    includePictureInPictureWindows: policyBits & 4 != 0,
                    includeOtherSpaces: policyBits & 8 != 0,
                    includeOtherDisplays: policyBits & 16 != 0)
                let expected =
                    (!state.isMinimized || policy.includeMinimizedWindows)
                    && (!state.isAppHidden || policy.includeHiddenApplicationWindows)
                    && (!state.isPictureInPicture
                        || policy.includePictureInPictureWindows)
                    && (state.isOnCurrentSpace || policy.includeOtherSpaces)
                    && (state.isOnActiveDisplay || policy.includeOtherDisplays)

                #expect(
                    WindowEligibility.shouldDisplay(state, policy: policy) == expected,
                    "state=\(stateBits), policy=\(policyBits)")
            }
        }
    }
}
