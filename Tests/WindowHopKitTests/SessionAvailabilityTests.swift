import XCTest
@testable import WindowHopKit

/// #38: a locked screen makes every app publish zero windows, so nothing learned while
/// the session cannot report windows may prune a window or move it off the current Space,
/// and the return to a usable session asks for one recovery re-enumeration.
final class SessionAvailabilityTests: XCTestCase {
    private let tracked = ["a", "b", "c"]

    // MARK: - Space membership while locked

    func testEnumerationWhileLockedIsUnavailable() {
        var session = SessionAvailability()
        session.apply(.screenLocked)
        // what an app publishes over AX while the screen is locked: zero windows
        let result = SpaceMembership.reconcile(tracked: tracked, enumeration: .listed([]),
                                               session: session, readEpoch: session.epoch)
        XCTAssertTrue(result.currentSpace.isEmpty, "a locked read may not move any window off-Space")
        XCTAssertTrue(result.suspects.isEmpty, "a locked read may not make any window a prune suspect")
    }

    func testReadThatSpansALockIsUnavailableAfterTheUnlock() {
        var session = SessionAvailability()
        let readEpoch = session.epoch
        session.apply(.screenLocked)
        session.apply(.screenUnlocked)
        let result = SpaceMembership.reconcile(tracked: tracked, enumeration: .listed([]),
                                               session: session, readEpoch: readEpoch)
        XCTAssertTrue(result.currentSpace.isEmpty, "a read started before the lock was taken in the dark")
        XCTAssertTrue(result.suspects.isEmpty)
    }

    func testRecoveryRefreshRestoresFlagsAfterUnlock() {
        var session = SessionAvailability()
        var flags = ["a": true, "b": false, "c": true]
        XCTAssertFalse(session.apply(.screenLocked), "locking asks for no refresh")
        let locked = SpaceMembership.reconcile(tracked: tracked, enumeration: .listed([]),
                                               session: session, readEpoch: session.epoch)
        flags.merge(locked.currentSpace) { _, new in new }
        XCTAssertEqual(flags, ["a": true, "b": false, "c": true], "the locked read kept every flag")

        XCTAssertTrue(session.apply(.screenUnlocked), "the unlock asks for one recovery re-enumeration")
        let recovery = SpaceMembership.reconcile(tracked: tracked, enumeration: .listed(["a", "b"]),
                                                 session: session, readEpoch: session.epoch)
        flags.merge(recovery.currentSpace) { _, new in new }
        XCTAssertEqual(flags, ["a": true, "b": true, "c": false], "the recovery read is the truth")
        XCTAssertEqual(recovery.suspects, ["c"])
    }

    func testUsableSessionKeepsTodaysReconciliation() {
        let session = SessionAvailability()
        let result = SpaceMembership.reconcile(tracked: tracked, enumeration: .listed([]),
                                               session: session, readEpoch: session.epoch)
        XCTAssertEqual(result.currentSpace, ["a": false, "b": false, "c": false],
                       "an empty success in a usable session still marks windows off-Space")
        XCTAssertEqual(result.suspects, tracked)
    }

    // MARK: - Pruning while locked

    func testNothingIsPrunedWhileLocked() {
        var session = SessionAvailability()
        session.apply(.screenLocked)
        XCTAssertEqual(SpaceMembership.confirmedDead(tracked, session: session, readEpoch: session.epoch), [],
                       "a liveness probe in the dark proves nothing")
        XCTAssertFalse(SpaceMembership.acceptsDestroyNotification(session: session),
                       "a destroy notification in the dark waits for the recovery pass")

        let probeEpoch = session.epoch
        session.apply(.screenUnlocked)
        XCTAssertEqual(SpaceMembership.confirmedDead(tracked, session: session, readEpoch: probeEpoch), [],
                       "a probe started while locked stays void after the unlock")
        XCTAssertEqual(SpaceMembership.confirmedDead(["b"], session: session, readEpoch: session.epoch), ["b"])
        XCTAssertTrue(SpaceMembership.acceptsDestroyNotification(session: session))
    }

    // MARK: - Transitions

    func testEachConditionBlocksUntilItsOwnEventClearsIt() {
        let pairs: [(SessionAvailability.Event, SessionAvailability.Event)] = [
            (.screenLocked, .screenUnlocked),
            (.sessionResignedActive, .sessionBecameActive),
            (.systemWillSleep, .systemDidWake),
        ]
        for (enter, leave) in pairs {
            var session = SessionAvailability()
            XCTAssertFalse(session.apply(enter))
            XCTAssertFalse(session.isUsable, "\(enter) makes the session unusable")
            XCTAssertTrue(session.apply(leave), "\(leave) asks for recovery")
            XCTAssertTrue(session.isUsable)
        }
    }

    func testSleepingDisplaysDoNotBlockButTheirWakeAsksForRecovery() {
        var session = SessionAvailability()
        XCTAssertFalse(session.apply(.displaysSlept))
        XCTAssertTrue(session.isUsable, "a Screen Sharing session can run while the physical displays sleep")
        XCTAssertTrue(session.trusts(readStartedAt: session.epoch))
        XCTAssertTrue(session.apply(.displaysWoke), "the wake still asks for one recovery pass")
    }

    func testRecoveryIsAskedOnceWhenTheLastConditionClears() {
        var session = SessionAvailability()
        session.apply(.systemWillSleep)
        session.apply(.displaysSlept)
        session.apply(.screenLocked)
        XCTAssertFalse(session.apply(.systemDidWake), "still dark: the screen is locked")
        XCTAssertFalse(session.apply(.displaysWoke), "the lock screen shows: still locked")
        XCTAssertTrue(session.apply(.screenUnlocked), "only the unlock makes the session usable")
        XCTAssertFalse(session.apply(.screenUnlocked), "a repeated unlock asks for nothing")
        XCTAssertFalse(session.apply(.displaysWoke), "a wake without a sleep asks for nothing")
    }

    func testWakeWithoutLockAsksForOneRecoveryPass() {
        var session = SessionAvailability()
        session.apply(.displaysSlept)
        session.apply(.systemWillSleep)
        XCTAssertTrue(session.apply(.systemDidWake))
        XCTAssertFalse(session.apply(.displaysWoke), "the system wake already ran the recovery pass")
    }

    func testEpochChangesOnlyWithUsability() {
        var session = SessionAvailability()
        let start = session.epoch
        session.apply(.sessionBecameActive)
        session.apply(.displaysSlept)
        XCTAssertEqual(session.epoch, start, "an event that keeps the session usable keeps in-flight reads valid")
        session.apply(.screenLocked)
        session.apply(.systemWillSleep)
        XCTAssertEqual(session.epoch, start + 1, "a second condition does not change usability")
        XCTAssertFalse(session.trusts(readStartedAt: session.epoch), "no read is trusted while unusable")
    }
}
