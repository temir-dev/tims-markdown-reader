import Darwin
import Foundation
import ImageIO

public struct ResolvedImage: Sendable {
    public let data: Data
    public let mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

public enum ImageResourceError: Error, Equatable, Sendable {
    case invalidSource
    case outsideDocumentDirectory
    case unsupportedType
    case notRegularFile
    case tooLarge
    case tooManyPixels
    case tooManyFrames
    case invalidImage
    case cancelled
    case unreadable
}

public enum ImageResourceResolver {
    public static let maximumImageBytes = 25 * 1_024 * 1_024
    public static let maximumPixelCount = 50_000_000
    public static let maximumFrameCount = 100
    // Sum every frame, not only each frame individually. Compressed size alone
    // does not bound the memory needed to display an animation.
    public static let maximumTotalPixelCount = 50_000_000

    public static func accepts(source: String) -> Bool {
        guard let path = normalizedSource(source) else { return false }
        return mimeType(forExtension: NSString(string: path).pathExtension) != nil
    }

    public static func normalizedSource(_ source: String) -> String? {
        guard !source.isEmpty,
              !source.contains("\0"),
              !source.hasPrefix("/"),
              !source.hasPrefix("~"),
              !NSString(string: source).isAbsolutePath,
              let urlComponents = URLComponents(string: source),
              urlComponents.scheme == nil,
              urlComponents.host == nil,
              urlComponents.query == nil,
              urlComponents.fragment == nil,
              let decodedPath = urlComponents.percentEncodedPath.removingPercentEncoding,
              !decodedPath.isEmpty,
              !decodedPath.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
              !decodedPath.hasPrefix("/"),
              !NSString(string: decodedPath).isAbsolutePath else {
            return nil
        }

        let components = decodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." }
        guard !components.isEmpty,
              components.allSatisfy({ $0 != ".." }) else {
            return nil
        }
        return components.joined(separator: "/")
    }

    public static func load(
        source: String,
        relativeTo documentURL: URL,
        maximumBytes: Int = maximumImageBytes,
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> ResolvedImage {
        guard maximumBytes >= 0,
              maximumBytes < Int.max,
              let relativePath = normalizedSource(source) else {
            throw ImageResourceError.invalidSource
        }
        guard let mimeType = mimeType(forExtension: NSString(string: relativePath).pathExtension) else {
            throw ImageResourceError.unsupportedType
        }
        guard !shouldCancel() else { throw ImageResourceError.cancelled }

        let directoryPath = documentURL.deletingLastPathComponent().path
        let directoryDescriptor = Darwin.open(directoryPath, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directoryDescriptor >= 0 else { throw ImageResourceError.unreadable }
        defer { Darwin.close(directoryDescriptor) }

        let components = relativePath.split(separator: "/").map(String.init)
        var parentDescriptor = directoryDescriptor
        var ownedParentDescriptor: Int32?
        defer {
            if let ownedParentDescriptor {
                Darwin.close(ownedParentDescriptor)
            }
        }

        for component in components.dropLast() {
            guard !shouldCancel() else { throw ImageResourceError.cancelled }
            let nextDescriptor = Darwin.openat(
                parentDescriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard nextDescriptor >= 0 else {
                throw pathOpenError()
            }
            if let ownedParentDescriptor {
                Darwin.close(ownedParentDescriptor)
            }
            ownedParentDescriptor = nextDescriptor
            parentDescriptor = nextDescriptor
        }

        guard let fileName = components.last else { throw ImageResourceError.invalidSource }
        let fileDescriptor = Darwin.openat(
            parentDescriptor,
            fileName,
            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
        )
        guard fileDescriptor >= 0 else { throw pathOpenError() }
        defer { Darwin.close(fileDescriptor) }

        var information = stat()
        guard Darwin.fstat(fileDescriptor, &information) == 0 else {
            throw ImageResourceError.unreadable
        }
        guard (information.st_mode & S_IFMT) == S_IFREG else {
            throw ImageResourceError.notRegularFile
        }
        guard information.st_size >= 0,
              information.st_size <= off_t(maximumBytes) else {
            throw ImageResourceError.tooLarge
        }

        var data = Data()
        data.reserveCapacity(Int(information.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)

        while true {
            guard !shouldCancel() else { throw ImageResourceError.cancelled }
            let amount = Darwin.read(fileDescriptor, &buffer, buffer.count)
            if amount == 0 { break }
            if amount < 0 {
                if errno == EINTR { continue }
                throw ImageResourceError.unreadable
            }
            guard amount <= maximumBytes - data.count else {
                throw ImageResourceError.tooLarge
            }
            data.append(contentsOf: buffer.prefix(amount))
        }

        try validateImage(data)
        guard !shouldCancel() else { throw ImageResourceError.cancelled }
        return ResolvedImage(data: data, mimeType: mimeType)
    }

    private static func validateImage(_ data: Data) throws {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options) else {
            throw ImageResourceError.invalidImage
        }

        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 0 else { throw ImageResourceError.invalidImage }
        guard frameCount <= maximumFrameCount else { throw ImageResourceError.tooManyFrames }

        var totalPixels = 0
        for index in 0..<frameCount {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, options)
                as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  width > 0,
                  height > 0 else {
                throw ImageResourceError.invalidImage
            }
            let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
            guard !overflow, pixelCount <= maximumPixelCount,
                  pixelCount <= maximumTotalPixelCount - totalPixels else {
                throw ImageResourceError.tooManyPixels
            }
            totalPixels += pixelCount
        }
    }

    private static func pathOpenError() -> ImageResourceError {
        switch errno {
        case ELOOP, ENOTDIR:
            .outsideDocumentDirectory
        default:
            .unreadable
        }
    }

    private static func mimeType(forExtension pathExtension: String) -> String? {
        switch pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "heic", "heif": "image/heic"
        case "tif", "tiff": "image/tiff"
        case "bmp": "image/bmp"
        case "ico": "image/x-icon"
        case "avif": "image/avif"
        default: nil
        }
    }
}
