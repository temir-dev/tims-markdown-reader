import CryptoKit
import Foundation
import Testing
@testable import ReaderCore

@Test func rendersGFMAndFootnotes() {
    let source = """
    # Reader

    ~~Removed~~ and a note.[^note]

    - [x] complete
    - [ ] pending
      - nested

    | Left | Right |
    | :--- | ----: |
    | one  | two   |

    ```swift
    let value = "<safe>"
    ```

    [^note]: Footnote with **strong text**.
    """

    let html = MarkdownRenderer.render(source).html
    #expect(html.contains("<h1 id=\"reader\">Reader</h1>"))
    #expect(html.contains("<del>Removed</del>"))
    #expect(html.contains("type=\"checkbox\" checked disabled"))
    #expect(html.contains("type=\"checkbox\" disabled"))
    #expect(html.contains("class=\"task-list-content\""))
    #expect(html.contains("<div class=\"table-scroll\""))
    #expect(html.contains("class=\"align-right\""))
    #expect(html.contains("class=\"language-swift\""))
    #expect(html.contains("&lt;safe&gt;"))
    #expect(html.contains("id=\"footnote-ref:1:1\""))
    #expect(html.contains("<li id=\"footnote:1\">"))
    #expect(html.contains("Footnote with <strong>strong text</strong>."))
}

@Test func neverEmitsDocumentHTML() {
    let source = """
    <script>globalThis.pwned = true</script>

    <img src=x onerror="globalThis.pwned = true">

    [bad](javascript:alert(1))

    ![secret](data:text/html;base64,SGVsbG8=)
    """

    let html = MarkdownRenderer.render(source).html
    #expect(!html.contains("<script>globalThis.pwned"))
    #expect(!html.contains("<img src=x"))
    #expect(!html.contains("href=\"javascript:"))
    #expect(!html.contains("src=\"data:"))
    #expect(html.contains("&lt;script&gt;globalThis.pwned"))
    #expect(html.contains("class=\"link-pending\""))
    #expect(html.contains("class=\"image-placeholder\""))
}

@Test func mapsOnlySafeRelativeRasterImagesToOpaqueURLs() {
    let source = """
    ![local](images/photo.png "A local image")

    ![remote](https://example.com/photo.png)

    ![absolute](/private/tmp/photo.png)

    ![traversal](../photo.png)

    ![vector](diagram.svg)
    """

    let document = MarkdownRenderer.render(source)
    #expect(document.images == ["image-0": "images/photo.png"])
    #expect(document.html.contains("src=\"markdown-reader://document/image/\(document.resourceToken)/image-0\""))
    #expect(document.html.contains("<figure class=\"local-image\"><img"))
    #expect(!document.html.contains("<p><figure"))
    #expect(document.html.contains("alt=\"local\""))
    #expect(document.html.contains("title=\"A local image\""))
    #expect(document.html.components(separatedBy: "class=\"image-placeholder\"").count == 5)
    #expect(!document.html.contains("https://example.com/photo.png"))
    #expect(!document.html.contains("/private/tmp/photo.png"))
}

@Test func emitsLockedDownShellAndOnlySafeClickableLinks() {
    let source = """
    [web](https://example.com/path?q=one)
    [email](mailto:reader@example.com)
    [local](#section)
    [credentials](https://user:password@example.com/)
    """

    let html = MarkdownRenderer.render(source).html
    #expect(html.contains("default-src 'none'; base-uri 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src markdown-reader:; connect-src 'none'; frame-src 'self'; worker-src 'none'; object-src 'none'; form-action 'none'"))
    #expect(html.contains("href=\"markdown-reader://document/assets/reader.css\""))
    #expect(html.contains("href=\"https://example.com/path?q=one\""))
    #expect(html.contains("href=\"mailto:reader@example.com\""))
    #expect(html.contains("href=\"#section\""))
    #expect(!html.contains("user:password"))
}

@Test func rendersExplicitReferenceAutomaticAndLocalLinks() {
    let source = """
    [explicit](https://example.com/path?q=one&two=2 "Title")
    [reference][docs]
    <https://example.org/autolink>
    Bare https://example.net/bare?q=1&two=2 and www.example.com/home.
    Email reader@example.com.
    [local guide](docs/guide%20one.md#hello-world)
    [same guide](docs/./guide%20one.md#hello-world)

    [docs]: https://developer.apple.com/documentation/webkit
    """

    let document = MarkdownRenderer.render(source)
    #expect(document.html.contains("href=\"https://example.com/path?q=one&amp;two=2\" title=\"Title\""))
    #expect(document.html.contains("href=\"https://developer.apple.com/documentation/webkit\""))
    #expect(document.html.contains("href=\"https://example.org/autolink\""))
    #expect(document.html.contains(">https://example.net/bare?q=1&amp;two=2</a>"))
    #expect(document.html.contains(">www.example.com/home</a>."))
    #expect(document.html.contains("href=\"mailto:reader@example.com\""))
    #expect(document.localLinks == [
        "link-0": LocalDocumentLink(path: "docs/guide one.md", fragment: "hello-world"),
    ])
    #expect(document.html.components(separatedBy: "/link-0\"").count == 3)
}

