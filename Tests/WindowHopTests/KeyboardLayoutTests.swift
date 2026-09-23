import Carbon.HIToolbox
import Foundation
import Testing

@testable import WindowHopCore

/// The live translator. Installed Apple layouts are read by identifier without
/// selecting or enabling them, and nothing asserts the machine's own layout.
/// Text Input Sources answer on the main thread, where XCTest ran every test.
@MainActor
struct KeyboardLayoutTests {
    private func layout(_ identifier: String) throws -> TISInputSource {
        try #require(
            KeyboardLayout.installedLayout(identifier: identifier),
            "\(identifier) is not installed")
    }

    private func characters(_ keyCodes: [UInt16], in identifier: String) throws -> [String?] {
        let source = try layout(identifier)
        return keyCodes.map { KeyboardLayout.character(forKeyCode: $0, in: source) }
    }

    @Test func installedLayoutsTranslatePhysicalKeys() throws {
        #expect(try characters([0, 6, 12], in: "com.apple.keylayout.US") == ["a", "z", "q"])
        #expect(try characters([6, 16], in: "com.apple.keylayout.German") == ["y", "z"])
        #expect(try characters([0, 12], in: "com.apple.keylayout.French") == ["q", "a"])
    }

    /// A dead key (French ^, key code 33) names itself rather than returning
    /// an empty string that waits for the next key.
    @Test func deadKeyTranslatesToItsOwnCharacter() throws {
        #expect(try characters([33], in: "com.apple.keylayout.French") == ["^"])
    }

    @Test func currentLayoutOnMainReturnsNilOrOneCharacter() {
        let character = KeyboardLayout.current.character(forKeyCode: 0)
        if let character {
            #expect(character.count == 1)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func currentLayoutOffMainReturnsNil() async {
        await withCheckedContinuation { done in
            DispatchQueue.global().async {
                #expect(KeyboardLayout.current.character(forKeyCode: 0) == nil)
                done.resume()
            }
        }
    }
}
