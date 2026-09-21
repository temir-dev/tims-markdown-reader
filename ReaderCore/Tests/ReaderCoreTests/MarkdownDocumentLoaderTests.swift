import Darwin
import Foundation
import Testing
@testable import ReaderCore

@Test func loadsEmptyAndUTF8Documents() throws {
    let fixture = try DocumentLoaderFixture()
    let emptyURL = fixture.url.appendingPathComponent("empty.md")
    let unicodeURL = fixture.url.appendingPathComponent("unicode.md")
    try Data().write(to: emptyURL)
    try Data("# Hello, 🌍\n\nCafé ☕️".utf8).write(to: unicodeURL)

    #expect(try MarkdownDocumentLoader.load(from: emptyURL) == "")
    #expect(try MarkdownDocumentLoader.load(from: unicodeURL).contains("🌍"))
}

@Test func rejectsInvalidUTF8AndOversizeDocuments() throws {
    let fixture = try DocumentLoaderFixture()
    let invalidURL = fixture.url.appendingPathComponent("invalid.md")
    let largeURL = fixture.url.appendingPathComponent("large.md")
    try Data([0xFF, 0xFE, 0xFA]).write(to: invalidURL)
    try Data(repeating: 0x41, count: 17).write(to: largeURL)

    #expect(throws: MarkdownDocumentLoadError.invalidUTF8) {
        try MarkdownDocumentLoader.load(from: invalidURL)
    }
    #expect(throws: MarkdownDocumentLoadError.tooLarge) {
        try MarkdownDocumentLoader.load(from: largeURL, maximumBytes: 16)
    }
}

@Test func rejectsDirectoriesAndInvalidLimits() throws {
    let fixture = try DocumentLoaderFixture()
    #expect(throws: MarkdownDocumentLoadError.notRegularFile) {
        try MarkdownDocumentLoader.load(from: fixture.url)
    }
    #expect(throws: MarkdownDocumentLoadError.invalidLimit) {
        try MarkdownDocumentLoader.load(from: fixture.url, maximumBytes: -1)
    }
}

private final class DocumentLoaderFixture {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownDocumentLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

@Test func cancelsDocumentReadsWithoutStartingIO() throws {
    #expect(throws: MarkdownDocumentLoadError.cancelled) {
        try MarkdownDocumentLoader.load(from: URL(fileURLWithPath: "/does-not-exist.md"), shouldCancel: { true })
    }
}

@Test func acceptsExactByteLimitAndRejectsFinalSymlinks() throws {
    let fixture = try DocumentLoaderFixture()
    let file = fixture.url.appendingPathComponent("exact.md")
    try Data("abcd".utf8).write(to: file)
    #expect(try MarkdownDocumentLoader.load(from: file, maximumBytes: 4) == "abcd")
    let symlink = fixture.url.appendingPathComponent("link.md")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
    #expect(throws: MarkdownDocumentLoadError.unreadable) { try MarkdownDocumentLoader.load(from: symlink) }
}

@Test func rejectsNamedPipesWithoutBlockingDocumentQueue() throws {
    let fixture = try DocumentLoaderFixture()
    let pipe = fixture.url.appendingPathComponent("pipe.md")
    #expect(mkfifo(pipe.path, 0o600) == 0)
    #expect(throws: MarkdownDocumentLoadError.notRegularFile) {
        try MarkdownDocumentLoader.load(from: pipe)
    }
}
