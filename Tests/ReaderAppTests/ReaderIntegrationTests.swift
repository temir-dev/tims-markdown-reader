import AppKit
import Foundation
import Testing
import WebKit
@testable import ReaderApp

@Suite(.serialized) @MainActor
struct ReaderIntegrationTests {
    @Test func followsFootnoteLinksWithoutCollidingWithHeadings() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("footnote-navigation.md")
        let source = "# fn-1\r\n\r\nA reference.[^one]\r\n\r\n" + String(repeating: "A paragraph.\r\n\r\n", count: 60) + "[^one]: The footnote body."
        try Data(source.utf8).write(to: file)
        let manager = DocumentWindowManager()
        manager.open(file)
        let window = try #require(NSApp.windows.first { $0.title == file.lastPathComponent })
        defer { window.close() }
        let content = try #require(window.contentView)
        let web = try #require(descendant(WKWebView.self, in: content))
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('.footnotes') !== null")) as? Bool == true }
        _ = try await web.evaluateJavaScript("document.querySelector('.footnote-ref a').click()")
        try await wait { (try? await web.evaluateJavaScript("document.querySelector(':target')?.id")) as? String == "footnote:1" }
        #expect(try await web.evaluateJavaScript("document.querySelector(':target').textContent.includes('The footnote body.')") as? Bool == true)
        _ = try await web.evaluateJavaScript("document.querySelector('.footnote-backref').click()")
        try await wait { (try? await web.evaluateJavaScript("document.querySelector(':target')?.id")) as? String == "footnote-ref:1:1" }
        #expect(try String(contentsOf: file, encoding: .utf8) == source)
    }

    @Test func rendersZeroWidthChartAndRejectsDocumentSanitizerOverrides() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("release-security.md")
        try Data("""
        # Release security regression

        ```mermaid
        xychart
          x-axis 1 --> 1
          line [1, 2]
        ```

        ```mermaid
        ---
        config:
          securityLevel: loose
          dompurifyConfig:
            ADD_ATTR: [onerror]
            RETURN_DOM: true
        ---
        flowchart LR
          A[Start] --> B[Finish]
        ```
        """.utf8).write(to: file)
        let manager = DocumentWindowManager()
        manager.open(file)
        let window = try #require(NSApp.windows.first { $0.title == "release-security.md" })
        defer { window.close() }
        let reader = try #require(window.contentViewController as? MarkdownViewController)
        let web = try #require(descendant(WKWebView.self, in: reader.view))
        try await wait {
            (try? await web.evaluateJavaScript("document.querySelectorAll('.mermaid-diagram iframe[sandbox]').length")) as? Int == 2
        }
        #expect(try await web.evaluateJavaScript("globalThis.mermaid.mermaidAPI.getConfig().securityLevel") as? String == "sandbox")
        #expect(try await web.evaluateJavaScript("typeof globalThis.mermaid.mermaidAPI.getConfig().dompurifyConfig") as? String == "undefined")
        #expect(try await web.evaluateJavaScript("Array.from(document.querySelectorAll('.mermaid-diagram iframe')).every(f => f.getAttribute('sandbox') === '' && f.srcdoc.includes('<svg'))") as? Bool == true)
    }

    @Test func readsFindsNavigatesAndRendersOfflineContentInOneWindow() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let nested = directory.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.md")
        let second = nested.appendingPathComponent("second.md")
        // Four matches for "coast": mixed case, inside a longer word, and split across emphasis.
        let source = "# First document\n\nRead this coast. The Coast is clear along the **coast**line.\n\n"
            + String(repeating: "Filler paragraph.\n\n", count: 80)
            + "A co*ast* split across emphasis.\n\n[Next](docs/second.md#destination)"
        try Data(source.utf8).write(to: first)
        try Data("""
        # Destination

        ![Local](chart.png)

        <script>globalThis.injected = true</script>

        [Run script](javascript:alert(1))

        ```mermaid
        flowchart LR
          A[Start] --> B[Finish]
        ```
        """.utf8).write(to: second)
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2ZV0AAAAASUVORK5CYII="))
        try png.write(to: nested.appendingPathComponent("chart.png"))

        let manager = DocumentWindowManager()
        manager.open(first)
        let window = try #require(NSApp.windows.first { $0.title == "first.md" })
        defer { window.close() }
        window.appearance = NSAppearance(named: .aqua)
        let controller = try #require(window.windowController as? MarkdownDocumentWindowController)
        let reader = try #require(window.contentViewController as? MarkdownViewController)
        let web = try #require(descendant(WKWebView.self, in: reader.view))
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String == "First document" }
        let windowCount = NSApp.windows.filter { $0.windowController is MarkdownDocumentWindowController }.count
        manager.open(first)
        #expect(NSApp.windows.filter { $0.windowController is MarkdownDocumentWindowController }.count == windowCount)
        reader.showFind(nil)
        let field = try #require(descendant(NSSearchField.self, in: reader.view))
        let status = try #require(descendant(identifiedBy: "reader-find-status", in: reader.view) as? NSTextField)
        field.stringValue = "coast"
        reader.findNext(nil)
        // Every match is highlighted at once; the first stays selected without scrolling away.
        try await wait { status.stringValue == "1 of 4" }
        #expect(try await web.evaluateJavaScript("CSS.highlights.get('reader-find')?.size") as? Int == 4)
        #expect(try await web.evaluateJavaScript("CSS.highlights.get('reader-find-current')?.size") as? Int == 1)
        #expect(try await web.evaluateJavaScript("window.scrollY") as? Int == 0)
        #expect(try await web.evaluateJavaScript("typeof window.readerFind") as? String == "undefined")
        reader.findNext(nil)
        try await wait { status.stringValue == "2 of 4" }
        reader.findPrevious(nil)
        try await wait { status.stringValue == "1 of 4" }
        reader.findPrevious(nil)
        try await wait { status.stringValue == "4 of 4" }
        // Wrapping to the last match, far down the page, brings it into view.
        #expect(((try await web.evaluateJavaScript("window.scrollY")) as? Int ?? 0) > 0)
        #expect(try await web.evaluateJavaScript("document.querySelector('mark') === null") as? Bool == true)
        field.stringValue = "no such text"
        reader.findNext(nil)
        try await wait { status.stringValue == "No matches" }
        let found = try await web.find("coast", configuration: WKFindConfiguration())
        #expect(found.matchFound)
        reader.closeFind(nil)
        #expect(field.stringValue.isEmpty)
        try await wait { (try? await web.evaluateJavaScript("CSS.highlights.has('reader-find')")) as? Bool == false }

        // Back and Forward are visible toolbar buttons, disabled until there is somewhere to go.
        let toolbarItems = try #require(window.toolbar?.items)
        let backButton = try #require(toolbarItems.first { $0.itemIdentifier.rawValue == "reader-back" })
        let forwardButton = try #require(toolbarItems.first { $0.itemIdentifier.rawValue == "reader-forward" })
        #expect(backButton.image != nil && forwardButton.image != nil)
        #expect(!controller.validateToolbarItem(backButton) && !controller.validateToolbarItem(forwardButton))

        _ = try await web.evaluateJavaScript("document.querySelector('a[href*=\"/link/\"]').click()")
        do {
            try await wait {
                let title = (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String
                return controller.documentURL == second && title == "Destination"
            }
        } catch {
            print("Navigation actual: \(controller.documentURL.absoluteString), expected: \(second.absoluteString)")
            print("Web URL: \(String(describing: web.url))")
            print("Body: \(String(describing: try? await web.evaluateJavaScript("document.body.innerHTML")))")
            throw error
        }
        #expect(NSApp.windows.filter { $0.windowController is MarkdownDocumentWindowController }.count == windowCount)
        #expect(descendant(WKWebView.self, in: reader.view) === web)
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('img')?.naturalWidth")) as? Int == 1 }
        #expect(try await web.evaluateJavaScript("typeof globalThis.injected") as? String == "undefined")
        #expect(try await web.evaluateJavaScript("document.querySelector('.link-pending')?.getAttribute('title')") as? String == "Blocked unsafe or unsupported link")
        #expect(try await web.evaluateJavaScript("document.querySelector('.link-pending')?.hasAttribute('href')") as? Bool == false)
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('.mermaid-diagram iframe')?.getAttribute('sandbox')")) as? String == "" }
        #expect(try await web.evaluateJavaScript("document.querySelector('.mermaid-diagram iframe').srcdoc.includes('<svg')") as? Bool == true)

        let lightDiagram = try await web.evaluateJavaScript("document.querySelector('.mermaid-diagram iframe').srcdoc") as? String
        window.appearance = NSAppearance(named: .darkAqua)
        try await wait {
            (try? await web.evaluateJavaScript("getComputedStyle(document.body).backgroundColor")) as? String == "rgb(28, 28, 30)"
        }
        try await wait {
            let darkDiagram = (try? await web.evaluateJavaScript("document.querySelector('.mermaid-diagram iframe')?.srcdoc")) as? String
            return darkDiagram != nil && darkDiagram != lightDiagram
        }
        window.appearance = NSAppearance(named: .aqua)
        try await wait {
            (try? await web.evaluateJavaScript("getComputedStyle(document.body).backgroundColor")) as? String == "rgb(255, 255, 255)"
        }

        // Following a link enables Back only; the buttons use their real target/action wiring.
        #expect(controller.validateToolbarItem(backButton) && !controller.validateToolbarItem(forwardButton))
        #expect(NSApp.sendAction(try #require(backButton.action), to: backButton.target, from: backButton))
        try await wait {
            let title = (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String
            return controller.documentURL == first && title == "First document"
        }
        #expect(!controller.validateToolbarItem(backButton) && controller.validateToolbarItem(forwardButton))
        #expect(NSApp.sendAction(try #require(forwardButton.action), to: forwardButton.target, from: forwardButton))
        try await wait {
            let title = (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String
            return controller.documentURL == second && title == "Destination"
        }
        #expect(controller.validateToolbarItem(backButton) && !controller.validateToolbarItem(forwardButton))
        #expect(try String(contentsOf: first, encoding: .utf8) == source)
        // Verify the real reader refreshes, not just the watcher callback.
        let handle = try FileHandle(forWritingTo: second)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("# Updated destination".utf8))
        try handle.close()
        try await wait {
            (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String == "Updated destination"
        }
        // The previous document's watcher must no longer control this window.
        try Data("# Changed previous file".utf8).write(to: first, options: .atomic)
        try await Task.sleep(for: .milliseconds(400))
        #expect(controller.documentURL == second)
        #expect(try await web.evaluateJavaScript("document.querySelector('h1')?.textContent") as? String == "Updated destination")
    }

}
