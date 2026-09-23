import XCTest
@testable import WindowHopCore
@testable import WindowHopKit

/// The Settings model over a fake login-item boundary: nothing here can touch
/// the machine's real login items.
@MainActor
final class LaunchAtLoginModelTests: XCTestCase {
    private final class FakeLoginItem {
        var status: LoginItemStatus = .disabled
        /// What a requested change leaves behind; nil means it succeeds as asked.
        var nextChange: LoginItemChange?
        var requests: [Bool] = []
        var settingsOpened = 0

        func change(_ on: Bool) -> LoginItemChange {
            requests.append(on)
            let result = nextChange ?? LoginItemChange(status: on ? .enabled : .disabled, failed: false)
            status = result.status
            return result
        }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "windowhop-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeModel(_ fake: FakeLoginItem, preferences: Preferences) -> LaunchAtLoginModel {
        LaunchAtLoginModel(preferences: preferences,
                           readStatus: { fake.status },
                           change: fake.change,
                           openLoginItemsSettings: { fake.settingsOpened += 1 })
    }

    func testStartsFromTheReportedStatusNotTheStoredIntent() {
        let fake = FakeLoginItem()
        fake.status = .requiresApproval
        let preferences = Preferences(defaults: defaults)

        let model = makeModel(fake, preferences: preferences)

        XCTAssertEqual(model.status, .requiresApproval)
        XCTAssertFalse(preferences.launchAtLogin)
    }

    /// A change made in System Settings while the retained window was open:
    /// refresh follows it, registers nothing and leaves the intent alone.
    func testRefreshFollowsAnExternalChangeWithoutSideEffects() {
        let fake = FakeLoginItem()
        fake.status = .enabled
        let preferences = Preferences(defaults: defaults)
        preferences.launchAtLogin = true
        let model = makeModel(fake, preferences: preferences)

        fake.status = .disabled
        model.refresh()

        XCTAssertEqual(model.status, .disabled)
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertTrue(preferences.launchAtLogin)
    }

    func testSuccessfulRequestsRecordTheIntent() {
        let fake = FakeLoginItem()
        let preferences = Preferences(defaults: defaults)
        let model = makeModel(fake, preferences: preferences)

        model.request(true)
        XCTAssertEqual(model.status, .enabled)
        XCTAssertFalse(model.failed)
        XCTAssertTrue(preferences.launchAtLogin)

        model.request(false)
        XCTAssertEqual(model.status, .disabled)
        XCTAssertFalse(preferences.launchAtLogin)
    }

    func testPendingApprovalKeepsTheIntentAndOffersSettings() {
        let fake = FakeLoginItem()
        fake.nextChange = LoginItemChange(status: .requiresApproval, failed: false)
        let preferences = Preferences(defaults: defaults)
        let model = makeModel(fake, preferences: preferences)

        model.request(true)

        XCTAssertEqual(model.status, .requiresApproval)
        XCTAssertTrue(model.status.isOn)
        XCTAssertFalse(model.failed)
        XCTAssertTrue(preferences.launchAtLogin)
        model.openLoginItemsSettings()
        XCTAssertEqual(fake.settingsOpened, 1)
    }

    func testFailedRequestKeepsTheIntentAndReportsFailure() {
        let fake = FakeLoginItem()
        fake.nextChange = LoginItemChange(status: .disabled, failed: true)
        let preferences = Preferences(defaults: defaults)
        let model = makeModel(fake, preferences: preferences)

        model.request(true)

        XCTAssertTrue(model.failed)
        XCTAssertEqual(model.status, .disabled)
        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?[Preferences.Key.launchAtLogin.rawValue],
                     "a failed request must not store an intent")
    }

    /// Approving in System Settings after a failure: the new status replaces
    /// the stale failure message.
    func testAChangedStatusClearsAnEarlierFailure() {
        let fake = FakeLoginItem()
        fake.nextChange = LoginItemChange(status: .disabled, failed: true)
        let model = makeModel(fake, preferences: Preferences(defaults: defaults))
        model.request(true)

        model.refresh()
        XCTAssertTrue(model.failed, "an unchanged status keeps the failure visible")

        fake.status = .enabled
        model.refresh()
        XCTAssertFalse(model.failed)
        XCTAssertEqual(model.status, .enabled)
    }
}
