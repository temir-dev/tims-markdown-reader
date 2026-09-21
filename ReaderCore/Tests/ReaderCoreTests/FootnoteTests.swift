import Foundation
import Testing
@testable import ReaderCore

@Test(arguments: ["\n", "\r\n", "\r"])
func footnotesSupportCommonLineEndings(_ newline: String) {
    let source = ["# Notes", "", "A reference.[^one]", "", "[^one]: First paragraph.", "", "    Second paragraph."].joined(separator: newline)
    let html = MarkdownRenderer.render(source).html
    #expect(html.contains("class=\"footnotes\""))
    #expect(html.contains("<p>First paragraph.</p>"))
    #expect(html.contains("<p>Second paragraph.</p>"))
}

@Test func footnoteAndHeadingAnchorsNeverCollide() throws {
    let html = MarkdownRenderer.render("# fn-1\n\n# fnref-1-1\n\nReference.[^one]\n\n[^one]: A note.").html
    let pattern = try NSRegularExpression(pattern: #"\bid="([^"]+)""#)
    let text = html as NSString
    let identifiers = pattern.matches(in: html, range: NSRange(location: 0, length: text.length)).map { text.substring(with: $0.range(at: 1)) }
    #expect(identifiers.count == Set(identifiers).count)
}

@Test func footnoteTextInsideALinkDoesNotCreateNestedLinks() {
    let html = MarkdownRenderer.render("[Read this [^one]](https://example.com)\n\n[^one]: A note.").html
    #expect(html.contains(">Read this [^one]</a>"))
    #expect(!html.contains("class=\"footnote-ref\""))
}
