import XCTest

@testable import WindowHopKit

/// Same-app windows sharing a displayed title get their document's parent folder,
/// and only when that folder actually tells them apart (issue #92).
final class CollisionLabelTests: XCTestCase {
    private typealias Entry = CollisionLabel.Entry<String>

    private func labels(_ entries: [Entry]) -> [String] {
        CollisionLabel.labels(for: entries)
    }

    func testDistinctTitlesAreUnchanged() {
        XCTAssertEqual(
            labels([
                Entry(appId: "TextEdit", title: "A.txt", documentPath: "file:///Users/me/Work/A.txt"),
                Entry(appId: "TextEdit", title: "B.txt", documentPath: "file:///Users/me/Home/B.txt"),
            ]), ["A.txt", "B.txt"])
    }

    func testCollisionSeparatedByFolderGetsTheFolderName() {
        XCTAssertEqual(
            labels([
                Entry(appId: "TextEdit", title: "Notes.txt", documentPath: "file:///Users/me/Work/Notes.txt"),
                Entry(appId: "TextEdit", title: "Notes.txt", documentPath: "file:///Users/me/Personal/Notes.txt"),
            ]), ["Notes.txt — Work", "Notes.txt — Personal"])
    }

    func testSameFolderAddsNothing() {
        XCTAssertEqual(
            labels([
                Entry(appId: "Preview", title: "Scan", documentPath: "file:///Users/me/Docs/Scan.pdf"),
                Entry(appId: "Preview", title: "Scan", documentPath: "file:///Users/me/Docs/Scan.png"),
            ]), ["Scan", "Scan"])
    }

    func testMissingDocumentsInventNothing() {
        XCTAssertEqual(
            labels([
                Entry(appId: "TextEdit", title: "Untitled", documentPath: nil),
                Entry(appId: "TextEdit", title: "Untitled", documentPath: nil),
            ]), ["Untitled", "Untitled"])
    }

    func testOnlyTheEntryWithADocumentIsQualified() {
        XCTAssertEqual(
            labels([
                Entry(appId: "Editor", title: "Draft", documentPath: "file:///Users/me/Blog/Draft"),
                Entry(appId: "Editor", title: "Draft", documentPath: nil),
            ]), ["Draft — Blog", "Draft"])
    }

    func testSameTitleInDifferentAppsIsNotACollision() {
        XCTAssertEqual(
            labels([
                Entry(appId: "TextEdit", title: "Notes.txt", documentPath: "file:///Users/me/Work/Notes.txt"),
                Entry(appId: "BBEdit", title: "Notes.txt", documentPath: "file:///Users/me/Home/Notes.txt"),
            ]), ["Notes.txt", "Notes.txt"])
    }

    func testLabelsDependOnMetadataNotPosition() {
        let work = Entry(appId: "TextEdit", title: "Notes.txt", documentPath: "file:///Users/me/Work/Notes.txt")
        let home = Entry(appId: "TextEdit", title: "Notes.txt", documentPath: "file:///Users/me/Home/Notes.txt")
        XCTAssertEqual(labels([work, home]), ["Notes.txt — Work", "Notes.txt — Home"])
        XCTAssertEqual(labels([home, work]), ["Notes.txt — Home", "Notes.txt — Work"])
    }

    func testParentFolderNameHandlesPathsAndEncoding() {
        XCTAssertEqual(CollisionLabel.parentFolderName(of: "file:///Users/me/My%20Files/a.txt"), "My Files")
        XCTAssertEqual(CollisionLabel.parentFolderName(of: "/Users/me/Plain/a.txt"), "Plain")
        XCTAssertNil(CollisionLabel.parentFolderName(of: "file:///a.txt"))
        XCTAssertNil(CollisionLabel.parentFolderName(of: "https://example.com/folder/a.txt"))
        XCTAssertNil(CollisionLabel.parentFolderName(of: ""))
        XCTAssertNil(CollisionLabel.parentFolderName(of: nil))
    }
}
