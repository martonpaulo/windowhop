import Carbon.HIToolbox
import XCTest
@testable import WindowHopCore

/// The live translator. Installed Apple layouts are read by identifier without
/// selecting or enabling them, and nothing asserts the machine's own layout.
final class KeyboardLayoutTests: XCTestCase {
    private func layout(_ identifier: String) throws -> TISInputSource {
        try XCTUnwrap(KeyboardLayout.installedLayout(identifier: identifier),
                      "\(identifier) is not installed", file: #filePath, line: #line)
    }

    private func characters(_ keyCodes: [UInt16], in identifier: String) throws -> [String?] {
        let source = try layout(identifier)
        return keyCodes.map { KeyboardLayout.character(forKeyCode: $0, in: source) }
    }

    func testInstalledLayoutsTranslatePhysicalKeys() throws {
        XCTAssertEqual(try characters([0, 6, 12], in: "com.apple.keylayout.US"), ["a", "z", "q"])
        XCTAssertEqual(try characters([6, 16], in: "com.apple.keylayout.German"), ["y", "z"])
        XCTAssertEqual(try characters([0, 12], in: "com.apple.keylayout.French"), ["q", "a"])
    }

    /// A dead key (French ^, key code 33) names itself rather than returning
    /// an empty string that waits for the next key.
    func testDeadKeyTranslatesToItsOwnCharacter() throws {
        XCTAssertEqual(try characters([33], in: "com.apple.keylayout.French"), ["^"])
    }

    func testCurrentLayoutOnMainReturnsNilOrOneCharacter() {
        let character = KeyboardLayout.current.character(forKeyCode: 0)
        if let character {
            XCTAssertEqual(character.count, 1)
        }
    }

    func testCurrentLayoutOffMainReturnsNil() {
        let done = expectation(description: "off-main translation")
        DispatchQueue.global().async {
            XCTAssertNil(KeyboardLayout.current.character(forKeyCode: 0))
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}
