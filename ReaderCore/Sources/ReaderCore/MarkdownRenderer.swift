import Foundation
import Markdown

public struct RenderedDocument: Sendable {
    public let html: String
    public let images: [String: String]
    public let localLinks: [String: LocalDocumentLink]
    public let mermaidCount: Int
    public let resourceToken: String

    public init(
        html: String,
        images: [String: String] = [:],
        localLinks: [String: LocalDocumentLink] = [:],
        mermaidCount: Int = 0,
        resourceToken: String = UUID().uuidString.lowercased()
    ) {
        self.html = html
        self.images = images
        self.localLinks = localLinks
        self.mermaidCount = mermaidCount
        self.resourceToken = resourceToken
    }
}

public enum MarkdownRenderer {
    public static func render(_ source: String, title: String = "Tim’s Markdown Reader") -> RenderedDocument {
        let footnoteSource = Footnotes.extract(from: source)
        let document = Document(parsing: footnoteSource.markdown)
        let resourceToken = UUID().uuidString.lowercased()
        var visitor = SafeHTMLVisitor(
            footnoteDefinitions: footnoteSource.definitions,
            resourceToken: resourceToken
        )
        let content = visitor.visit(document) + visitor.renderFootnotes()
        return RenderedDocument(
            html: ReaderShell.document(
                title: title,
                content: content,
                includeMermaid: visitor.mermaidCount > 0
            ),
            images: visitor.imageSources,
            localLinks: visitor.localLinks,
            mermaidCount: visitor.mermaidCount,
            resourceToken: resourceToken
        )
    }

    public static func loadingDocument() -> RenderedDocument {
        RenderedDocument(html: ReaderShell.document(
            title: "Tim’s Markdown Reader",
            content: "<p class=\"status\">Loading…</p>"
        ))
    }

    public static func errorDocument(title: String, message: String) -> RenderedDocument {
        let content = """
        <section class="error-state" role="alert">
        <h1>Unable to open this document</h1>
        <p>\(HTML.text(message))</p>
        </section>
        """
        return RenderedDocument(html: ReaderShell.document(title: title, content: content))
    }
}

private struct SafeHTMLVisitor: MarkupVisitor {
    typealias Result = String

    private static let maximumImageCount = 200
    private static let maximumLocalLinkCount = 500
    private static let maximumAutomaticLinkCount = 1_000
    private let footnoteDefinitions: [String: String]
    private let resourceToken: String
    private let linkDetector: NSDataDetector?
    private var footnoteOrder: [String] = []
    private var footnoteNumbers: [String: Int] = [:]
    private var footnoteReferenceCounts: [String: Int] = [:]
    private var tableAlignments: [Table.ColumnAlignment?] = []
    private var currentTableColumn = 0
    private var inTableHead = false
    private var imageIdentifiersBySource: [String: String] = [:]
    private var localLinkIdentifiersByDestination: [LocalDocumentLink: String] = [:]
    private var headingSlugCounts: [String: Int] = [:]
    private var usedHeadingIdentifiers: Set<String> = []
    private var isRenderingLink = false
    private var automaticLinkCount = 0
    private(set) var imageSources: [String: String] = [:]
    private(set) var localLinks: [String: LocalDocumentLink] = [:]
    private(set) var mermaidCount = 0

