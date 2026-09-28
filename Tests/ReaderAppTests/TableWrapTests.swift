import AppKit
import Foundation
import Testing
import WebKit
@testable import ReaderApp

extension ReaderIntegrationTests {
    @Test func wideTablesWrapByDefaultAndScrollWhenChosen() async throws {
        _ = NSApplication.shared
        let suite = "TableWrapTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReadingPreferences(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("wide-table.md")
        let longCell = String(repeating: "a long sentence in one cell ", count: 12)
        let unbroken = String(repeating: "x", count: 180)
        let source = "# Wide table\n\n| Name | Notes | Link |\n| --- | --- | --- |\n| First | \(longCell) | \(unbroken) |\n"
        try Data(source.utf8).write(to: file)

        let manager = DocumentWindowManager(preferences: preferences)
        manager.open(file)
        let window = try #require(NSApp.windows.first { $0.title == "wide-table.md" })
        defer { window.close() }
        window.setContentSize(NSSize(width: 900, height: 700))
        let content = try #require(window.contentView)
        let web = try #require(descendant(WKWebView.self, in: content))
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('table') !== null")) as? Bool == true }

        let overflow = "(() => { const s = document.querySelector('.table-scroll'); return s.scrollWidth - s.clientWidth; })()"
        // Default: the table fits its box, so there is nothing to scroll sideways.
        try await wait { ((try? await web.evaluateJavaScript(overflow)) as? Double ?? 99) <= 1 }
        #expect(try await web.evaluateJavaScript("document.documentElement.dataset.readerTables") as? String == "wrap")

        // Scroll keeps the natural width, which for this table is much wider than the page.
        preferences.update(tables: .scroll)
        try await wait { ((try? await web.evaluateJavaScript(overflow)) as? Double ?? 0) > 200 }

        preferences.update(tables: .wrap)
        try await wait { ((try? await web.evaluateJavaScript(overflow)) as? Double ?? 99) <= 1 }
        #expect(try String(contentsOf: file, encoding: .utf8) == source)
    }
}
