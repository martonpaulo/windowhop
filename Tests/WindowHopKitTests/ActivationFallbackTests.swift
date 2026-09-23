import Testing

@testable import WindowHopKit

/// The whole-app frontmost fall-back runs only when activation did not take (#41).
struct ActivationFallbackTests {
    @Test func noFallbackWhenTheTargetIsFocused() {
        #expect(!ActivationFallback.isNeeded(focusedPID: 42, targetPID: 42))
    }

    @Test func fallbackWhenAnotherAppKeepsFocus() {
        #expect(ActivationFallback.isNeeded(focusedPID: 7, targetPID: 42))
    }

    @Test func fallbackWhenFocusIsUnknown() {
        #expect(ActivationFallback.isNeeded(focusedPID: nil, targetPID: 42))
    }
}
