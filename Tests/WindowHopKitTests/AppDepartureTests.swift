import Foundation
import Testing

@testable import WindowHopKit

/// The departure rule never trusts a departed app's process identifier (#136).
struct AppDepartureTests {
    /// Stands in for `NSRunningApplication`: `token` is the process identity that
    /// `isEqual` compares, `processIdentifier` what the object reports.
    private struct FakeApp {
        let token: Int
        let processIdentifier: Int32
    }

    private static func keysToRemove(
        tracked: [Int32: FakeApp], departed: [FakeApp], stillListed: [FakeApp] = []
    ) -> [Int32] {
        AppDeparture.keysToRemove(
            tracked: tracked, departed: departed, stillListed: stillListed,
            isSameProcess: { $0.token == $1.token })
    }

    @Test func aDepartedAppReportingNoProcessIdentifierIsRemoved() {
        let tracked: [Int32: FakeApp] = [42: FakeApp(token: 1, processIdentifier: 42)]
        let departed = FakeApp(token: 1, processIdentifier: -1)

        #expect(Self.keysToRemove(tracked: tracked, departed: [departed]) == [42])
    }

    @Test func aNewProcessReusingTheIdentifierIsKept() {
        let tracked: [Int32: FakeApp] = [42: FakeApp(token: 2, processIdentifier: 42)]
        let departed = FakeApp(token: 1, processIdentifier: 42)

        #expect(Self.keysToRemove(tracked: tracked, departed: [departed]).isEmpty)
    }

    @Test func anAppThatIsStillListedIsKept() {
        let finder = FakeApp(token: 1, processIdentifier: 42)

        #expect(
            Self.keysToRemove(tracked: [42: finder], departed: [finder], stillListed: [finder]).isEmpty)
    }

    @Test func aDepartureThatWasNeverTrackedRemovesNothing() {
        let tracked: [Int32: FakeApp] = [42: FakeApp(token: 1, processIdentifier: 42)]
        let departed = FakeApp(token: 3, processIdentifier: -1)

        #expect(Self.keysToRemove(tracked: tracked, departed: [departed]).isEmpty)
    }

    @Test func severalDeparturesRemoveEachTrackedAppOnce() {
        let first = FakeApp(token: 1, processIdentifier: 10)
        let second = FakeApp(token: 2, processIdentifier: 20)
        let kept = FakeApp(token: 3, processIdentifier: 30)
        let tracked: [Int32: FakeApp] = [10: first, 20: second, 30: kept]
        let departed = [
            FakeApp(token: 2, processIdentifier: -1), FakeApp(token: 1, processIdentifier: 10),
            FakeApp(token: 2, processIdentifier: 20),
        ]

        #expect(Self.keysToRemove(tracked: tracked, departed: departed) == [20, 10])
    }
}
