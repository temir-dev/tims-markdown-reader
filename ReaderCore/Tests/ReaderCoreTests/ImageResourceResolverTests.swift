import Darwin
import Foundation
import Testing
@testable import ReaderCore

@Test func loadsAContainedRasterFile() throws {
    let fixture = try ImageFixture()
    let bytes = try validPNGData()
    let imageURL = fixture.directory.appendingPathComponent("image.png")
    try bytes.write(to: imageURL)

    let image = try ImageResourceResolver.load(
        source: "image.png",
        relativeTo: fixture.document
    )

    #expect(image.data == bytes)
    #expect(image.mimeType == "image/png")
}

@Test func normalizesSafeRelativeImagePaths() {
    #expect(ImageResourceResolver.normalizedSource("images/./icons//photo%2Epng") == "images/icons/photo.png")
    #expect(ImageResourceResolver.normalizedSource("images/%2E%2E/photo.png") == nil)
}

@Test func rejectsTraversalAndSymlinkEscapes() throws {
    let fixture = try ImageFixture()
    let outsideDirectory = fixture.directory.deletingLastPathComponent()
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: outsideDirectory) }

    let outsideImage = outsideDirectory.appendingPathComponent("outside.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: outsideImage)
    let symlink = fixture.directory.appendingPathComponent("escaped.png")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outsideImage)

    #expect(throws: ImageResourceError.invalidSource) {
        try ImageResourceResolver.load(source: "../outside.png", relativeTo: fixture.document)
    }
    #expect(throws: ImageResourceError.outsideDocumentDirectory) {
        try ImageResourceResolver.load(source: "escaped.png", relativeTo: fixture.document)
    }
}

@Test func rejectsInvalidUnsupportedAndOversizeImages() throws {
    let fixture = try ImageFixture()
    let imageURL = fixture.directory.appendingPathComponent("large.png")
    try Data(repeating: 0, count: 17).write(to: imageURL)

    #expect(throws: ImageResourceError.invalidSource) {
        try ImageResourceResolver.load(source: "/tmp/image.png", relativeTo: fixture.document)
    }
    #expect(throws: ImageResourceError.invalidSource) {
        try ImageResourceResolver.load(source: "data:image/png;base64,AAAA", relativeTo: fixture.document)
    }
    #expect(throws: ImageResourceError.unsupportedType) {
        try ImageResourceResolver.load(source: "image.svg", relativeTo: fixture.document)
    }
    #expect(throws: ImageResourceError.tooLarge) {
        try ImageResourceResolver.load(
            source: "large.png",
            relativeTo: fixture.document,
            maximumBytes: 16
        )
    }
    #expect(throws: ImageResourceError.invalidImage) {
        try ImageResourceResolver.load(source: "large.png", relativeTo: fixture.document)
    }
}

@Test func supportsCooperativeImageReadCancellation() throws {
    let fixture = try ImageFixture()
    try validPNGData().write(to: fixture.directory.appendingPathComponent("image.png"))

    #expect(throws: ImageResourceError.cancelled) {
        try ImageResourceResolver.load(
            source: "image.png",
            relativeTo: fixture.document,
            shouldCancel: { true }
        )
    }
}

private func validPNGData() throws -> Data {
    try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2ZV0AAAAASUVORK5CYII="))
}

private final class ImageFixture {
    let directory: URL
    let document: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownReaderTests-\(UUID().uuidString)", isDirectory: true)
        document = directory.appendingPathComponent("document.md")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("# Test".utf8).write(to: document)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

@Test func rejectsDecodedControlCharactersInImagePaths() {
    for source in ["real.png%00ignored.png", "image%0A.png", "image%0D.png", "image%7F.png"] {
        #expect(ImageResourceResolver.normalizedSource(source) == nil)
    }
}

@Test func preservesLiteralPercentEscapesThroughRenderingAndImageLoading() throws {
    let fixture = try ImageFixture()
    let bytes = try validPNGData()
    try bytes.write(to: fixture.directory.appendingPathComponent("literal%20.png"))
    let document = MarkdownRenderer.render("![literal](literal%2520.png)")
    let source = try #require(document.images["image-0"])
    let image = try ImageResourceResolver.load(source: source, relativeTo: fixture.document)
    #expect(image.data == bytes)
}

@Test func rejectsNamedPipesWithoutBlockingImageQueue() throws {
    let fixture = try ImageFixture()
    let pipe = fixture.directory.appendingPathComponent("pipe.png")
    #expect(mkfifo(pipe.path, 0o600) == 0)
    #expect(throws: ImageResourceError.notRegularFile) {
        try ImageResourceResolver.load(source: "pipe.png", relativeTo: fixture.document)
    }
}
