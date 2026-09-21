import AppKit
import Foundation
import Testing
import WebKit
@testable import ReaderApp

extension ReaderIntegrationTests {
    func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }

    func descendant(identifiedBy identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier { return view }
        return view.subviews.lazy.compactMap { descendant(identifiedBy: identifier, in: $0) }.first
    }

    func wait(line: Int = #line, _ condition: () async -> Bool) async throws {
        for _ in 0..<300 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw VerificationError.timedOut(line)
    }
}

private enum VerificationError: Error { case timedOut(Int) }
