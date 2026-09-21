import AppKit
import Foundation
import Testing
import WebKit
@testable import ReaderApp

// These extensions share one serialized suite because they use NSApplication.
extension ReaderIntegrationTests {
    @Test func readingSettingsUpdateEveryWindowAndPersistWithoutReloading() async throws {
        _ = NSApplication.shared
        let suite = "ReadingSettingsTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReadingPreferences(defaults: defaults)
        #expect(preferences.font == .system && preferences.textSize == 17 && preferences.width == .centered)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = "# Reading settings\n\nA paragraph with `code` to read.\n\n```mermaid\nflowchart LR\n A[Open] --> B[Read]\n```\n\n" + String(repeating: "More text for scrolling.\n\n", count: 100)
        let manager = DocumentWindowManager(preferences: preferences)
        var windows: [NSWindow] = []
        var webs: [WKWebView] = []
        defer { windows.forEach { $0.close() } }
        for index in 0..<2 {
            let file = directory.appendingPathComponent("settings-\(index).md")
            try Data(source.utf8).write(to: file)
            manager.open(file)
            let window = try #require(NSApp.windows.first { $0.title == file.lastPathComponent })
            windows.append(window)
            window.setContentSize(NSSize(width: 1800, height: 800))
            let windowContent = try #require(window.contentView)
            let web = try #require(descendant(WKWebView.self, in: windowContent))
            webs.append(web)
            try await wait { (try? await web.evaluateJavaScript("document.querySelector('.mermaid-diagram iframe')?.srcdoc.includes('<svg')")) as? Bool == true }
            _ = try await web.evaluateJavaScript("window.settingsTestMarker = 42; window.scrollTo(0, 400)")
        }
        let originalWidth = try #require(try await webs[0].evaluateJavaScript("document.querySelector('.reader > p').getBoundingClientRect().width") as? Double)
        let settings = ReadingSettingsWindowController(preferences: preferences)
        defer { settings.close() }
        settings.showWindow(nil)
        let content = try #require(settings.window?.contentView)
        content.layoutSubtreeIfNeeded()
        let font = try #require(descendant(NSPopUpButton.self, in: content))
        font.selectItem(withTitle: "Serif")
        let fontAction = try #require(font.action)
        #expect(font.sendAction(fontAction, to: font.target))
        let slider = try #require(descendant(NSSlider.self, in: content))
        slider.doubleValue = 21
        let sliderAction = try #require(slider.action)
        #expect(slider.sendAction(sliderAction, to: slider.target))
        let width = try #require(descendant(NSSegmentedControl.self, in: content))
        width.selectedSegment = 1
        let widthAction = try #require(width.action)
        #expect(width.sendAction(widthAction, to: width.target))
        for web in webs {
            try await wait { (try? await web.evaluateJavaScript("getComputedStyle(document.documentElement).fontSize")) as? String == "21px" }
            #expect(try await web.evaluateJavaScript("getComputedStyle(document.querySelector('p')).fontFamily.includes('Georgia')") as? Bool == true)
            #expect(try await web.evaluateJavaScript("document.documentElement.dataset.readerWidth") as? String == "full")
            #expect(try await web.evaluateJavaScript("window.settingsTestMarker") as? Int == 42)
            #expect(try await web.evaluateJavaScript("window.scrollY") as? Double ?? 0 > 0)
            try await wait { (try? await web.evaluateJavaScript("document.querySelector('.mermaid-diagram iframe')?.srcdoc.includes('21px')")) as? Bool == true }
            #expect(try await web.evaluateJavaScript("document.querySelector('.mermaid-diagram iframe').getAttribute('sandbox')") as? String == "")
        }
        let wideWidth = try #require(try await webs[0].evaluateJavaScript("document.querySelector('.reader > p').getBoundingClientRect().width") as? Double)
        #expect(wideWidth > originalWidth + 100)
        let restored = ReadingPreferences(defaults: defaults)
        #expect(restored.font == .serif && restored.textSize == 21 && restored.width == .full)
        // A fresh reader and an external file save must both retain the appearance.
        let file = directory.appendingPathComponent("settings-new.md")
        try Data("# New reader".utf8).write(to: file)
        manager.open(file)
        let fresh = try #require(NSApp.windows.first { $0.title == file.lastPathComponent })
        windows.append(fresh)
        let freshContent = try #require(fresh.contentView)
        let freshWeb = try #require(descendant(WKWebView.self, in: freshContent))
        try await wait { (try? await freshWeb.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String == "New reader" }
        #expect(try await freshWeb.evaluateJavaScript("getComputedStyle(document.documentElement).fontSize") as? String == "21px")
        try Data("# Refreshed reader".utf8).write(to: file, options: .atomic)
        try await wait { (try? await freshWeb.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String == "Refreshed reader" }
        #expect(try await freshWeb.evaluateJavaScript("getComputedStyle(document.documentElement).fontSize") as? String == "21px")
        func button(named title: String, in view: NSView) -> NSButton? {
            if let match = view as? NSButton, match.title == title { return match }
            return view.subviews.lazy.compactMap { button(named: title, in: $0) }.first
        }
        let smaller = try #require(button(named: "−", in: content))
        let larger = try #require(button(named: "+", in: content))
        let smallerAction = try #require(smaller.action)
        #expect(smaller.sendAction(smallerAction, to: smaller.target))
        #expect(preferences.textSize == 20)
        let largerAction = try #require(larger.action)
        #expect(larger.sendAction(largerAction, to: larger.target))
        #expect(preferences.textSize == 21)
        preferences.update(textSize: 28)
        #expect(!larger.isEnabled && smaller.isEnabled)
        preferences.update(textSize: 12)
        #expect(!smaller.isEnabled && larger.isEnabled)
        let reset = try #require(button(named: "Restore Defaults", in: content))
        let resetAction = try #require(reset.action)
        #expect(reset.sendAction(resetAction, to: reset.target))
        // Each visible control must stay inside the small fixed settings window.
        for control: NSView in [font, slider, width, smaller, larger, reset] {
            #expect(content.bounds.contains(control.convert(control.bounds, to: content)))
        }
        #expect(font.titleOfSelectedItem == "System" && slider.doubleValue == 17 && width.selectedSegment == 0)
        try await wait { (try? await freshWeb.evaluateJavaScript("getComputedStyle(document.documentElement).fontSize")) as? String == "17px" }
        #expect(try String(contentsOf: directory.appendingPathComponent("settings-0.md"), encoding: .utf8) == source)
    }

    @Test func readingPreferencesValidateStoredValuesAndSizeLimits() throws {
        let suite = "ReadingSettingsTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["font": "invalid", "width": "invalid", "textSize": 900], forKey: "readingAppearance")
        let preferences = ReadingPreferences(defaults: defaults)
        #expect(preferences.font == .system && preferences.width == .centered && preferences.textSize == 28)
        preferences.update(textSize: -100)
        #expect(preferences.textSize == 12)
        preferences.update(textSize: .nan)
        #expect(preferences.textSize == 17)
        preferences.update(font: .monospaced, textSize: 19.6)
        #expect(preferences.textSize == 20 && preferences.font == .monospaced)
        preferences.restoreDefaults()
        #expect(ReadingPreferences(defaults: defaults).textSize == 17)
    }
}
