import XCTest
@testable import WindowHopCore

final class TitleResolverTests: XCTestCase {
    func testWindowTitleWins() {
        XCTAssertEqual(TitleResolver.resolve(axTitle: "Report.pdf", documentPath: "/tmp/Other.txt", appName: "Preview"),
                       "Report.pdf")
    }

    func testEmptyTitleFallsBackToDocumentName() {
        XCTAssertEqual(TitleResolver.resolve(axTitle: "", documentPath: "/Users/me/Notes/Groceries.md", appName: "Editor"),
                       "Groceries.md")
    }

    func testWhitespaceTitleFallsBack() {
        XCTAssertEqual(TitleResolver.resolve(axTitle: "  \n ", documentPath: nil, appName: "Slack"), "Slack")
    }

    func testNilEverythingYieldsEmptyString() {
        XCTAssertEqual(TitleResolver.resolve(axTitle: nil, documentPath: nil, appName: nil), "")
    }

    func testPercentEncodedDocumentNameIsDecoded() {
        XCTAssertEqual(TitleResolver.resolve(axTitle: nil, documentPath: "file:///tmp/My%20Doc.txt", appName: "App"),
                       "My Doc.txt")
    }

    func testUnicodeTitlesPassThroughUnchanged() {
        for title in ["日本語のタイトル", "🚀 Deploy — prod", "עברית מימין לשמאל", "café ☕️"] {
            XCTAssertEqual(TitleResolver.resolve(axTitle: title, documentPath: nil, appName: "App"), title)
        }
    }
}
