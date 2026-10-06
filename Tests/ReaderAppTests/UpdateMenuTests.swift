import AppKit
import Foundation
import Testing
@testable import ReaderApp

extension ReaderIntegrationTests {
    @Test func checkForUpdatesIsWiredAndOnlyPointsAtTheReleasePage() throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let previousMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMenu }
        MainMenu.install(for: delegate)

        let applicationMenu = try #require(NSApp.mainMenu?.items.first?.submenu)
        let item = try #require(applicationMenu.items.first { $0.title == "Check for Updates…" })
        #expect(item.action == #selector(AppDelegate.checkForUpdates(_:)))
        #expect(item.target === delegate)
        // Directly under About, where Mac users look for it.
        #expect(applicationMenu.items.firstIndex(of: item) == 1)

        // Back and Forward have their own Go menu with the usual Mac shortcuts.
        let goMenu = try #require(NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Go" })
        #expect(goMenu.items.map(\.title) == ["Back", "Forward"])
        #expect(goMenu.items.map(\.keyEquivalent) == ["[", "]"])

        let url = AppDelegate.releasesURL
        #expect(url.scheme == "https")
        #expect(url.host == "github.com")
        #expect(url.path.hasSuffix("/releases/latest"))
        #expect(url.query == nil && url.user == nil)

        // People see the version only. The build number stays in Info.plist for telling builds apart.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("version-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let info = ["CFBundleIdentifier": "test.version", "CFBundleShortVersionString": "3.4", "CFBundleVersion": "77"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent("Contents/Info.plist"))
        let bundle = try #require(Bundle(url: directory))
        #expect(AppDelegate.installedVersionDescription(bundle: bundle) == "3.4")

        func labels(_ view: NSView) -> [String] {
            ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap(labels)
        }
        NSApp.orderFrontStandardAboutPanel(options: AppDelegate.aboutPanelOptions(bundle: bundle))
        let about = try #require(NSApp.windows.first { $0.contentView.map(labels)?.contains("Tim’s Markdown Reader") == true })
        defer { about.close() }
        let shown = about.contentView.map(labels) ?? []
        #expect(shown.contains("Version 3.4"))
        #expect(!shown.contains { $0.contains("77") })
    }
}
