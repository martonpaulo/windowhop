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
        XCTAssertTrue(WindowEligibility.shouldDisplay(visibleState(),
                                                      includeOtherSpaces: true,
                                                      includeOtherDisplays: true))
    }

    func testMinimizedWindowsAreNeverDisplayed() {
        var state = visibleState()
        state.isMinimized = true
        XCTAssertFalse(WindowEligibility.shouldDisplay(state, includeOtherSpaces: true, includeOtherDisplays: true))
    }

    func testHiddenAppWindowsAreNeverDisplayed() {
        var state = visibleState()
        state.isAppHidden = true
        XCTAssertFalse(WindowEligibility.shouldDisplay(state, includeOtherSpaces: true, includeOtherDisplays: true))
    }

    func testOwnWindowsAreNeverDisplayed() {
        var state = visibleState()
        state.isOwnWindow = true
        XCTAssertFalse(WindowEligibility.shouldDisplay(state, includeOtherSpaces: true, includeOtherDisplays: true))
    }

    func testPictureInPictureWindowsAreNeverDisplayed() {
        var state = visibleState()
        state.isPictureInPicture = true
        XCTAssertFalse(WindowEligibility.shouldDisplay(state, includeOtherSpaces: true, includeOtherDisplays: true))
    }

    func testOtherSpaceWindowsFollowTheSetting() {
        var state = visibleState()
        state.isOnCurrentSpace = false
        XCTAssertTrue(WindowEligibility.shouldDisplay(state, includeOtherSpaces: true, includeOtherDisplays: true))
        XCTAssertFalse(WindowEligibility.shouldDisplay(state, includeOtherSpaces: false, includeOtherDisplays: true))
    }

    func testOtherDisplayWindowsFollowTheSetting() {
        var state = visibleState()
        state.isOnActiveDisplay = false
        XCTAssertTrue(WindowEligibility.shouldDisplay(state, includeOtherSpaces: true, includeOtherDisplays: true))
        XCTAssertFalse(WindowEligibility.shouldDisplay(state, includeOtherSpaces: true, includeOtherDisplays: false))
    }
}
