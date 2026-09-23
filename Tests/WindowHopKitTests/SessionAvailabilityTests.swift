import Foundation
import Testing

@testable import WindowHopKit

/// #38: a locked screen makes every app publish zero windows, so nothing learned while
/// the session cannot report windows may prune a window or move it off the current Space,
/// and the return to a usable session asks for one recovery re-enumeration.
struct SessionAvailabilityTests {
    private let tracked = ["a", "b", "c"]

    // MARK: - Space membership while locked

    @Test func enumerationWhileLockedIsUnavailable() {
        var session = SessionAvailability()
        session.apply(.screenLocked)
        // what an app publishes over AX while the screen is locked: zero windows
        let result = SpaceMembership.reconcile(
            tracked: tracked, enumeration: .listed([]),
            session: session, readEpoch: session.epoch)
        #expect(result.currentSpace.isEmpty, "a locked read may not move any window off-Space")
        #expect(result.suspects.isEmpty, "a locked read may not make any window a prune suspect")
    }

    @Test func readThatSpansALockIsUnavailableAfterTheUnlock() {
        var session = SessionAvailability()
        let readEpoch = session.epoch
        session.apply(.screenLocked)
        session.apply(.screenUnlocked)
        let result = SpaceMembership.reconcile(
            tracked: tracked, enumeration: .listed([]),
            session: session, readEpoch: readEpoch)
        #expect(result.currentSpace.isEmpty, "a read started before the lock was taken in the dark")
        #expect(result.suspects.isEmpty)
    }

    @Test func recoveryRefreshRestoresFlagsAfterUnlock() {
        var session = SessionAvailability()
        var flags = ["a": true, "b": false, "c": true]
        #expect(session.apply(.screenLocked) == false, "locking asks for no refresh")
        let locked = SpaceMembership.reconcile(
            tracked: tracked, enumeration: .listed([]),
            session: session, readEpoch: session.epoch)
        flags.merge(locked.currentSpace) { _, new in new }
        #expect(flags == ["a": true, "b": false, "c": true], "the locked read kept every flag")

        #expect(session.apply(.screenUnlocked) == true, "the unlock asks for one recovery re-enumeration")
        let recovery = SpaceMembership.reconcile(
            tracked: tracked, enumeration: .listed(["a", "b"]),
            session: session, readEpoch: session.epoch)
        flags.merge(recovery.currentSpace) { _, new in new }
        #expect(flags == ["a": true, "b": true, "c": false], "the recovery read is the truth")
        #expect(recovery.suspects == ["c"])
    }

    @Test func usableSessionKeepsTodaysReconciliation() {
        let session = SessionAvailability()
        let result = SpaceMembership.reconcile(
            tracked: tracked, enumeration: .listed([]),
            session: session, readEpoch: session.epoch)
        #expect(
            result.currentSpace == ["a": false, "b": false, "c": false],
            "an empty success in a usable session still marks windows off-Space")
        #expect(result.suspects == tracked)
    }

    // MARK: - Pruning while locked

    @Test func nothingIsPrunedWhileLocked() {
        var session = SessionAvailability()
        session.apply(.screenLocked)
        #expect(
            SpaceMembership.confirmedDead(tracked, session: session, readEpoch: session.epoch) == [],
            "a liveness probe in the dark proves nothing")
        #expect(
            !SpaceMembership.acceptsDestroyNotification(session: session),
            "a destroy notification in the dark waits for the recovery pass")

        let probeEpoch = session.epoch
        session.apply(.screenUnlocked)
        #expect(
            SpaceMembership.confirmedDead(tracked, session: session, readEpoch: probeEpoch) == [],
            "a probe started while locked stays void after the unlock")
        #expect(SpaceMembership.confirmedDead(["b"], session: session, readEpoch: session.epoch) == ["b"])
        #expect(SpaceMembership.acceptsDestroyNotification(session: session))
    }

    // MARK: - Transitions

    @Test func eachConditionBlocksUntilItsOwnEventClearsIt() {
        let pairs: [(SessionAvailability.Event, SessionAvailability.Event)] = [
            (.screenLocked, .screenUnlocked),
            (.sessionResignedActive, .sessionBecameActive),
            (.systemWillSleep, .systemDidWake),
        ]
        for (enter, leave) in pairs {
            var session = SessionAvailability()
            #expect(session.apply(enter) == false)
            #expect(!session.isUsable, "\(enter) makes the session unusable")
            #expect(session.apply(leave) == true, "\(leave) asks for recovery")
            #expect(session.isUsable)
        }
    }

    @Test func sleepingDisplaysDoNotBlockButTheirWakeAsksForRecovery() {
        var session = SessionAvailability()
        #expect(session.apply(.displaysSlept) == false)
        #expect(session.isUsable, "a Screen Sharing session can run while the physical displays sleep")
        #expect(session.trusts(readStartedAt: session.epoch))
        #expect(session.apply(.displaysWoke) == true, "the wake still asks for one recovery pass")
    }

    @Test func recoveryIsAskedOnceWhenTheLastConditionClears() {
        var session = SessionAvailability()
        session.apply(.systemWillSleep)
        session.apply(.displaysSlept)
        session.apply(.screenLocked)
        #expect(session.apply(.systemDidWake) == false, "still dark: the screen is locked")
        #expect(session.apply(.displaysWoke) == false, "the lock screen shows: still locked")
        #expect(session.apply(.screenUnlocked) == true, "only the unlock makes the session usable")
        #expect(session.apply(.screenUnlocked) == false, "a repeated unlock asks for nothing")
        #expect(session.apply(.displaysWoke) == false, "a wake without a sleep asks for nothing")
    }

    @Test func wakeWithoutLockAsksForOneRecoveryPass() {
        var session = SessionAvailability()
        session.apply(.displaysSlept)
        session.apply(.systemWillSleep)
        #expect(session.apply(.systemDidWake) == true)
        #expect(session.apply(.displaysWoke) == false, "the system wake already ran the recovery pass")
    }

    @Test func epochChangesOnlyWithUsability() {
        var session = SessionAvailability()
        let start = session.epoch
        session.apply(.sessionBecameActive)
        session.apply(.displaysSlept)
        #expect(session.epoch == start, "an event that keeps the session usable keeps in-flight reads valid")
        session.apply(.screenLocked)
        session.apply(.systemWillSleep)
        #expect(session.epoch == start + 1, "a second condition does not change usability")
        #expect(!session.trusts(readStartedAt: session.epoch), "no read is trusted while unusable")
    }
}