@Test func keepsUnsafeAndUnsupportedLinksNonClickable() {
    let source = """
    [script](javascript:alert(1))
    [file](file:///private/etc/passwd)
    [credentials](https://user:password@example.com/)
    [traversal](../secret.md)
    [absolute](/private/secret.md)
    [unsupported](notes.txt)
    [query](notes.md?download=true)
    """

    let document = MarkdownRenderer.render(source)
    #expect(document.localLinks.isEmpty)
    #expect(document.html.components(separatedBy: "class=\"link-pending\"").count == 8)
    #expect(!document.html.contains("href=\"javascript:"))
    #expect(!document.html.contains("href=\"file:"))
    #expect(!document.html.contains("user:password"))
}

@Test func deduplicatesAndLimitsLocalImages() {
    let duplicateDocument = MarkdownRenderer.render("""
    ![first](images/photo.png)

    ![second](images/./photo.png)
    """)
    #expect(duplicateDocument.images == ["image-0": "images/photo.png"])
    #expect(duplicateDocument.html.components(separatedBy: "/image-0\"").count == 3)

    let manyImages = (0...200)
        .map { "![image \($0)](images/image-\($0).png)" }
        .joined(separator: "\n\n")
    let limitedDocument = MarkdownRenderer.render(manyImages)
    #expect(limitedDocument.images.count == 200)
    #expect(limitedDocument.html.contains("Image omitted: more than 200 unique images."))
    #expect(limitedDocument.html.contains("<p><span class=\"limit-placeholder\""))
}

@Test func emitsValidBlockAndInlineImageMarkup() {
    let block = MarkdownRenderer.render("![block](image.png)").html
    #expect(block.contains("<figure class=\"local-image\"><img"))
    #expect(!block.contains("<p><figure"))

    let inline = MarkdownRenderer.render("Before ![inline](image.png) after.").html
    #expect(inline.contains("<p>Before <span class=\"local-image-inline\"><img"))
    #expect(!inline.contains("<figure"))

    let blocked = MarkdownRenderer.render("![blocked](image.svg)").html
    #expect(blocked.contains("<p><span class=\"image-placeholder\""))
    let blockedInline = MarkdownRenderer.render("Before ![blocked](image.svg) after.").html
    #expect(blockedInline.contains("<p>Before <span class=\"image-placeholder\""))
}

@Test func createsStableUniqueHeadingAnchors() {
    let html = MarkdownRenderer.render("""
    # Hello, World!
    ## Hello World
    ### !!!
    """).html
    #expect(html.contains("<h1 id=\"hello-world\">"))
    #expect(html.contains("<h2 id=\"hello-world-2\">"))
    #expect(html.contains("<h3 id=\"section\">"))
}

@Test func showsMDXJSXLiterally() {
    let html = MarkdownRenderer.render("<Callout kind=\"tip\">Hello</Callout>").html
    #expect(!html.contains("<Callout"))
    #expect(html.contains("&lt;Callout kind=&quot;tip&quot;&gt;"))
}

@Test func doesNotTreatFencedDefinitionsAsFootnotes() {
    let source = """
    Reference [^demo].

    ```text
    [^demo]: not a definition
    ```
    """

    let html = MarkdownRenderer.render(source).html
    #expect(!html.contains("class=\"footnotes\""))
    #expect(html.contains("[^demo]"))
}

@Test func appliesRequestedReadingTypography() {
    let stylesheet = ReaderAssets.stylesheet
    #expect(stylesheet.contains("font-size: var(--reader-text-size, 17px)"))
    #expect(stylesheet.contains("line-height: 1.6"))
    #expect(stylesheet.contains("--prose-measure: 60rem"))
    #expect(stylesheet.contains("--prose-inset: max(0px, calc((100% - var(--prose-measure)) / 2))"))
    #expect(stylesheet.contains("max-width: none"))
    #expect(stylesheet.contains("clamp(24px, 5vw, 80px)"))
    #expect(stylesheet.contains("width: min(100%, var(--prose-measure))"))
    #expect(stylesheet.contains(".reader > :is(.table-scroll, .mermaid-diagram, pre, .local-image)"))
    #expect(stylesheet.contains("width: calc(100% - var(--prose-inset))"))
    #expect(stylesheet.contains("margin-left: var(--prose-inset)"))
    #expect(stylesheet.contains("ui-monospace, SFMono-Regular, Menlo"))
    #expect(stylesheet.contains("prefers-color-scheme: dark"))
    #expect(stylesheet.contains("--background: #1c1c1e"))
    #expect(stylesheet.contains("--link: #075db7"))
    #expect(stylesheet.contains("--accent-soft: #f4f5f6"))
    #expect(stylesheet.contains("background: var(--accent-soft)"))
    #expect(stylesheet.contains("border-left: 3px solid var(--link)"))
    #expect(stylesheet.contains("border-radius: 12px"))
    #expect(stylesheet.contains("tbody tr:nth-child(even)"))
    #expect(stylesheet.contains(".footnote-ref a"))
    #expect(stylesheet.contains("::selection"))
}

