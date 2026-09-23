import Foundation
import Testing

@testable import WindowHopKit

/// Same-app windows sharing a displayed title get their document's parent folder,
/// and only when that folder actually tells them apart (issue #92).
struct CollisionLabelTests {
    private typealias Entry = CollisionLabel.Entry<String>

    private func labels(_ entries: [Entry]) -> [String] {
        CollisionLabel.labels(for: entries)
    }

    @Test func distinctTitlesAreUnchanged() {
        #expect(
            labels([
                Entry(appId: "TextEdit", title: "A.txt", documentPath: "file:///Users/me/Work/A.txt"),
                Entry(appId: "TextEdit", title: "B.txt", documentPath: "file:///Users/me/Home/B.txt"),
            ]) == ["A.txt", "B.txt"])
    }

    @Test func collisionSeparatedByFolderGetsTheFolderName() {
        #expect(
            labels([
                Entry(appId: "TextEdit", title: "Notes.txt", documentPath: "file:///Users/me/Work/Notes.txt"),
                Entry(appId: "TextEdit", title: "Notes.txt", documentPath: "file:///Users/me/Personal/Notes.txt"),
            ]) == ["Notes.txt — Work", "Notes.txt — Personal"])
    }

    @Test func sameFolderAddsNothing() {
        #expect(
            labels([
                Entry(appId: "Preview", title: "Scan", documentPath: "file:///Users/me/Docs/Scan.pdf"),
                Entry(appId: "Preview", title: "Scan", documentPath: "file:///Users/me/Docs/Scan.png"),
            ]) == ["Scan", "Scan"])
    }

    @Test func missingDocumentsInventNothing() {
        #expect(
            labels([
                Entry(appId: "TextEdit", title: "Untitled", documentPath: nil),
                Entry(appId: "TextEdit", title: "Untitled", documentPath: nil),
            ]) == ["Untitled", "Untitled"])
    }

    @Test func onlyTheEntryWithADocumentIsQualified() {
        #expect(
            labels([
                Entry(appId: "Editor", title: "Draft", documentPath: "file:///Users/me/Blog/Draft"),
                Entry(appId: "Editor", title: "Draft", documentPath: nil),
            ]) == ["Draft — Blog", "Draft"])
    }

    @Test func sameTitleInDifferentAppsIsNotACollision() {
        #expect(
            labels([
                Entry(appId: "TextEdit", title: "Notes.txt", documentPath: "file:///Users/me/Work/Notes.txt"),
                Entry(appId: "BBEdit", title: "Notes.txt", documentPath: "file:///Users/me/Home/Notes.txt"),
            ]) == ["Notes.txt", "Notes.txt"])
    }

    @Test func labelsDependOnMetadataNotPosition() {
        let work = Entry(appId: "TextEdit", title: "Notes.txt", documentPath: "file:///Users/me/Work/Notes.txt")
        let home = Entry(appId: "TextEdit", title: "Notes.txt", documentPath: "file:///Users/me/Home/Notes.txt")
        #expect(labels([work, home]) == ["Notes.txt — Work", "Notes.txt — Home"])
        #expect(labels([home, work]) == ["Notes.txt — Home", "Notes.txt — Work"])
    }

    @Test func parentFolderNameHandlesPathsAndEncoding() {
        #expect(CollisionLabel.parentFolderName(of: "file:///Users/me/My%20Files/a.txt") == "My Files")
        #expect(CollisionLabel.parentFolderName(of: "/Users/me/Plain/a.txt") == "Plain")
        #expect(CollisionLabel.parentFolderName(of: "file:///a.txt") == nil)
        #expect(CollisionLabel.parentFolderName(of: "https://example.com/folder/a.txt") == nil)
        #expect(CollisionLabel.parentFolderName(of: "") == nil)
        #expect(CollisionLabel.parentFolderName(of: nil) == nil)
    }
}
