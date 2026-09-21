import Foundation

/// A small bounded history for local file navigation; no document contents are retained.
public struct DocumentLocation: Equatable, Sendable {
    public let url: URL
    public let scrollY: Double
    public let fragment: String?

    public init(url: URL, scrollY: Double = 0, fragment: String? = nil) {
        self.url = url
        self.scrollY = scrollY.isFinite ? max(0, scrollY) : 0
        self.fragment = fragment
    }
}

public struct DocumentNavigationHistory: Sendable {
    private var previous: [DocumentLocation] = []
    private var next: [DocumentLocation] = []
    private let limit = 50
    public init() {}
    public var canGoBack: Bool { !previous.isEmpty }
    public var canGoForward: Bool { !next.isEmpty }

    public mutating func visit(leaving current: DocumentLocation) {
        previous.append(current)
        if previous.count > limit { previous.removeFirst() }
        next.removeAll()
    }

    public mutating func goBack(leaving current: DocumentLocation) -> DocumentLocation? {
        guard let destination = previous.popLast() else { return nil }
        next.append(current)
        return destination
    }

    public mutating func goForward(leaving current: DocumentLocation) -> DocumentLocation? {
        guard let destination = next.popLast() else { return nil }
        previous.append(current)
        return destination
    }
}