@Test func rendersMermaidThroughPinnedOfflineAssets() throws {
    let source = """
    ```mermaid
    flowchart LR
      Start --> Finish[<script>alert(1)</script>]
    ```
    """

    let document = MarkdownRenderer.render(source)
    #expect(document.mermaidCount == 1)
    #expect(document.html.contains("data-mermaid-diagram"))
    #expect(document.html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
    #expect(!document.html.contains("<script>alert(1)</script>"))
    #expect(document.html.contains("markdown-reader://document/assets/mermaid.min.js"))
    #expect(document.html.contains("markdown-reader://document/assets/mermaid-bootstrap.js"))

    let bootstrap = try #require(String(data: ReaderAssets.mermaidBootstrap, encoding: .utf8))
    #expect(bootstrap.contains("securityLevel: \"sandbox\""))
    #expect(bootstrap.contains("frame.setAttribute(\"sandbox\", \"\")"))
    #expect(!bootstrap.contains("webkit.messageHandlers"))
    #expect(!bootstrap.contains("fetch("))
    #expect(!bootstrap.contains("XMLHttpRequest"))
}

@Test func omitsMermaidScriptsFromOrdinaryDocuments() {
    let document = MarkdownRenderer.render("# Plain Markdown")
    #expect(document.mermaidCount == 0)
    #expect(!document.html.contains("mermaid.min.js"))
    #expect(!document.html.contains("mermaid-bootstrap.js"))
}

@Test func enforcesMermaidCountAndSizeLimits() {
    let diagram = """
    ```mermaid
    flowchart LR
      A --> B
    ```
    """
    let many = Array(repeating: diagram, count: 101).joined(separator: "\n\n")
    let manyDocument = MarkdownRenderer.render(many)
    #expect(manyDocument.mermaidCount == 100)
    #expect(manyDocument.html.contains("Mermaid diagram omitted: more than 100 diagrams."))

    let oversized = "```mermaid\n" + String(repeating: "A", count: 500 * 1_024 + 1) + "\n```"
    let oversizedDocument = MarkdownRenderer.render(oversized)
    #expect(oversizedDocument.mermaidCount == 0)
    #expect(oversizedDocument.html.contains("Code block omitted: larger than 500 KiB."))
}

@Test func pinsTheVendoredMermaidRuntime() {
    #expect(ReaderAssets.mermaidVersion == "11.16.1")
    #expect(!ReaderAssets.mermaidRuntime.isEmpty)

    let digest = SHA256.hash(data: ReaderAssets.mermaidRuntime)
        .map { String(format: "%02x", $0) }
        .joined()
    #expect(digest == "18327bef70d96fb505fe7287d9f6a7362ebf07ff6576ddfaffb1a06f3e1a2954")
}

@Test func headingAnchorsRemainUniqueWhenNaturalNamesMatchGeneratedSuffixes() {
    let html = MarkdownRenderer.render("# Topic\n# Topic\n# Topic-2\n# Topic").html
    let ids = html.components(separatedBy: "<h1 id=\"").dropFirst().map { String($0.prefix(while: { $0 != "\"" })) }
    #expect(Set(ids).count == 4)
}

@Test func rendersFootnotesReferencedInsideOtherFootnotesWithoutDroppingThem() {
    let html = MarkdownRenderer.render("""
    See [^one].

    [^one]: Also see [^two].
    [^two]: The nested note, pointing back [^one].
    """).html
    #expect(html.contains("<li id=\"footnote:2\">"))
    #expect(html.contains("The nested note"))
    #expect(html.contains("href=\"#footnote-ref:1:2\""))
}

@Test func footnoteDefinitionsPreserveParagraphBoundaries() {
    let html = MarkdownRenderer.render("""
    First paragraph.[^note]
    [^note]: A note.

    Second paragraph.
    """).html
    #expect(html.contains("</p>\n<p>Second paragraph.</p>"))
}
