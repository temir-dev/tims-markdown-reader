import AppKit
import Foundation
import ReaderCore
import Testing
import WebKit
@testable import ReaderApp

extension ReaderIntegrationTests {
    @Test func rendererFailureWaitsForManualRetryAndKeepsSourceUnchanged() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("recovery.md")
        let source = Data("# Original document".utf8)
        try source.write(to: file)
        let manager = DocumentWindowManager()
        manager.open(file)
        let window = try #require(NSApp.windows.first { $0.title == file.lastPathComponent })
        defer { window.close() }
        let reader = try #require(window.contentViewController as? MarkdownViewController)
        let web = try #require(descendant(WKWebView.self, in: reader.view))
        let cover = try #require(reader.view.subviews.first { $0.identifier?.rawValue == "reader-loading-cover" })
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String == "Original document" }
        reader.showFind(nil)
        // Deliver WebKit's failure callback without killing any system processes.
        reader.webViewWebContentProcessDidTerminate(web)
        let recovery = try #require(reader.view.subviews.compactMap { $0 as? NSStackView }.first)
        let retry = try #require(descendant(NSButton.self, in: recovery))
        #expect(web.isHidden && !recovery.isHidden && cover.isHidden)
        #expect(window.firstResponder === retry)
        #expect(retry.title == "Retry")
        reader.showFind(nil)
        #expect(descendant(NSSearchField.self, in: reader.view)?.isHiddenOrHasHiddenAncestor == true)

        // A file-watcher update must not create an automatic crash/reload loop.
        reader.show(.success(MarkdownRenderer.render("# Updated document")), title: "recovery.md")
        #expect(web.isHidden && !recovery.isHidden)
        #expect(try await web.evaluateJavaScript("document.querySelector('h1')?.textContent") as? String == "Original document")
        let action = try #require(retry.action)
        #expect(retry.sendAction(action, to: retry.target))
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String == "Updated document" }
        try await wait { cover.isHidden }
        #expect(!web.isHidden && recovery.isHidden)
        #expect(try Data(contentsOf: file) == source)

        // A second failure is recoverable, and opening another document resets it.
        reader.webViewWebContentProcessDidTerminate(web)
        #expect(web.isHidden && !recovery.isHidden)
        reader.prepareForDocument(at: directory.appendingPathComponent("another.md"))
        reader.show(.success(MarkdownRenderer.render("# Another document")), title: "another.md")
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String == "Another document" }
        try await wait { cover.isHidden }
        #expect(!web.isHidden && recovery.isHidden)
        #expect(try Data(contentsOf: file) == source)
    }
}
