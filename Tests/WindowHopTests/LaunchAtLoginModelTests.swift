import Foundation
import Testing
import WindowHopTestSupport

@testable import WindowHopCore
@testable import WindowHopKit

extension SharedAppState {
    /// The Settings model over a fake login-item boundary: nothing here can touch
    /// the machine's real login items.
    @MainActor
    final class LaunchAtLoginModelTests {
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

        private let suite: TestDefaults
        private var defaults: UserDefaults { suite.defaults }

        init() throws {
            suite = try TestDefaults()
        }

        isolated deinit {
            suite.remove()
        }

        private func makeModel(_ fake: FakeLoginItem, preferences: Preferences) -> LaunchAtLoginModel {
            LaunchAtLoginModel(
                preferences: preferences,
                readStatus: { fake.status },
                change: fake.change,
                openLoginItemsSettings: { fake.settingsOpened += 1 })
        }

        @Test func startsFromTheReportedStatusNotTheStoredIntent() {
            let fake = FakeLoginItem()
            fake.status = .requiresApproval
            let preferences = Preferences(defaults: defaults)

            let model = makeModel(fake, preferences: preferences)

            #expect(model.status == .requiresApproval)
            #expect(!preferences.launchAtLogin)
        }

        /// A change made in System Settings while the retained window was open:
        /// refresh follows it, registers nothing and leaves the intent alone.
        @Test func refreshFollowsAnExternalChangeWithoutSideEffects() {
            let fake = FakeLoginItem()
            fake.status = .enabled
            let preferences = Preferences(defaults: defaults)
            preferences.launchAtLogin = true
            let model = makeModel(fake, preferences: preferences)

            fake.status = .disabled
            model.refresh()

            #expect(model.status == .disabled)
            #expect(fake.requests.isEmpty)
            #expect(preferences.launchAtLogin)
        }

        @Test func successfulRequestsRecordTheIntent() {
            let fake = FakeLoginItem()
            let preferences = Preferences(defaults: defaults)
            let model = makeModel(fake, preferences: preferences)

            model.request(true)
            #expect(model.status == .enabled)
            #expect(!model.failed)
            #expect(preferences.launchAtLogin)

            model.request(false)
            #expect(model.status == .disabled)
            #expect(!preferences.launchAtLogin)
        }

        @Test func pendingApprovalKeepsTheIntentAndOffersSettings() {
            let fake = FakeLoginItem()
            fake.nextChange = LoginItemChange(status: .requiresApproval, failed: false)
            let preferences = Preferences(defaults: defaults)
            let model = makeModel(fake, preferences: preferences)

            model.request(true)

            #expect(model.status == .requiresApproval)
            #expect(model.status.isOn)
            #expect(!model.failed)
            #expect(preferences.launchAtLogin)
            model.openLoginItemsSettings()
            #expect(fake.settingsOpened == 1)
        }

        @Test func failedRequestKeepsTheIntentAndReportsFailure() {
            let fake = FakeLoginItem()
            fake.nextChange = LoginItemChange(status: .disabled, failed: true)
            let preferences = Preferences(defaults: defaults)
            let model = makeModel(fake, preferences: preferences)

            model.request(true)

            #expect(model.failed)
            #expect(model.status == .disabled)
            #expect(!preferences.launchAtLogin)
            #expect(
                suite.persistentDomain?[Preferences.Key.launchAtLogin.rawValue] == nil,
                "a failed request must not store an intent")
        }

        /// Approving in System Settings after a failure: the new status replaces
        /// the stale failure message.
        @Test func aChangedStatusClearsAnEarlierFailure() {
            let fake = FakeLoginItem()
            fake.nextChange = LoginItemChange(status: .disabled, failed: true)
            let model = makeModel(fake, preferences: Preferences(defaults: defaults))
            model.request(true)

            model.refresh()
            #expect(model.failed, "an unchanged status keeps the failure visible")

            fake.status = .enabled
            model.refresh()
            #expect(!model.failed)
            #expect(model.status == .enabled)
        }
    }
}
