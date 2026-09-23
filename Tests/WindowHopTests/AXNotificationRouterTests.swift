import Foundation
import Testing

@testable import WindowHopCore

extension SharedAppState {
    /// The AX observer callback is a capture-free C function: it finds its router
    /// through the notification's `refcon`, and the router finds the store through a
    /// weak reference, so a late notification can never keep a store alive.
    @MainActor
    struct AXNotificationRouterTests {
        @Test func refconResolvesToTheSameRouter() throws {
            let isolated = try IsolatedPreferences()
            defer { isolated.remove() }
            let store = WindowStore(preferences: isolated.preferences, previews: isolated.previews)
            let router = store.router
            let resolved = Unmanaged<AXNotificationRouter>.fromOpaque(router.refcon)
                .takeUnretainedValue()
            #expect(resolved === router)
            #expect(router.store === store)
        }

        @Test func routerDoesNotKeepTheStoreAlive() throws {
            let isolated = try IsolatedPreferences()
            defer { isolated.remove() }
            var store: WindowStore? = WindowStore(
                preferences: isolated.preferences,
                previews: isolated.previews)
            weak let weakStore = store
            let router = store?.router
            store = nil
            #expect(weakStore == nil)
            #expect(router != nil)
            #expect(router?.store == nil)
        }
    }
}
