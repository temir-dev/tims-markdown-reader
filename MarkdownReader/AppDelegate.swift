import AppKit
import UniformTypeIdentifiers

// The same app sources are compiled into the native integration-test harness.
#if !SWIFT_PACKAGE
@main
#endif
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let documentWindows = DocumentWindowManager()
    private var receivedOpenRequest = false
    private var licenseWindow: NSWindow?
    private var settingsWindow: ReadingSettingsWindowController?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.delegate = delegate
        application.setActivationPolicy(.regular)
        MainMenu.install(for: delegate)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)

        // Finder delivers open events during launch. Defer the empty-launch
        // check by one run-loop turn so its event wins over the Open panel.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !self.receivedOpenRequest,
                  self.documentWindows.isEmpty else { return }
            self.showOpenPanel()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedOpenRequest = true

        for url in urls where url.isFileURL {
            documentWindows.open(url)
        }

        application.activate(ignoringOtherApps: true)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag, documentWindows.isEmpty {
            showOpenPanel()
        }
        return true
    }

    @objc func openDocument(_ sender: Any?) {
        showOpenPanel()
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            settingsWindow = ReadingSettingsWindowController(preferences: .shared)
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(
            string: "Free and open source · MIT licensed\nProvided as is, without warranty.\nFull license and third-party notices: app menu → Licenses…",
            attributes: [.font: NSFont.systemFont(ofSize: 12)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Tim’s Markdown Reader",
            .credits: credits
        ])
    }

    /// The download page. The app never checks online itself; the browser opens this.
    static let releasesURL = URL(string: "https://github.com/temir-dev/tims-markdown-reader/releases/latest")!

    static func installedVersionDescription(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    @objc func checkForUpdates(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "You have version \(Self.installedVersionDescription())"
        alert.informativeText = "This app doesn't go online, so it can't check by itself. The download page shows the latest version. To update, download it and replace the app."
        alert.addButton(withTitle: "Open Download Page")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(Self.releasesURL)
    }

    @objc func showLicenses(_ sender: Any?) {
        if let licenseWindow {
            licenseWindow.makeKeyAndOrderFront(nil)
            return
        }
        let texts = [("LICENSE", nil as String?), ("ThirdPartyNotices", "txt")].compactMap { name, ext in
            Bundle.main.url(forResource: name, withExtension: ext)
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Licenses — Tim’s Markdown Reader"
        window.isReleasedWhenClosed = false
        let scroll = NSTextView.scrollableTextView()
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.font = .systemFont(ofSize: 13)
            text.textContainerInset = NSSize(width: 20, height: 20)
            text.string = texts.joined(separator: "\n\n────────────────────────\n\n")
        }
        window.contentView = scroll
        window.center()
        licenseWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }

        guard panel.runModal() == .OK else { return }

        for url in panel.urls where Self.supportedExtensions.contains(url.pathExtension.lowercased()) {
            documentWindows.open(url)
        }
    }

    private static let supportedExtensions = Set(["md", "markdown", "mdx"])
}
