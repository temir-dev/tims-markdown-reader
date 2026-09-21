import AppKit
import ReaderCore

@MainActor
final class MarkdownDocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation,
    NSToolbarDelegate, NSToolbarItemValidation {
    private static let frameAutosaveName: NSWindow.FrameAutosaveName =
        "MarkdownReaderDocumentWindow"
    private static let backItem = NSToolbarItem.Identifier("reader-back")
    private static let forwardItem = NSToolbarItem.Identifier("reader-forward")
    private(set) var documentURL: URL
    private let readerViewController: MarkdownViewController
    private let loadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.tairov.timsmarkdownreader.document-loader"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var fileWatcher: DocumentFileWatcher?
    private var loadOperation: BlockOperation?
    private var loadGeneration = 0
    private var initialFragment: String?
    private var history = DocumentNavigationHistory()
    private var navigationGeneration = 0
    var onClose: (() -> Void)?
    var onOpenDocumentLink: ((URL, String?) -> Void)? {
        didSet {
            readerViewController.onOpenDocumentLink = onOpenDocumentLink
        }
    }

    init(documentURL: URL, initialFragment: String? = nil, preferences: ReadingPreferences? = nil) {
        self.documentURL = documentURL
        self.initialFragment = initialFragment
        readerViewController = MarkdownViewController(documentURL: documentURL, preferences: preferences)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = documentURL.lastPathComponent
        window.contentViewController = readerViewController
        window.minSize = NSSize(width: 480, height: 320)

        super.init(window: window)
        window.delegate = self
        let toolbar = NSToolbar(identifier: "MarkdownReaderDocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func loadDocument() {
        if fileWatcher == nil {
            fileWatcher = DocumentFileWatcher(documentURL: documentURL) { [weak self] in
                self?.reloadAfterFileChange()
            }
        }
        let fragment = initialFragment
        initialFragment = nil
        loadDocument(
            showLoading: true,
            restoringScrollY: nil,
            navigatingToFragment: fragment
        )
    }

    private func reloadAfterFileChange() {
        let generation = navigationGeneration
        readerViewController.captureScrollPosition { [weak self] scrollY in
            guard let self, self.navigationGeneration == generation else { return }
            self.loadDocument(
                showLoading: false,
                restoringScrollY: scrollY,
                navigatingToFragment: nil
            )
        }
    }

    private func loadDocument(
        showLoading: Bool,
        restoringScrollY: Double?,
        navigatingToFragment fragment: String?
    ) {
        loadGeneration += 1
        let generation = loadGeneration
        let url = documentURL

        if showLoading {
            readerViewController.showLoading()
        }

        loadOperation?.cancel()
        loadQueue.cancelAllOperations()

        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let result: Result<RenderedDocument, Error>

            do {
                let text = try MarkdownDocumentLoader.load(from: url, shouldCancel: { operation.isCancelled })
                guard !operation.isCancelled else { return }
                result = .success(MarkdownRenderer.render(text, title: url.lastPathComponent))
            } catch {
                result = .failure(error)
            }

            guard !operation.isCancelled else { return }
            DispatchQueue.main.async { [weak self, weak operation] in
                guard let self,
                      operation?.isCancelled == false,
                      self.loadGeneration == generation else { return }
                self.loadOperation = nil
                self.readerViewController.show(
                    result,
                    title: url.lastPathComponent,
                    restoringScrollY: restoringScrollY,
                    navigatingToFragment: fragment
                )
            }
        }
        loadOperation = operation
        loadQueue.addOperation(operation)
    }

    func navigate(to url: URL, fragment: String? = nil) {
        if url == documentURL {
            if let fragment { navigateToFragment(fragment) }
            return
        }
        changeLocation { [weak self] current in
            self?.history.visit(leaving: current)
            return DocumentLocation(url: url, fragment: fragment)
        }
    }

    @objc func goBack(_ sender: Any?) {
        changeLocation { [weak self] current in self?.history.goBack(leaving: current) }
    }

    @objc func goForward(_ sender: Any?) {
        changeLocation { [weak self] current in self?.history.goForward(leaving: current) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(goBack(_:)): return history.canGoBack
        case #selector(goForward(_:)): return history.canGoForward
        default: return true
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.backItem: return history.canGoBack
        case Self.forwardItem: return history.canGoForward
        default: return true
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.backItem, Self.forwardItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let back = itemIdentifier == Self.backItem
        guard back || itemIdentifier == Self.forwardItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = back ? "Back" : "Forward"
        item.toolTip = back ? "Back to the previous document (⌘[)" : "Forward to the next document (⌘])"
        item.image = NSImage(
            systemSymbolName: back ? "chevron.backward" : "chevron.forward",
            accessibilityDescription: item.label
        )
        item.isBordered = true
        item.isNavigational = true
        item.target = self
        item.action = back ? #selector(goBack(_:)) : #selector(goForward(_:))
        return item
    }

    private func changeLocation(_ destination: @escaping (DocumentLocation) -> DocumentLocation?) {
        navigationGeneration += 1
        let generation = navigationGeneration
        readerViewController.captureScrollPosition { [weak self] scrollY in
            guard let self, self.navigationGeneration == generation,
                  let target = destination(DocumentLocation(url: self.documentURL, scrollY: scrollY)) else { return }
            self.fileWatcher?.cancel()
            self.fileWatcher = nil
            self.documentURL = target.url
            self.window?.title = target.url.lastPathComponent
            self.readerViewController.prepareForDocument(at: target.url)
            self.fileWatcher = DocumentFileWatcher(documentURL: target.url) { [weak self] in
                self?.reloadAfterFileChange()
            }
            self.loadDocument(showLoading: true,
                              restoringScrollY: target.fragment == nil ? target.scrollY : nil,
                              navigatingToFragment: target.fragment)
            // History changed: update Back/Forward now rather than at the next event.
            self.window?.toolbar?.validateVisibleItems()
        }
    }

    func navigateToFragment(_ fragment: String) {
        readerViewController.navigateToFragment(fragment)
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame()
        navigationGeneration += 1
        loadGeneration += 1
        loadOperation?.cancel()
        loadOperation = nil
        loadQueue.cancelAllOperations()
        fileWatcher?.cancel()
        fileWatcher = nil
        onClose?()
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        saveWindowFrame()
    }

    private func saveWindowFrame() {
        guard let window,
              !window.styleMask.contains(.fullScreen) else {
            return
        }
        window.saveFrame(usingName: Self.frameAutosaveName)
    }
}
