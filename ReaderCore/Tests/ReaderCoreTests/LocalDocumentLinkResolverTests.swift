import Foundation
import Testing
@testable import ReaderCore

@Test func parsesOnlySafeRelativeMarkdownLinks() {
    #expect(
        LocalDocumentLinkResolver.parse("docs/./guide%20one.md#hello%20world")
            == LocalDocumentLink(path: "docs/guide one.md", fragment: "hello world")
    )
    #expect(LocalDocumentLinkResolver.parse("../secret.md") == nil)
    #expect(LocalDocumentLinkResolver.parse("/private/secret.md") == nil)
    #expect(LocalDocumentLinkResolver.parse("file:///private/secret.md") == nil)
    #expect(LocalDocumentLinkResolver.parse("notes.txt") == nil)
    #expect(LocalDocumentLinkResolver.parse("notes.md?download=true") == nil)
}

@Test func resolvesOnlyContainedRegularMarkdownFiles() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MarkdownReaderLinkTests-\(UUID().uuidString)", isDirectory: true)
    let docs = root.appendingPathComponent("docs", isDirectory: true)
    let document = root.appendingPathComponent("index.md")
    let guide = docs.appendingPathComponent("guide.md")
    try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("# Index".utf8).write(to: document)
    try Data("# Guide".utf8).write(to: guide)

    let link = try #require(LocalDocumentLinkResolver.parse("docs/guide.md#guide"))
    #expect(LocalDocumentLinkResolver.resolve(link, relativeTo: document) == guide)

    let outside = root.deletingLastPathComponent()
        .appendingPathComponent("outside-\(UUID().uuidString).md")
    try Data("secret".utf8).write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }
    let escaped = docs.appendingPathComponent("escaped.md")
    try FileManager.default.createSymbolicLink(at: escaped, withDestinationURL: outside)
    let escapedLink = try #require(LocalDocumentLinkResolver.parse("docs/escaped.md"))
    #expect(LocalDocumentLinkResolver.resolve(escapedLink, relativeTo: document) == nil)
}

@Test func rejectsDecodedControlCharactersInDocumentPaths() {
    for source in ["good.md%00ignored.md", "note%0A.md", "note%0D.md", "note%7F.md"] {
        #expect(LocalDocumentLinkResolver.parse(source) == nil)
    }
}
