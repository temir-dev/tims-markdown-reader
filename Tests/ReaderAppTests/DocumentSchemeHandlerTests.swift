import Foundation
import ReaderCore
import Testing
import WebKit
@testable import ReaderApp

extension ReaderIntegrationTests {
    @Test func rejectsStaleAndUnexpectedResourceRequests() throws {
        let handler = DocumentSchemeHandler(sourceDocumentURL: URL(fileURLWithPath: "/unused/document.md"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        let first = MarkdownRenderer.render("# First\n\n[Next](next.md)")
        handler.update(document: first)
        let oldPage = handler.currentDocumentURL
        let oldLink = try #require(URL(string: "markdown-reader://document/link/\(first.resourceToken)/link-0"))
        #expect(handler.localDocumentLink(for: oldLink)?.path == "next.md")
        let current = MarkdownRenderer.render("# Current")
        handler.update(document: current)
        #expect(handler.localDocumentLink(for: oldLink) == nil)
        for url in [oldPage,
                    URL(string: "markdown-reader://other/assets/reader.css")!,
                    URL(string: "markdown-reader://document/assets/reader.css?unexpected=1")!,
                    URL(string: "markdown-reader://document/assets/missing.js")!] {
            let task = SchemeTask(url: url)
            handler.webView(web, start: task)
            #expect(task.events == ["failure"])
            #expect(task.data.isEmpty)
        }
        let task = SchemeTask(url: handler.currentDocumentURL)
        handler.webView(web, start: task)
        #expect(task.events == ["response", "data", "finish"])
        #expect(String(data: task.data, encoding: .utf8) == current.html)
    }

    @Test func cancelledAndReplacedImageRequestsNeverDeliverLateCallbacks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2ZV0AAAAASUVORK5CYII="))
        try bytes.write(to: directory.appendingPathComponent("image.png"))
        let handler = DocumentSchemeHandler(sourceDocumentURL: directory.appendingPathComponent("document.md"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        func imageTask(_ document: RenderedDocument) -> SchemeTask {
            SchemeTask(url: URL(string: "markdown-reader://document/image/\(document.resourceToken)/image-0")!)
        }
        let first = MarkdownRenderer.render("![test](image.png)")
        handler.update(document: first)
        let cancelled = imageTask(first)
        handler.webView(web, start: cancelled)
        handler.webView(web, stop: cancelled)
        let replaced = imageTask(first)
        handler.webView(web, start: replaced)
        let second = MarkdownRenderer.render("![test](image.png)")
        handler.update(document: second)
        let current = imageTask(second)
        handler.webView(web, start: current)
        // The serial image queue completes the earlier jobs before this one.
        try await wait { current.events.last == "finish" }
        #expect(cancelled.events.isEmpty)
        #expect(replaced.events.isEmpty)
        #expect(current.data == bytes)
    }
}

@MainActor
// The handler delivers every callback on the main actor; retain runtime checks
// when conforming to WebKit's older nonisolated Objective-C protocol.
private final class SchemeTask: NSObject, @preconcurrency WKURLSchemeTask {
    let request: URLRequest
    private(set) var events: [String] = []
    private(set) var data = Data()

    init(url: URL) { request = URLRequest(url: url) }
    func didReceive(_ response: URLResponse) { events.append("response") }
    func didReceive(_ data: Data) { events.append("data"); self.data.append(data) }
    func didFinish() { events.append("finish") }
    func didFailWithError(_ error: Error) { events.append("failure") }
}
