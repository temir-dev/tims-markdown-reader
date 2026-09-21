import AppKit
import Foundation
import ReaderCore
import Testing
import WebKit
@testable import ReaderApp

extension ReaderIntegrationTests {
    @Test func canvasMatchesAppearanceBeforeLoadingAndAcrossReloads() async throws {
        _ = NSApplication.shared
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-\(UUID().uuidString).md")
        let controller = MarkdownDocumentWindowController(documentURL: file)
        let window = try #require(controller.window)
        defer { window.close() }
        let reader = try #require(window.contentViewController as? MarkdownViewController)
        let web = try #require(descendant(WKWebView.self, in: reader.view))
        let cover = try #require(reader.view.subviews.first { $0.identifier?.rawValue == "reader-loading-cover" })
        window.setContentSize(NSSize(width: 900, height: 700))
        window.appearance = NSAppearance(named: .darkAqua)
        controller.showWindow(nil)

        func expectNativeBackground(dark: Bool) throws {
            for color in [web.underPageBackgroundColor, window.backgroundColor] {
                let rgb = try #require(color?.usingColorSpace(.sRGB))
                #expect(abs(rgb.redComponent - (dark ? 28.0 / 255.0 : 1)) < 0.01)
                #expect(abs(rgb.greenComponent - (dark ? 28.0 / 255.0 : 1)) < 0.01)
                #expect(abs(rgb.blueComponent - (dark ? 30.0 / 255.0 : 1)) < 0.01)
                #expect(rgb.alphaComponent == 1)
            }
        }

        func expectCanvas(dark: Bool) async throws {
            let snapshot = try await web.takeSnapshot(configuration: nil)
            let data = try #require(snapshot.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            let pixel = try #require(bitmap.colorAt(x: bitmap.pixelsWide - 20, y: bitmap.pixelsHigh - 20)?.usingColorSpace(.sRGB))
            #expect(pixel.alphaComponent > 0.99)
            if dark {
                #expect(max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.25)
            } else {
                #expect(min(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.9)
            }
        }

        // The original flash occurs before any HTML or stylesheet exists.
        #expect(web.url == nil)
        #expect(!cover.isHidden && cover.isOpaque)
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(cover.frame == web.frame)
        let initial = try #require(cover.bitmapImageRepForCachingDisplay(in: cover.bounds))
        cover.cacheDisplay(in: cover.bounds, to: initial)
        let initialPixel = try #require(initial.colorAt(x: 20, y: 20)?.usingColorSpace(.sRGB))
        #expect(initialPixel.alphaComponent > 0.99)
        #expect(max(initialPixel.redComponent, initialPixel.greenComponent, initialPixel.blueComponent) < 0.25)
        // WebKit cannot snapshot a page before its first navigation, so check
        // both native backing colors here, then actual pixels once it can draw.
        try expectNativeBackground(dark: true)
        reader.showLoading()
        #expect(!cover.isHidden)
        try expectNativeBackground(dark: true)
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('.status') !== null")) as? Bool == true }
        try await wait { cover.isHidden }
        try await expectCanvas(dark: true)

        for dark in [true, false, true] {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let background = dark ? "rgb(28, 28, 30)" : "rgb(255, 255, 255)"
            try await wait { (try? await web.evaluateJavaScript("getComputedStyle(document.body).backgroundColor")) as? String == background }
            try expectNativeBackground(dark: dark)
            try await expectCanvas(dark: dark)
            reader.show(.success(MarkdownRenderer.render("# Reloaded document")), title: "Canvas")
            #expect(!cover.isHidden)
            try await expectCanvas(dark: dark)
            try await wait { (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String == "Reloaded document" }
            try await wait { cover.isHidden }
            try await expectCanvas(dark: dark)
        }

        // A superseded load must never reveal its frame over a newer load.
        for number in 1...3 {
            reader.show(.success(MarkdownRenderer.render("# Rapid \(number)")), title: "Canvas")
            #expect(!cover.isHidden)
        }
        try await wait { cover.isHidden }
        #expect(try await web.evaluateJavaScript("document.querySelector('h1')?.textContent") as? String == "Rapid 3")
        reader.navigateToFragment("rapid-3")
        try await wait { cover.isHidden }
        #expect(try await web.evaluateJavaScript("location.hash") as? String == "#rapid-3")
    }

    @Test func diagramCanvasesFollowAppearanceAndPlaceholdersFollowProse() async throws {
        _ = NSApplication.shared
        let suite = "RenderingAppearanceTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReadingPreferences(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rendering-appearance.md")
        let source = """
        # Rendering appearance

        A paragraph on the normal reading column.

        ![Unsupported image](sample.svg)

        Inline ![Unsupported inline image](sample.svg) stays in its paragraph.

        ```mermaid
        flowchart LR
          A[Open note] --> B{Clear enough?}
          B -->|Yes| C[Close it]
          B -->|No| D[Read details]
        ```

        ```mermaid
        sequenceDiagram
          Person->>Reader: Open note
          Reader->>File: Read bytes
          File-->>Reader: Markdown
          Reader-->>Person: Display document
        ```

        ```mermaid
        pie title A sample reading session
          "Notes" : 50
          "Tables" : 30
          "Diagrams" : 20
        ```

        ```mermaid
        flowchart LR
          A[Deliberately unfinished
        ```
        """
        try Data(source.utf8).write(to: file)
        let manager = DocumentWindowManager(preferences: preferences)
        manager.open(file)
        let window = try #require(NSApp.windows.first { $0.title == file.lastPathComponent })
        defer { window.close() }
        window.setContentSize(NSSize(width: 1800, height: 950))
        let content = try #require(window.contentView)
        let web = try #require(descendant(WKWebView.self, in: content))
        try await wait { (try? await web.evaluateJavaScript("document.querySelectorAll('.image-placeholder').length")) as? Int == 2 }
        for width: ReadingPreferences.Width in [.centered, .full] {
            preferences.update(width: width)
            try await wait { (try? await web.evaluateJavaScript("document.documentElement.dataset.readerWidth")) as? String == width.rawValue }
            #expect(try await web.evaluateJavaScript("""
            (() => {
              const prose = document.querySelector('.reader > p');
              const placeholder = document.querySelector('.image-placeholder');
              return Math.abs(prose.getBoundingClientRect().left - placeholder.getBoundingClientRect().left) < 1;
            })()
            """) as? Bool == true)
        }
        preferences.update(width: .centered)
        window.setContentSize(NSSize(width: 1250, height: 950))
        // Switching both ways catches stale diagram palettes after an OS change.
        for (index, dark) in [false, true, false].enumerated() {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let scheme = dark ? "dark" : "light"
            let background = dark ? "rgb(41, 42, 45)" : "rgb(244, 245, 246)"
            try await wait {
                (try? await web.evaluateJavaScript("""
                (() => {
                  const frames = Array.from(document.querySelectorAll('.mermaid-diagram iframe'));
                  return frames.length === 3 && frames.every(frame => {
                    const doc = new DOMParser().parseFromString(frame.srcdoc, 'text/html');
                    return frame.getAttribute('sandbox') === '' && frame.contentDocument === null &&
                      doc.querySelector('svg') !== null && doc.querySelector('script') === null &&
                      doc.documentElement.style.colorScheme === '\(scheme)' &&
                      doc.documentElement.style.backgroundColor === '\(background)' &&
                      doc.body.style.backgroundColor === '\(background)';
                  }) && document.querySelectorAll('.mermaid-error[role="alert"]').length === 1;
                })()
                """)) as? Bool == true
            }
            // Optional local evidence, never written into the public source tree.
            if index < 2, let output = ProcessInfo.processInfo.environment["READER_RENDER_SNAPSHOTS"] {
                for diagram in 0..<3 {
                    _ = try await web.evaluateJavaScript("document.querySelectorAll('.mermaid-diagram')[\(diagram)].scrollIntoView({block: 'center'})")
                    // Frame navigation/painting finishes after srcdoc is assigned.
                    try await Task.sleep(for: .milliseconds(300))
                    let snapshot = try await web.takeSnapshot(configuration: nil)
                    let tiff = try #require(snapshot.tiffRepresentation)
                    let bitmap = try #require(NSBitmapImageRep(data: tiff))
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(scheme)-\(diagram).png"))
                }
            }
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == source)
    }
}
