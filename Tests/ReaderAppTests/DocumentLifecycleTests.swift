import AppKit
import Foundation
import Testing
import WebKit
@testable import ReaderApp

// These extensions share one serialized suite because they use NSApplication.
extension ReaderIntegrationTests {
    @Test func recoversFromInvalidDeletedAndRapidlyReplacedFiles() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("recovery café 🌍.md")
        try Data([0xFF, 0xFE]).write(to: file)
        let manager = DocumentWindowManager()
        manager.open(file)
        let window = try #require(NSApp.windows.first { $0.title == file.lastPathComponent })
        defer { window.close() }
        let reader = try #require(window.contentViewController as? MarkdownViewController)
        let web = try #require(descendant(WKWebView.self, in: reader.view))
        try await wait {
            (try? await web.evaluateJavaScript("document.querySelector('.error-state')?.textContent.includes('UTF-8')")) as? Bool == true
        }
        try Data("# Recovered".utf8).write(to: file, options: .atomic)
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String == "Recovered" }
        try FileManager.default.removeItem(at: file)
        try await wait {
            (try? await web.evaluateJavaScript("document.querySelector('.error-state')?.textContent.includes('could not be read')")) as? Bool == true
        }
        // Exercise save bursts while the watcher reattaches after deletion.
        for index in 0..<25 {
            try Data("# Revision \(index)".utf8).write(to: file, options: .atomic)
            try await Task.sleep(for: .milliseconds(15))
        }
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String == "Revision 24" }
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Revision 24")
        #expect(descendant(WKWebView.self, in: reader.view) === web)
    }

    @Test func keepsSameNamedDocumentsInSeparateWindows() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = DocumentWindowManager()
        var opened: [NSWindow] = []
        defer { opened.forEach { $0.close() } }
        var urls: [URL] = []
        for index in 0..<3 {
            let folder = directory.appendingPathComponent("folder \(index)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("AGENTS.md")
            urls.append(file)
            try Data("# Document \(index)".utf8).write(to: file)
            manager.open(file)
            let window = try #require(NSApp.windows.first {
                ($0.windowController as? MarkdownDocumentWindowController)?.documentURL == file
            })
            opened.append(window)
        }
        #expect(Set(opened.map(ObjectIdentifier.init)).count == 3)
        for (index, window) in opened.enumerated() {
            let reader = try #require(window.contentViewController as? MarkdownViewController)
            let web = try #require(descendant(WKWebView.self, in: reader.view))
            try await wait {
                (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String == "Document \(index)"
            }
        }
        manager.open(urls[0])
        #expect(NSApp.windows.filter {
            ($0.windowController as? MarkdownDocumentWindowController)?.documentURL == urls[0]
        }.count == 1)
        opened.forEach { $0.close() }
        #expect(manager.isEmpty)
        opened.removeAll()
    }

    @Test func releasesControllersWhenClosedDuringLoadingAndCanReopen() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("close-during-load.md")
        try Data(("# Loading stress\n\n" + String(repeating: "A paragraph with **Markdown**.\n\n", count: 4_000)).utf8).write(to: file)
        let manager = DocumentWindowManager()
        for _ in 0..<12 {
            weak var releasedController: MarkdownDocumentWindowController?
            try autoreleasepool {
                manager.open(file)
                let window = try #require(NSApp.windows.first { $0.title == file.lastPathComponent })
                releasedController = window.windowController as? MarkdownDocumentWindowController
                window.close()
                #expect(manager.isEmpty)
            }
            try await wait { releasedController == nil }
        }
        // A fresh open must still work after cancellation/release cycles.
        try Data("# Reopened successfully".utf8).write(to: file, options: .atomic)
        manager.open(file)
        let window = try #require(NSApp.windows.first { $0.title == file.lastPathComponent })
        defer { window.close() }
        let reader = try #require(window.contentViewController as? MarkdownViewController)
        let web = try #require(descendant(WKWebView.self, in: reader.view))
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String == "Reopened successfully" }
    }
}
