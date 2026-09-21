import AppKit
import ReaderCore
import WebKit

@MainActor
final class MarkdownViewController: NSViewController, WKNavigationDelegate, NSSearchFieldDelegate {
    private let preferences: ReadingPreferences
    private var documentURL: URL
    private let webView: WKWebView
    private let schemeHandler: DocumentSchemeHandler
    private let findBar = NSVisualEffectView()
    private let findField = NSSearchField()
    private let recoveryView = NSStackView()
    private let loadingCover = ReaderBackgroundView()
    private var presentationNavigation: WKNavigation?
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    private var rendererUnavailable = false
    private let findStatus = NSTextField(labelWithString: "")
    private var findBarHeightConstraint: NSLayoutConstraint?
    private weak var restorationNavigation: WKNavigation?
    private var restorationScrollY: Double?
    private var findRequest = 0
    private var pendingFind: DispatchWorkItem?
    /// The query whose matches are currently highlighted in the page.
    private var searchedQuery: String?
    var onOpenDocumentLink: ((URL, String?) -> Void)?

    init(documentURL: URL, preferences: ReadingPreferences? = nil) {
        self.preferences = preferences ?? .shared
        self.documentURL = documentURL
        schemeHandler = DocumentSchemeHandler(sourceDocumentURL: documentURL)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // Only the two app-bundled Mermaid scripts are permitted by CSP.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(
            schemeHandler,
            forURLScheme: DocumentSchemeHandler.scheme
        )
        webView = ReaderWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        installUserScripts()
        NotificationCenter.default.addObserver(self, selector: #selector(readingPreferencesChanged), name: ReadingPreferences.didChange, object: self.preferences)
        webView.navigationDelegate = self
        findField.delegate = self
        findField.target = self
        findField.action = #selector(findNext(_:))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func installUserScripts() {
        let content = webView.configuration.userContentController
        content.removeAllUserScripts()
        content.addUserScript(WKUserScript(
            source: preferences.applicationScript, injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        // Find runs in the app's own script world, out of reach of document scripts.
        content.addUserScript(WKUserScript(
            source: ReaderAssets.findScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient
        ))
    }

    @objc private func readingPreferencesChanged() {
        // Update both the current page and every subsequent load without reloading it.
        installUserScripts()
        if !rendererUnavailable {
            webView.evaluateJavaScript(preferences.applicationScript, completionHandler: nil)
        }
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        configureFindBar()

        findBar.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(findBar)
        container.addSubview(webView)
        loadingCover.identifier = NSUserInterfaceItemIdentifier("reader-loading-cover")
        loadingCover.wantsLayer = true
        loadingCover.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(loadingCover)
        configureRecoveryView()
        container.addSubview(recoveryView)

        let findBarHeightConstraint = findBar.heightAnchor.constraint(equalToConstant: 0)
        self.findBarHeightConstraint = findBarHeightConstraint

        NSLayoutConstraint.activate([
            findBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            findBar.topAnchor.constraint(equalTo: container.topAnchor),
            findBarHeightConstraint,
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: findBar.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            loadingCover.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            loadingCover.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            loadingCover.topAnchor.constraint(equalTo: webView.topAnchor),
            loadingCover.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            recoveryView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            recoveryView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            recoveryView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            recoveryView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
        ])
        view = container
    }

    func prepareForDocument(at url: URL) {
        webView.stopLoading()
        setRendererUnavailable(false)
        documentURL = url
        schemeHandler.setSourceDocument(url)
        closeFind(nil)
        restorationNavigation = nil
        restorationScrollY = nil
    }

    func showLoading() {
        schemeHandler.update(document: MarkdownRenderer.loadingDocument())
        loadDocumentShell(restoringScrollY: nil)
    }

    func show(
        _ result: Result<RenderedDocument, Error>,
        title: String,
        restoringScrollY: Double? = nil,
        navigatingToFragment fragment: String? = nil
    ) {
        let document: RenderedDocument

        switch result {
        case let .success(rendered):
            document = rendered
        case let .failure(error):
            document = MarkdownRenderer.errorDocument(
                title: title,
                message: error.localizedDescription
            )
        }

        schemeHandler.update(document: document)
        loadDocumentShell(
            restoringScrollY: restoringScrollY,
            navigatingToFragment: fragment
        )
    }

    func navigateToFragment(_ fragment: String) {
        loadDocumentShell(restoringScrollY: nil, navigatingToFragment: fragment)
    }

    func captureScrollPosition(completion: @escaping (Double) -> Void) {
        guard !rendererUnavailable else { completion(0); return }
        webView.evaluateJavaScript("window.scrollY") { value, _ in
            let position = (value as? NSNumber)?.doubleValue ?? 0
            completion(position.isFinite ? max(position, 0) : 0)
        }
    }

    @objc func showFind(_ sender: Any?) {
        guard !rendererUnavailable else { return }
        findBar.isHidden = false
        findBarHeightConstraint?.constant = 42
        view.layoutSubtreeIfNeeded()
        view.window?.makeFirstResponder(findField)
        findField.selectText(nil)
    }

    @objc func findNext(_ sender: Any?) {
        if findBarHeightConstraint?.constant == 0 {
            showFind(sender)
        }
        stepFind(backwards: false)
    }

    @objc func findPrevious(_ sender: Any?) {
        if findBarHeightConstraint?.constant == 0 {
            showFind(sender)
        }
        stepFind(backwards: true)
    }

    @objc func closeFind(_ sender: Any?) {
        pendingFind?.cancel()
        pendingFind = nil
        findRequest += 1
        findField.stringValue = ""
        clearFindHighlights()
        findBarHeightConstraint?.constant = 0
        findBar.isHidden = true
        findStatus.stringValue = ""
        view.window?.makeFirstResponder(rendererUnavailable ? retryButton : webView)
    }

    func controlTextDidChange(_ notification: Notification) {
        pendingFind?.cancel()
        findRequest += 1
        let work = DispatchWorkItem { [weak self] in self?.updateSearch(revealingMatch: true) }
        pendingFind = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
    }

    override func cancelOperation(_ sender: Any?) {
        closeFind(sender)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if isAllowedDocumentNavigation(navigationAction, url: url) ||
            isAllowedMermaidSandboxNavigation(navigationAction, url: url) {
            decisionHandler(.allow)
            return
        }

        if navigationAction.targetFrame?.isMainFrame == true,
           navigationAction.navigationType == .linkActivated {
            if let localLink = schemeHandler.localDocumentLink(for: url),
               let targetURL = LocalDocumentLinkResolver.resolve(
                   localLink,
                   relativeTo: documentURL
               ) {
                onOpenDocumentLink?(targetURL, localLink.fragment)
            } else if isAllowedExternalURL(url) {
                NSWorkspace.shared.open(url)
            }
        }
        decisionHandler(.cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Use native controls: a failed rendering process cannot display HTML errors.
        // Watcher updates may refresh the stored document, but only Retry or opening
        // another document can restart rendering after a failure.
        setRendererUnavailable(true)
        webView.stopLoading()
        restorationNavigation = nil
        restorationScrollY = nil
        closeFind(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !rendererUnavailable else { return }
        if navigation === restorationNavigation,
           let scrollY = restorationScrollY {
            restorationNavigation = nil
            restorationScrollY = nil

            let safeScrollY = Int(min(max(scrollY, 0), 100_000_000).rounded())
            webView.evaluateJavaScript("window.scrollTo(0, \(safeScrollY))")
        }

        if findBarHeightConstraint?.constant != 0,
           !findField.stringValue.isEmpty {
            // A refreshed page has no highlights. Restore them without moving the reader.
            updateSearch(revealingMatch: false)
        }

        guard let navigation, navigation === presentationNavigation else { return }
        // didFinish means navigation finished, not that the new frame has been
        // presented. Keep an opaque native cover until WebKit incorporates its
        // screen updates. A one-point snapshot avoids copying the whole page.
        let snapshot = WKSnapshotConfiguration()
        snapshot.rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        snapshot.afterScreenUpdates = true
        webView.takeSnapshot(with: snapshot) { [weak self] image, error in
            guard let self, !self.rendererUnavailable,
                  navigation === self.presentationNavigation else { return }
            self.presentationNavigation = nil
            if image != nil, error == nil {
                self.loadingCover.isHidden = true
            } else {
                self.setRendererUnavailable(true)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failPresentation(navigation)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failPresentation(navigation)
    }

    private func failPresentation(_ navigation: WKNavigation?) {
        guard let navigation, navigation === presentationNavigation else { return }
        setRendererUnavailable(true)
    }

    private func configureRecoveryView() {
        recoveryView.orientation = .vertical
        recoveryView.alignment = .centerX
        recoveryView.spacing = 12
        recoveryView.translatesAutoresizingMaskIntoConstraints = false
        recoveryView.isHidden = !rendererUnavailable
        let title = NSTextField(wrappingLabelWithString: "Unable to display this document")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        title.alignment = .center
        let detail = NSTextField(wrappingLabelWithString: "The reader stopped unexpectedly. Your file has not been changed.")
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        retryButton.bezelStyle = .rounded
        retryButton.target = self
        retryButton.action = #selector(retryRendering(_:))
        recoveryView.addArrangedSubview(title)
        recoveryView.addArrangedSubview(detail)
        recoveryView.addArrangedSubview(retryButton)
        detail.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true
    }

    private func setRendererUnavailable(_ unavailable: Bool) {
        rendererUnavailable = unavailable
        presentationNavigation = nil
        loadingCover.isHidden = unavailable
        webView.isHidden = unavailable
        recoveryView.isHidden = !unavailable
    }

    @objc private func retryRendering(_ sender: Any?) {
        guard rendererUnavailable else { return }
        setRendererUnavailable(false)
        loadDocumentShell(restoringScrollY: nil)
        view.window?.makeFirstResponder(webView)
    }

    private func configureFindBar() {
        findBar.material = .headerView
        findBar.blendingMode = .withinWindow
        findBar.state = .active
        findBar.isHidden = true

        findField.placeholderString = "Find in document"
        findField.translatesAutoresizingMaskIntoConstraints = false

        findStatus.identifier = NSUserInterfaceItemIdentifier("reader-find-status")
        findStatus.setAccessibilityLabel("Find results")
        findStatus.textColor = .secondaryLabelColor
        findStatus.alignment = .right
        findStatus.translatesAutoresizingMaskIntoConstraints = false

        let previous = NSButton(title: "‹", target: self, action: #selector(findPrevious(_:)))
        previous.toolTip = "Previous Match"
        previous.translatesAutoresizingMaskIntoConstraints = false

        let next = NSButton(title: "›", target: self, action: #selector(findNext(_:)))
        next.toolTip = "Next Match"
        next.translatesAutoresizingMaskIntoConstraints = false

        let done = NSButton(title: "Done", target: self, action: #selector(closeFind(_:)))
        done.translatesAutoresizingMaskIntoConstraints = false

        findBar.addSubview(findField)
        findBar.addSubview(previous)
        findBar.addSubview(next)
        findBar.addSubview(findStatus)
        findBar.addSubview(done)

        let minimumFindFieldWidth = findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        minimumFindFieldWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            findField.leadingAnchor.constraint(equalTo: findBar.leadingAnchor, constant: 12),
            findField.centerYAnchor.constraint(equalTo: findBar.centerYAnchor),
            minimumFindFieldWidth,

            previous.leadingAnchor.constraint(equalTo: findField.trailingAnchor, constant: 8),
            previous.centerYAnchor.constraint(equalTo: findBar.centerYAnchor),
            previous.widthAnchor.constraint(equalToConstant: 30),

            next.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 4),
            next.centerYAnchor.constraint(equalTo: findBar.centerYAnchor),
            next.widthAnchor.constraint(equalToConstant: 30),

            findStatus.leadingAnchor.constraint(equalTo: next.trailingAnchor, constant: 8),
            findStatus.centerYAnchor.constraint(equalTo: findBar.centerYAnchor),

            done.leadingAnchor.constraint(greaterThanOrEqualTo: findStatus.trailingAnchor, constant: 8),
            done.trailingAnchor.constraint(equalTo: findBar.trailingAnchor, constant: -12),
            done.centerYAnchor.constraint(equalTo: findBar.centerYAnchor),
        ])
    }

    private func loadDocumentShell(
        restoringScrollY: Double?,
        navigatingToFragment fragment: String? = nil
    ) {
        guard !rendererUnavailable else { return }
        restorationNavigation = nil
        restorationScrollY = nil

        var components = URLComponents(
            url: schemeHandler.currentDocumentURL,
            resolvingAgainstBaseURL: false
        )
        components?.fragment = fragment
        let targetURL = components?.url ?? schemeHandler.currentDocumentURL
        var currentPage = webView.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        currentPage?.fragment = nil
        var targetPage = components
        targetPage?.fragment = nil
        // An anchor jump keeps the existing frame and has no didFinish callback.
        if fragment != nil, loadingCover.isHidden, currentPage?.url == targetPage?.url {
            webView.load(URLRequest(url: targetURL))
            return
        }
        presentationNavigation = nil
        loadingCover.isHidden = false
        let navigation = webView.load(URLRequest(url: targetURL))
        presentationNavigation = navigation
        if navigation == nil { setRendererUnavailable(true) }
        if let restoringScrollY, let navigation {
            restorationNavigation = navigation
            restorationScrollY = restoringScrollY
        }
    }

    /// Highlights every match for the field's text and selects the first one at or
    /// below the reader's position. Typing must not advance through matches.
    private func updateSearch(revealingMatch: Bool) {
        guard !rendererUnavailable else { return }
        pendingFind?.cancel()
        pendingFind = nil
        let query = findField.stringValue
        guard !query.isEmpty else {
            findRequest += 1
            findStatus.stringValue = ""
            clearFindHighlights()
            return
        }
        searchedQuery = query
        runFind(
            "return window.readerFind.search(query, reveal)",
            arguments: ["query": query, "reveal": revealingMatch],
            query: query,
            fallbackBackwards: false
        )
    }

    private func stepFind(backwards: Bool) {
        guard !rendererUnavailable else { return }
        let query = findField.stringValue
        guard !query.isEmpty, query == searchedQuery else {
            updateSearch(revealingMatch: true)
            return
        }
        pendingFind?.cancel()
        pendingFind = nil
        runFind(
            "return window.readerFind.step(delta)",
            arguments: ["delta": backwards ? -1 : 1],
            query: query,
            fallbackBackwards: backwards
        )
    }

    // Arguments are passed as values, never interpolated into the script text.
    private func runFind(
        _ body: String,
        arguments: [String: Any],
        query: String,
        fallbackBackwards: Bool
    ) {
        findRequest += 1
        let request = findRequest
        webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .defaultClient) { [weak self] result in
            guard let self, self.findRequest == request, self.findField.stringValue == query else { return }
            guard case let .success(value) = result,
                  let state = value as? [String: Any],
                  state["supported"] as? Bool == true,
                  let count = (state["count"] as? NSNumber)?.intValue,
                  let index = (state["index"] as? NSNumber)?.intValue else {
                // WebKit before the CSS Custom Highlight API: one match at a time.
                self.searchedQuery = nil
                self.nativeFind(query, backwards: fallbackBackwards, request: request)
                return
            }
            if count == 0 {
                self.findStatus.stringValue = "No matches"
            } else {
                let total = state["limited"] as? Bool == true ? "\(count)+" : "\(count)"
                self.findStatus.stringValue = "\(index + 1) of \(total)"
            }
        }
    }

    private func clearFindHighlights() {
        searchedQuery = nil
        guard !rendererUnavailable else { return }
        webView.callAsyncJavaScript("window.readerFind?.clear()", arguments: [:], in: nil, in: .defaultClient, completionHandler: nil)
        webView.find("", configuration: WKFindConfiguration(), completionHandler: { _ in })
    }

    private func nativeFind(_ query: String, backwards: Bool, request: Int) {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(query, configuration: configuration) { [weak self] result in
            guard let self, self.findRequest == request, self.findField.stringValue == query else { return }
            self.findStatus.stringValue = result.matchFound ? "" : "No matches"
        }
    }

    private func isAllowedDocumentNavigation(
        _ action: WKNavigationAction,
        url: URL
    ) -> Bool {
        guard action.targetFrame?.isMainFrame == true,
              url.scheme == DocumentSchemeHandler.scheme,
              url.host == "document",
              url.path == schemeHandler.currentDocumentURL.path,
              url.query == nil else {
            return false
        }

        if action.navigationType == .other {
            return true
        }
        return action.navigationType == .linkActivated && url.fragment != nil
    }

    private func isAllowedMermaidSandboxNavigation(
        _ action: WKNavigationAction,
        url: URL
    ) -> Bool {
        guard action.targetFrame?.isMainFrame == false,
              action.navigationType == .other,
              url.scheme == "about" else {
            return false
        }
        return url.absoluteString == "about:blank" || url.absoluteString == "about:srcdoc"
    }

    private func isAllowedExternalURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              components.user == nil,
              components.password == nil else {
            return false
        }

        switch scheme {
        case "http", "https":
            return components.host?.isEmpty == false
        case "mailto":
            return !components.path.isEmpty
        default:
            return false
        }
    }
}

/// Covers WebKit's transient blank frames without suspending its layout/paint.
private final class ReaderBackgroundView: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        readerBackground(for: effectiveAppearance).setFill()
        dirtyRect.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private func readerBackground(for appearance: NSAppearance) -> NSColor {
    let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return dark ? NSColor(srgbRed: 28.0 / 255, green: 28.0 / 255, blue: 30.0 / 255, alpha: 1) : .white
}

/// Match the native canvas to reader.css before the first HTML page is ready.
private final class ReaderWebView: WKWebView {
    override init(frame: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        updateBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        let color = readerBackground(for: effectiveAppearance)
        underPageBackgroundColor = color
        window?.backgroundColor = color
    }
}
