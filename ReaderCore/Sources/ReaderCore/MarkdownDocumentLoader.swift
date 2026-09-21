import Darwin
import Foundation

public enum MarkdownDocumentLoadError: LocalizedError, Equatable, Sendable {
    case invalidLimit
    case notRegularFile
    case tooLarge
    case invalidUTF8
    case unreadable
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidLimit:
            return "The configured document size limit is invalid."
        case .notRegularFile:
            return "This item is not a regular file."
        case .tooLarge:
            return "This document is larger than the 20 MiB reading limit."
        case .invalidUTF8:
            return "This file is not valid UTF-8."
        case .unreadable:
            return "This document could not be read."
        case .cancelled:
            return "Document loading was cancelled."
        }
    }
}

public enum MarkdownDocumentLoader {
    public static let maximumDocumentBytes = 20 * 1_024 * 1_024

    public static func load(
        from url: URL,
        maximumBytes: Int = maximumDocumentBytes,
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> String {
        guard maximumBytes >= 0, maximumBytes < Int.max else {
            throw MarkdownDocumentLoadError.invalidLimit
        }

        guard !shouldCancel() else { throw MarkdownDocumentLoadError.cancelled }
        guard url.isFileURL, !url.path.utf8.contains(0) else { throw MarkdownDocumentLoadError.unreadable }
        // Inspect the opened descriptor, not a path that may change between stat/open.
        // Nonblocking open prevents a substituted FIFO from hanging the load queue.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw MarkdownDocumentLoadError.unreadable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw MarkdownDocumentLoadError.unreadable }
        guard (information.st_mode & S_IFMT) == S_IFREG else { throw MarkdownDocumentLoadError.notRegularFile }
        guard information.st_size >= 0, information.st_size <= maximumBytes else {
            throw MarkdownDocumentLoadError.tooLarge
        }

        var data = Data()
        let boundedReadCount = maximumBytes + 1
        do {
            while data.count < boundedReadCount {
                guard !shouldCancel() else { throw MarkdownDocumentLoadError.cancelled }
                let remaining = boundedReadCount - data.count
                let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)) ?? Data()
                guard !chunk.isEmpty else { break }
                data.append(chunk)
            }
        } catch let error as MarkdownDocumentLoadError {
            throw error
        } catch {
            throw MarkdownDocumentLoadError.unreadable
        }
        guard !shouldCancel() else { throw MarkdownDocumentLoadError.cancelled }
        guard data.count <= maximumBytes else {
            throw MarkdownDocumentLoadError.tooLarge
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw MarkdownDocumentLoadError.invalidUTF8
        }
        return text
    }
}
