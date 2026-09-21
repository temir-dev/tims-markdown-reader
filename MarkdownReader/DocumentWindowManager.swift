import AppKit

@MainActor
final class DocumentWindowManager {
    private let preferences: ReadingPreferences

    init(preferences: ReadingPreferences? = nil) {
        self.preferences = preferences ?? .shared
    }

    private var windows: [MarkdownDocumentWindowController] = []

    var isEmpty: Bool {
        windows.isEmpty
    }

    func open(_ requestedURL: URL, fragment: String? = nil) {
        let url = requestedURL.standardizedFileURL.resolvingSymlinksInPath()

        if let existing = windows.first(where: { $0.documentURL == url }) {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            if let fragment {
                existing.navigateToFragment(fragment)
            }
            return
        }

        let controller = MarkdownDocumentWindowController(
            documentURL: url,
            initialFragment: fragment,
            preferences: preferences
        )
        controller.onOpenDocumentLink = { [weak controller] targetURL, fragment in
            controller?.navigate(to: targetURL, fragment: fragment)
        }
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.windows.removeAll { $0 === controller }
        }
        windows.append(controller)

        // The native window is visible before any file I/O begins.
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.loadDocument()
    }
}
