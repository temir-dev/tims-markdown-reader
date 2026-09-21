import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ReaderCore

@Test func rejectsOversizedImageHeadersWithoutDecodingPixels() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var data = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2ZV0AAAAASUVORK5CYII="))
    // Only alter the PNG header. No large bitmap is allocated or decoded.
    data.replaceSubrange(16..<24, with: [0, 0, 0x27, 0x10, 0, 0, 0x27, 0x10]) // 10,000 × 10,000
    var crc: UInt32 = 0xffff_ffff
    for byte in data[12..<29] {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb8_8320) }
    }
    crc ^= 0xffff_ffff
    data.replaceSubrange(29..<33, with: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: crc >> $0) })
    try data.write(to: directory.appendingPathComponent("oversized.png"))
    do {
        _ = try ImageResourceResolver.load(source: "oversized.png", relativeTo: directory.appendingPathComponent("document.md"))
        Issue.record("An oversized image header must not be accepted")
    } catch let error as ImageResourceError {
        // ImageIO may reject inconsistent compressed data before our pixel check.
        #expect(error == .tooManyPixels || error == .invalidImage)
    }
}

@Test func rejectsTooManyAnimationFrames() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pixels = Data([0, 0, 0, 255])
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let image = try #require(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.gif.identifier as CFString, 101, nil))
    for _ in 0..<101 { CGImageDestinationAddImage(destination, image, nil) }
    #expect(CGImageDestinationFinalize(destination))
    try (output as Data).write(to: directory.appendingPathComponent("animation.gif"))
    #expect(throws: ImageResourceError.tooManyFrames) {
        try ImageResourceResolver.load(source: "animation.gif", relativeTo: directory.appendingPathComponent("document.md"))
    }
}

@Test func limitsTotalAnimationPixelsWithoutDecodingFrames() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    // Reuse one modest bitmap to encode valid GIFs. Never decode the animation.
    let provider = try #require(CGDataProvider(data: Data(repeating: 0, count: 1_000 * 1_000 * 4) as CFData))
    let image = try #require(CGImage(width: 1_000, height: 1_000, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: 4_000, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    for frameCount in [50, 51] {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.gif.identifier as CFString, frameCount, nil))
        for _ in 0..<frameCount { CGImageDestinationAddImage(destination, image, nil) }
        try #require(CGImageDestinationFinalize(destination))
        let data = output as Data
        let imageSource = try #require(CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary))
        #expect(CGImageSourceGetCount(imageSource) == frameCount)
        try data.write(to: directory.appendingPathComponent("animation.gif"))
        if frameCount == 50 {
            // Exactly 50 million total pixels remains within the limit.
            let accepted = try ImageResourceResolver.load(source: "animation.gif", relativeTo: directory.appendingPathComponent("document.md"))
            #expect(accepted.data == data)
        } else {
            #expect(throws: ImageResourceError.tooManyPixels) {
                try ImageResourceResolver.load(source: "animation.gif", relativeTo: directory.appendingPathComponent("document.md"))
            }
        }
    }
}
