import Foundation
import ReaderCore
@preconcurrency import WebKit

private final class ImageLoadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }
}

@MainActor
final class DocumentSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "markdown-reader"
    // A fresh path prevents WebKit treating a new file + fragment as an
    // in-page anchor on the previous document, or reusing its cached HTML.
    var currentDocumentURL: URL {
        URL(string: "markdown-reader://document/page/\(document.resourceToken)/index.html")!
    }

    private var sourceDocumentURL: URL
    private let imageQueue = DispatchQueue(
        label: "dev.tairov.timsmarkdownreader.image-loader",
        qos: .userInitiated
    )
    private struct PendingImageTask {
        let generation: UInt64
        let cancellation: ImageLoadCancellation
        let schemeTask: any WKURLSchemeTask
    }

    private static let maximumDocumentImageBytes = 200 * 1_024 * 1_024
    private var document = MarkdownRenderer.loadingDocument()
    private var generation: UInt64 = 0
    private var pendingImageTasks: [ObjectIdentifier: PendingImageTask] = [:]
    private var servedImageIdentifiers: Set<String> = []
    private var servedImageBytes = 0

    init(sourceDocumentURL: URL) {
        self.sourceDocumentURL = sourceDocumentURL
        super.init()
    }

    func setSourceDocument(_ url: URL) {
        sourceDocumentURL = url
        update(document: MarkdownRenderer.loadingDocument())
    }

    func update(document: RenderedDocument) {
        generation &+= 1
        for pendingTask in pendingImageTasks.values {
            pendingTask.cancellation.cancel()
        }
        pendingImageTasks.removeAll()
        servedImageIdentifiers.removeAll()
        servedImageBytes = 0
        self.document = document
    }

    func localDocumentLink(for url: URL) -> LocalDocumentLink? {
        guard url.scheme == Self.scheme,
              url.host == "document",
              url.query == nil else {
            return nil
        }
        let pathComponents = url.path.split(separator: "/").map(String.init)
        guard pathComponents.count == 3,
              pathComponents[0] == "link",
              pathComponents[1] == document.resourceToken else {
            return nil
        }
        return document.localLinks[pathComponents[2]]
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == Self.scheme,
              url.host == "document",
              url.query == nil else {
            fail(urlSchemeTask, code: .badURL)
            return
        }

        switch url.path {
        case currentDocumentURL.path:
            respond(
                to: urlSchemeTask,
                url: url,
                mimeType: "text/html",
                textEncodingName: "utf-8",
                data: Data(document.html.utf8)
            )
        case "/assets/reader.css":
            respond(
                to: urlSchemeTask,
                url: url,
                mimeType: "text/css",
                textEncodingName: "utf-8",
                data: Data(ReaderAssets.stylesheet.utf8)
            )
        case "/assets/mermaid.min.js":
            respond(
                to: urlSchemeTask,
                url: url,
                mimeType: "text/javascript",
                textEncodingName: "utf-8",
                data: ReaderAssets.mermaidRuntime
            )
        case "/assets/mermaid-bootstrap.js":
            respond(
                to: urlSchemeTask,
                url: url,
                mimeType: "text/javascript",
                textEncodingName: "utf-8",
                data: ReaderAssets.mermaidBootstrap
            )
        default:
            let pathComponents = url.path.split(separator: "/").map(String.init)
            guard pathComponents.count == 3,
                  pathComponents[0] == "image",
                  pathComponents[1] == document.resourceToken else {
                fail(urlSchemeTask, code: .fileDoesNotExist)
                return
            }

            let identifier = pathComponents[2]
            guard !identifier.isEmpty,
                  !identifier.contains("/"),
                  let source = document.images[identifier] else {
                fail(urlSchemeTask, code: .fileDoesNotExist)
                return
            }
            loadImage(
                identifier: identifier,
                source: source,
                requestURL: url,
                urlSchemeTask: urlSchemeTask
            )
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let identifier = ObjectIdentifier(urlSchemeTask)
        pendingImageTasks.removeValue(forKey: identifier)?.cancellation.cancel()
    }

    private func loadImage(
        identifier: String,
        source: String,
        requestURL: URL,
        urlSchemeTask: any WKURLSchemeTask
    ) {
        let taskIdentifier = ObjectIdentifier(urlSchemeTask)
        let sourceDocumentURL = sourceDocumentURL
        let taskGeneration = generation
        let cancellation = ImageLoadCancellation()
        pendingImageTasks[taskIdentifier] = PendingImageTask(
            generation: taskGeneration,
            cancellation: cancellation,
            schemeTask: urlSchemeTask
        )

        imageQueue.async { [weak self] in
            let result = Result {
                try ImageResourceResolver.load(
                    source: source,
                    relativeTo: sourceDocumentURL,
                    shouldCancel: { cancellation.isCancelled() }
                )
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let pendingTask = self.pendingImageTasks.removeValue(forKey: taskIdentifier),
                      pendingTask.generation == taskGeneration,
                      self.generation == taskGeneration,
                      !cancellation.isCancelled() else {
                    return
                }

                switch result {
                case let .success(image):
                    let additionalBytes = self.servedImageIdentifiers.contains(identifier)
                        ? 0
                        : image.data.count
                    guard additionalBytes <= Self.maximumDocumentImageBytes - self.servedImageBytes else {
                        self.fail(pendingTask.schemeTask, code: .dataLengthExceedsMaximum)
                        return
                    }
                    self.servedImageIdentifiers.insert(identifier)
                    self.servedImageBytes += additionalBytes
                    self.respond(
                        to: pendingTask.schemeTask,
                        url: requestURL,
                        mimeType: image.mimeType,
                        textEncodingName: nil,
                        data: image.data
                    )
                case .failure:
                    self.fail(pendingTask.schemeTask, code: .cannotOpenFile)
                }
            }
        }
    }

    private func respond(
        to task: any WKURLSchemeTask,
        url: URL,
        mimeType: String,
        textEncodingName: String?,
        data: Data
    ) {
        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: textEncodingName
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: any WKURLSchemeTask, code: URLError.Code) {
        task.didFailWithError(URLError(code))
    }
}
