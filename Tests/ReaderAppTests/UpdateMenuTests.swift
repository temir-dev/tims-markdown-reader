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

        // The test harness has no app Info.plist, so the fallback must stay readable.
        #expect(AppDelegate.installedVersionDescription(bundle: Bundle(for: AppDelegate.self)).contains("("))
    }
}
