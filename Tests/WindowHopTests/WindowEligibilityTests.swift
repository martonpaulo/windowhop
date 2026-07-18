import XCTest
@testable import WindowHopCore

final class WindowEligibilityTests: XCTestCase {
    private func standardWindow(size: CGSize = CGSize(width: 800, height: 600)) -> WindowFacts {
        WindowFacts(role: "AXWindow", subrole: "AXStandardWindow", size: size,
                    title: "Document", bundleIdentifier: "com.example.app",
                    localizedAppName: "Example")
    }

    // MARK: - isActualWindow

    func testStandardWindowIsActual() {
        XCTAssertTrue(WindowEligibility.isActualWindow(standardWindow()))
    }

    func testDialogIsActual() {
        var facts = standardWindow()
        facts.subrole = "AXDialog"
        XCTAssertTrue(WindowEligibility.isActualWindow(facts))
    }

    func testMissingSizeIsRejected() {
        var facts = standardWindow()
        facts.size = nil
        XCTAssertFalse(WindowEligibility.isActualWindow(facts))
    }

    func testTinySurfacesAreRejected() {
        XCTAssertFalse(WindowEligibility.isActualWindow(standardWindow(size: CGSize(width: 90, height: 400))))
        XCTAssertFalse(WindowEligibility.isActualWindow(standardWindow(size: CGSize(width: 400, height: 40))))
    }

    func testTooltipsAndMenusAreRejected() {
        for subrole in ["AXUnknown", "AXSystemDialog", nil] {
            var facts = standardWindow()
            facts.subrole = subrole
            XCTAssertFalse(WindowEligibility.isActualWindow(facts), "subrole \(subrole ?? "nil")")
        }
    }

    func testJetbrainsNonWindowsWithoutTitleAreRejected() {
        var facts = standardWindow()
        facts.bundleIdentifier = "com.jetbrains.intellij"
        facts.subrole = "AXDialog"
        facts.title = ""
        XCTAssertFalse(WindowEligibility.isActualWindow(facts))
        facts.title = "UserResourceMapper.java"
        XCTAssertTrue(WindowEligibility.isActualWindow(facts))
    }

    func testSteamWindowsNeedTitleAndRole() {
        var facts = standardWindow()
        facts.bundleIdentifier = "com.valvesoftware.steam"
        facts.subrole = "AXUnknown"
        facts.title = "Library"
        XCTAssertTrue(WindowEligibility.isActualWindow(facts))
        facts.title = ""
        XCTAssertFalse(WindowEligibility.isActualWindow(facts))
    }

    func testFirefoxFullscreenVideoNeedsHeight() {
        var facts = standardWindow()
        facts.bundleIdentifier = "org.mozilla.firefox"
        facts.subrole = "AXUnknown"
        facts.size = CGSize(width: 1200, height: 300)
        XCTAssertFalse(WindowEligibility.isActualWindow(facts))
        facts.size = CGSize(width: 1200, height: 800)
        XCTAssertTrue(WindowEligibility.isActualWindow(facts))
    }

    // MARK: - shouldDisplay

    private func visibleState() -> WindowDisplayState {
        WindowDisplayState(isMinimized: false, isAppHidden: false, isOwnWindow: false,
                           isOnCurrentSpace: true, isOnActiveDisplay: true)
    }

    func testVisibleWindowIsDisplayed() {
        XCTAssertTrue(WindowEligibility.shouldDisplay(visibleState(), policy: .init()))
    }

    func testMinimizedWindowsFollowThePolicy() {
        var state = visibleState()
        state.isMinimized = true
        XCTAssertFalse(WindowEligibility.shouldDisplay(state, policy: .init()))
        XCTAssertTrue(WindowEligibility.shouldDisplay(
            state, policy: .init(includeMinimizedWindows: true)))
    }

    func testHiddenAppWindowsFollowThePolicy() {
        var state = visibleState()
        state.isAppHidden = true
        XCTAssertFalse(WindowEligibility.shouldDisplay(state, policy: .init()))
        XCTAssertTrue(WindowEligibility.shouldDisplay(
            state, policy: .init(includeHiddenApplicationWindows: true)))
    }

    func testOwnWindowsAreNeverDisplayed() {
        var state = visibleState()
        state.isOwnWindow = true
        XCTAssertFalse(WindowEligibility.shouldDisplay(state, policy: .init()))
        XCTAssertFalse(WindowEligibility.shouldDisplay(
            state,
            policy: .init(includeMinimizedWindows: true,
                          includeHiddenApplicationWindows: true,
                          includePictureInPictureWindows: true)))
    }

    func testPictureInPictureWindowsFollowThePolicy() {
        var state = visibleState()
        state.isPictureInPicture = true
        XCTAssertFalse(WindowEligibility.shouldDisplay(state, policy: .init()))
        XCTAssertTrue(WindowEligibility.shouldDisplay(
            state, policy: .init(includePictureInPictureWindows: true)))
    }

    func testOtherSpaceWindowsFollowTheSetting() {
        var state = visibleState()
        state.isOnCurrentSpace = false
        XCTAssertTrue(WindowEligibility.shouldDisplay(state, policy: .init()))
        XCTAssertFalse(WindowEligibility.shouldDisplay(
            state, policy: .init(includeOtherSpaces: false)))
    }

    func testOtherDisplayWindowsFollowTheSetting() {
        var state = visibleState()
        state.isOnActiveDisplay = false
        XCTAssertTrue(WindowEligibility.shouldDisplay(state, policy: .init()))
        XCTAssertFalse(WindowEligibility.shouldDisplay(
            state, policy: .init(includeOtherDisplays: false)))
    }

    func testEveryUserFacingPolicyCombination() {
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
                let expected = (!state.isMinimized || policy.includeMinimizedWindows)
                    && (!state.isAppHidden || policy.includeHiddenApplicationWindows)
                    && (!state.isPictureInPicture
                        || policy.includePictureInPictureWindows)
                    && (state.isOnCurrentSpace || policy.includeOtherSpaces)
                    && (state.isOnActiveDisplay || policy.includeOtherDisplays)

                XCTAssertEqual(
                    WindowEligibility.shouldDisplay(state, policy: policy),
                    expected,
                    "state=\(stateBits), policy=\(policyBits)")
            }
        }
    }
}
