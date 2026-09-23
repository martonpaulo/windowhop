import Foundation
import Testing

@testable import WindowHopKit

struct TitleResolverTests {
    @Test func windowTitleWins() {
        #expect(
            TitleResolver.resolve(axTitle: "Report.pdf", documentPath: "/tmp/Other.txt", appName: "Preview")
                == "Report.pdf")
    }

    @Test func emptyTitleFallsBackToDocumentName() {
        #expect(
            TitleResolver.resolve(axTitle: "", documentPath: "/Users/me/Notes/Groceries.md", appName: "Editor")
                == "Groceries.md")
    }

    @Test func whitespaceTitleFallsBack() {
        #expect(TitleResolver.resolve(axTitle: "  \n ", documentPath: nil, appName: "Slack") == "Slack")
    }

    @Test func nilEverythingYieldsEmptyString() {
        #expect(TitleResolver.resolve(axTitle: nil, documentPath: nil, appName: nil) == "")
    }

    @Test func percentEncodedDocumentNameIsDecoded() {
        #expect(
            TitleResolver.resolve(axTitle: nil, documentPath: "file:///tmp/My%20Doc.txt", appName: "App")
                == "My Doc.txt")
    }

    @Test func unicodeTitlesPassThroughUnchanged() {
        for title in ["日本語のタイトル", "🚀 Deploy — prod", "עברית מימין לשמאל", "café ☕️"] {
            #expect(TitleResolver.resolve(axTitle: title, documentPath: nil, appName: "App") == title)
        }
    }
}