    init(footnoteDefinitions: [String: String], resourceToken: String) {
        self.footnoteDefinitions = footnoteDefinitions
        self.resourceToken = resourceToken
        linkDetector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        )
    }

    mutating func defaultVisit(_ markup: Markup) -> String {
        renderChildren(of: markup)
    }

    mutating func visitDocument(_ document: Document) -> String {
        renderChildren(of: document)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\(renderChildren(of: blockQuote))</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        guard codeBlock.code.utf8.count <= 500 * 1_024 else {
            return "<div class=\"limit-placeholder\">Code block omitted: larger than 500 KiB.</div>\n"
        }

        let rawLanguage = codeBlock.language?
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)
            .map { $0.lowercased() }
        if rawLanguage == "mermaid" {
            guard mermaidCount < 100 else {
                return "<div class=\"limit-placeholder\">Mermaid diagram omitted: more than 100 diagrams.</div>\n"
            }
            mermaidCount += 1
            return "<div class=\"mermaid-diagram\" data-mermaid-diagram><pre class=\"mermaid-source\"><code>\(HTML.text(codeBlock.code))</code></pre></div>\n"
        }

        let language = rawLanguage
            .map(safeLanguageName)
        let classAttribute = language.map { " class=\"language-\(HTML.attribute($0))\"" } ?? ""
        return "<pre><code\(classAttribute)>\(HTML.text(codeBlock.code))</code></pre>\n"
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = min(max(heading.level, 1), 6)
        let identifier = headingIdentifier(for: heading)
        return "<h\(level) id=\"\(HTML.attribute(identifier))\">\(renderChildren(of: heading))</h\(level)>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        "<pre class=\"raw-markup\"><code>\(HTML.text(html.rawHTML))</code></pre>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        let checkbox: String
        switch listItem.checkbox {
        case .checked:
            checkbox = "<input type=\"checkbox\" checked disabled aria-label=\"Completed task\">"
        case .unchecked:
            checkbox = "<input type=\"checkbox\" disabled aria-label=\"Incomplete task\">"
        case nil:
            checkbox = ""
        }
        guard listItem.checkbox != nil else {
            return "<li>\(renderChildren(of: listItem))</li>\n"
        }
        return "<li class=\"task-list-item\">\(checkbox)<div class=\"task-list-content\">\(renderChildren(of: listItem))</div></li>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        return "<ol\(start)>\n\(renderChildren(of: orderedList))</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let hasTasks = unorderedList.children.contains { child in
            (child as? ListItem)?.checkbox != nil
        }
        let classAttribute = hasTasks ? " class=\"task-list\"" : ""
        return "<ul\(classAttribute)>\n\(renderChildren(of: unorderedList))</ul>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        if paragraph.childCount == 1,
           let image = paragraph.child(at: 0) as? Image {
            return renderImage(image, asBlock: true) + "\n"
        }
        return "<p>\(renderChildren(of: paragraph))</p>\n"
    }

    mutating func visitTable(_ table: Table) -> String {
        let previousAlignments = tableAlignments
        tableAlignments = table.columnAlignments
        let content = renderChildren(of: table)
        tableAlignments = previousAlignments
        return "<div class=\"table-scroll\" role=\"region\" aria-label=\"Scrollable table\" tabindex=\"0\"><table>\n\(content)</table></div>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> String {
        let previous = inTableHead
        inTableHead = true
        currentTableColumn = 0
        let content = renderChildren(of: tableHead)
        inTableHead = previous
        return "<thead><tr>\n\(content)</tr></thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> String {
        guard !tableBody.isEmpty else { return "" }
        return "<tbody>\n\(renderChildren(of: tableBody))</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) -> String {
        currentTableColumn = 0
        return "<tr>\n\(renderChildren(of: tableRow))</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) -> String {
        guard tableCell.colspan > 0, tableCell.rowspan > 0 else { return "" }
        let element = inTableHead ? "th" : "td"
        var attributes = ""

        if currentTableColumn < tableAlignments.count,
           let alignment = tableAlignments[currentTableColumn] {
            attributes += " class=\"align-\(alignment.cssName)\""
        }
        currentTableColumn += 1

        if tableCell.colspan > 1 {
            attributes += " colspan=\"\(tableCell.colspan)\""
        }
        if tableCell.rowspan > 1 {
            attributes += " rowspan=\"\(tableCell.rowspan)\""
        }

        return "<\(element)\(attributes)>\(renderChildren(of: tableCell))</\(element)>\n"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(HTML.text(inlineCode.code))</code>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(renderChildren(of: emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(renderChildren(of: strong))</strong>"
    }

    mutating func visitImage(_ image: Image) -> String {
        renderImage(image, asBlock: false)
    }

    private mutating func renderImage(_ image: Image, asBlock: Bool) -> String {
        var plainTextVisitor = PlainTextVisitor()
        let alternative = plainTextVisitor.renderChildren(of: image)
        let label = alternative.isEmpty ? "Image" : "Image: \(alternative)"

        guard let source = image.source,
              let normalizedSource = ImageResourceResolver.normalizedSource(source),
              ImageResourceResolver.accepts(source: source) else {
            let placeholder = "<span class=\"image-placeholder\" role=\"img\" aria-label=\"\(HTML.attribute(label))\">▧ \(HTML.text(alternative))</span>"
            return asBlock ? "<p>\(placeholder)</p>" : placeholder
        }

        let identifier: String
        if let existing = imageIdentifiersBySource[normalizedSource] {
            identifier = existing
        } else {
            guard imageSources.count < Self.maximumImageCount else {
                let placeholder = "<span class=\"limit-placeholder\" role=\"img\" aria-label=\"\(HTML.attribute(label))\">Image omitted: more than \(Self.maximumImageCount) unique images.</span>"
                return asBlock ? "<p>\(placeholder)</p>" : placeholder
            }
            identifier = "image-\(imageSources.count)"
            // The scheme handler decodes this URL path once when it opens the file.
            // Escape literal percent signs so a filename such as "a%20.png" survives.
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "%?#"))
            imageSources[identifier] = normalizedSource.addingPercentEncoding(withAllowedCharacters: allowed)
            imageIdentifiersBySource[normalizedSource] = identifier
        }

        let title = image.title.map { " title=\"\(HTML.attribute($0))\"" } ?? ""
        let imageElement = "<img src=\"markdown-reader://document/image/\(resourceToken)/\(identifier)\" alt=\"\(HTML.attribute(alternative))\"\(title)>"
        if asBlock {
            return "<figure class=\"local-image\">\(imageElement)</figure>"
        }
        return "<span class=\"local-image-inline\">\(imageElement)</span>"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        "<code class=\"raw-markup-inline\">\(HTML.text(inlineHTML.rawHTML))</code>"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLink(_ link: Link) -> String {
        let previousLinkState = isRenderingLink
        isRenderingLink = true
        let content = renderChildren(of: link)
        isRenderingLink = previousLinkState

        guard let destination = link.destination else {
            return blockedLink(content)
        }

        let title = link.title.map { " title=\"\(HTML.attribute($0))\"" } ?? ""
        if let safeDestination = safeExternalOrAnchorDestination(destination) {
            return "<a href=\"\(HTML.attribute(safeDestination))\"\(title)>\(content)</a>"
        }
        if let localLink = LocalDocumentLinkResolver.parse(destination),
           let identifier = register(localLink: localLink) {
            let href = "markdown-reader://document/link/\(resourceToken)/\(identifier)"
            return "<a href=\"\(href)\"\(title)>\(content)</a>"
        }
        return blockedLink(content)
    }

    mutating func visitText(_ text: Text) -> String {
        renderTextWithFootnotes(text.string)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(renderChildren(of: strikethrough))</del>"
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> String {
        HTML.text(symbolLink.destination ?? "")
    }

    mutating func visitBlockDirective(_ blockDirective: BlockDirective) -> String {
        HTML.text(blockDirective.format())
    }

    mutating func visitCustomBlock(_ customBlock: CustomBlock) -> String {
        renderChildren(of: customBlock)
    }

    mutating func visitCustomInline(_ customInline: CustomInline) -> String {
        renderChildren(of: customInline)
    }

    mutating func visitInlineAttributes(_ attributes: InlineAttributes) -> String {
        renderChildren(of: attributes)
    }

    mutating func renderFootnotes() -> String {
        guard !footnoteOrder.isEmpty else { return "" }
        // Discover nested references before producing backlinks. Each definition is
        // visited once, so cycles terminate and every referenced note gets a body.
        var bodies: [(label: String, content: String)] = []
        var index = 0
        while index < footnoteOrder.count {
            let label = footnoteOrder[index]
            index += 1
            guard let markdown = footnoteDefinitions[label] else { continue }
            bodies.append((label, visit(Document(parsing: markdown))))
        }

        // Colons cannot occur in generated heading slugs, avoiding ID collisions.
        var result = "<section class=\"footnotes\" aria-label=\"Footnotes\"><hr><ol>\n"
        for (label, content) in bodies {
            guard let number = footnoteNumbers[label] else { continue }
            let referenceCount = footnoteReferenceCounts[label, default: 1]
            let backlinks = (1...referenceCount).map { reference in
                let suffix = referenceCount == 1 ? "" : "\(reference)"
                return "<a class=\"footnote-backref\" href=\"#footnote-ref:\(number):\(reference)\" aria-label=\"Back to reference \(number)\(suffix)\">↩</a>"
            }.joined(separator: " ")
            result += "<li id=\"footnote:\(number)\">\(content)\(backlinks)</li>\n"
        }
        result += "</ol></section>\n"
        return result
    }

    private mutating func renderChildren(of markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    private mutating func renderTextWithFootnotes(_ value: String) -> String {
        // Links cannot contain other links, including generated footnote links.
        guard !isRenderingLink else { return HTML.text(value) }
        var output = ""
        var cursor = value.startIndex

        while cursor < value.endIndex,
              let opening = value[cursor...].range(of: "[^") {
            output += renderDetectedLinks(String(value[cursor..<opening.lowerBound]))
            guard let closing = value[opening.upperBound...].firstIndex(of: "]") else {
                output += HTML.text(String(value[opening.lowerBound...]))
                return output
            }

            let rawLabel = String(value[opening.upperBound..<closing])
            let label = Footnotes.normalize(rawLabel)
            guard !label.isEmpty, footnoteDefinitions[label] != nil else {
                output += HTML.text(String(value[opening.lowerBound...closing]))
                cursor = value.index(after: closing)
                continue
            }

            let number: Int
            if let existing = footnoteNumbers[label] {
                number = existing
            } else {
                number = footnoteOrder.count + 1
                footnoteOrder.append(label)
                footnoteNumbers[label] = number
            }

            let reference = footnoteReferenceCounts[label, default: 0] + 1
            footnoteReferenceCounts[label] = reference
            output += "<sup class=\"footnote-ref\"><a href=\"#footnote:\(number)\" id=\"footnote-ref:\(number):\(reference)\" aria-label=\"Footnote \(number)\">\(number)</a></sup>"
            cursor = value.index(after: closing)
        }

        output += renderDetectedLinks(String(value[cursor...]))
        return output
    }

    private mutating func renderDetectedLinks(_ value: String) -> String {
        guard !value.isEmpty,
              !isRenderingLink,
              automaticLinkCount < Self.maximumAutomaticLinkCount,
              let linkDetector else {
            return HTML.text(value)
        }

        let source = value as NSString
        let matches = linkDetector.matches(
            in: value,
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else { return HTML.text(value) }

        var result = ""
        var cursor = 0
        for match in matches {
            guard automaticLinkCount < Self.maximumAutomaticLinkCount,
                  match.range.location >= cursor,
                  let detectedURL = match.url,
                  let destination = safeExternalOrAnchorDestination(detectedURL.absoluteString),
                  !destination.hasPrefix("#") else {
                continue
            }
            result += HTML.text(source.substring(with: NSRange(
                location: cursor,
                length: match.range.location - cursor
            )))
            let label = source.substring(with: match.range)
            result += "<a href=\"\(HTML.attribute(destination))\">\(HTML.text(label))</a>"
            cursor = NSMaxRange(match.range)
            automaticLinkCount += 1
        }
        result += HTML.text(source.substring(from: cursor))
        return result
    }

    private mutating func register(localLink: LocalDocumentLink) -> String? {
        if let identifier = localLinkIdentifiersByDestination[localLink] {
            return identifier
        }
        guard localLinks.count < Self.maximumLocalLinkCount else { return nil }
        let identifier = "link-\(localLinks.count)"
        localLinks[identifier] = localLink
        localLinkIdentifiersByDestination[localLink] = identifier
        return identifier
    }

    private func blockedLink(_ content: String) -> String {
        "<span class=\"link-pending\" title=\"Blocked unsafe or unsupported link\">\(content)</span>"
    }

    private func safeLanguageName(_ value: String) -> String {
        String(value.lowercased().filter { character in
            character.isLetter || character.isNumber || "_+-".contains(character)
        }.prefix(64))
    }

    private mutating func headingIdentifier(for heading: Heading) -> String {
        var visitor = PlainTextVisitor()
        let text = visitor.renderChildren(of: heading)
        var base = ""
        var needsSeparator = false

        for character in text {
            if character.isLetter || character.isNumber {
                if needsSeparator, !base.isEmpty {
                    base.append("-")
                }
                base.append(contentsOf: character.lowercased())
                needsSeparator = false
            } else if !base.isEmpty {
                needsSeparator = true
            }
        }

        if base.isEmpty { base = "section" }
        var occurrence = headingSlugCounts[base, default: 0] + 1
        var identifier = occurrence == 1 ? base : "\(base)-\(occurrence)"
        while usedHeadingIdentifiers.contains(identifier) {
            occurrence += 1
            identifier = "\(base)-\(occurrence)"
        }
        headingSlugCounts[base] = occurrence
        usedHeadingIdentifiers.insert(identifier)
        return identifier
    }

    private func safeExternalOrAnchorDestination(_ value: String) -> String? {
        guard !value.isEmpty,
              !value.contains(where: { $0.isNewline || $0.isASCIIControl }) else {
            return nil
        }

        if value.hasPrefix("#") {
            return value
        }

        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased() else {
            return nil
        }

        switch scheme {
        case "http", "https":
            guard components.host != nil,
                  components.user == nil,
                  components.password == nil else { return nil }
        case "mailto":
            guard !components.path.isEmpty else { return nil }
        default:
            return nil
        }

        return components.url?.absoluteString
    }
}

private struct PlainTextVisitor: MarkupVisitor {
    typealias Result = String

    mutating func defaultVisit(_ markup: Markup) -> String {
        renderChildren(of: markup)
    }

    mutating func visitText(_ text: Text) -> String { text.string }
    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String { inlineCode.code }
    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String { inlineHTML.rawHTML }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { " " }
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { " " }

    mutating func renderChildren(of markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }
}

private extension Character {
    var isASCIIControl: Bool {
        unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}

private extension Table.ColumnAlignment {
    var cssName: String {
        switch self {
        case .left: "left"
        case .center: "center"
        case .right: "right"
        }
    }
}
