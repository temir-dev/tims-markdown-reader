import Foundation

enum ReaderShell {
    static func document(
        title: String,
        content: String,
        includeMermaid: Bool = false
    ) -> String {
        let mermaidScripts = includeMermaid ? """
        <script src="markdown-reader://document/assets/mermaid.min.js" defer></script>
        <script src="markdown-reader://document/assets/mermaid-bootstrap.js" defer></script>
        """ : ""

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; base-uri 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src markdown-reader:; connect-src 'none'; frame-src 'self'; worker-src 'none'; object-src 'none'; form-action 'none'">
        <title>\(HTML.text(title))</title>
        <link rel="stylesheet" href="markdown-reader://document/assets/reader.css">
        \(mermaidScripts)
        </head>
        <body><main class="reader">\(content)</main></body>
        </html>
        """
    }
}

public enum ReaderAssets {
    public static let mermaidVersion = "11.16.1"

    public static let stylesheet: String = {
        guard let url = Bundle.module.url(forResource: "reader", withExtension: "css"),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return "body{font-family:-apple-system,sans-serif;font-size:17px;line-height:1.6}.reader{width:100%;padding:48px clamp(24px,5vw,80px) 96px}"
        }
        return value
    }()

    public static let mermaidRuntime = resourceData(
        named: "mermaid.min",
        extension: "js"
    )

    public static let mermaidBootstrap = resourceData(
        named: "mermaid-bootstrap",
        extension: "js"
    )

    /// Injected by the app as a user script; never served to the document.
    public static let findScript = String(
        decoding: resourceData(named: "reader-find", extension: "js"),
        as: UTF8.self
    )

    private static func resourceData(named name: String, extension: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: `extension`),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return Data()
        }
        return data
    }
}
