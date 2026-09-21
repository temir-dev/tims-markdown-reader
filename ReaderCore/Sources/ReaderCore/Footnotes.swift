import Foundation

struct FootnoteSource: Sendable {
    let markdown: String
    let definitions: [String: String]
}

enum Footnotes {
    static func extract(from source: String) -> FootnoteSource {
        // Swift treats CRLF as one Character. Normalize common file line endings
        // before extracting definitions so Windows-authored notes work as well.
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var definitions: [String: String] = [:]
        var index = 0
        var fence: Fence?

        while index < lines.count {
            let line = lines[index]

            if let currentFence = fence {
                output.append(line)
                if currentFence.closes(line) {
                    fence = nil
                }
                index += 1
                continue
            }

            if let openingFence = Fence(opening: line) {
                fence = openingFence
                output.append(line)
                index += 1
                continue
            }

            guard let definition = parseDefinition(line) else {
                output.append(line)
                index += 1
                continue
            }

            var bodyLines = [definition.firstLine]
            var next = index + 1
            var pendingBlankLines = 0

            while next < lines.count {
                let candidate = lines[next]

                if candidate.isEmpty {
                    pendingBlankLines += 1
                    next += 1
                    continue
                }

                if candidate.hasPrefix("    ") {
                    bodyLines.append(contentsOf: repeatElement("", count: pendingBlankLines))
                    pendingBlankLines = 0
                    bodyLines.append(String(candidate.dropFirst(4)))
                    next += 1
                    continue
                }

                if candidate.hasPrefix("\t") {
                    bodyLines.append(contentsOf: repeatElement("", count: pendingBlankLines))
                    pendingBlankLines = 0
                    bodyLines.append(String(candidate.dropFirst()))
                    next += 1
                    continue
                }

                break
            }

            let key = normalize(definition.label)
            if !key.isEmpty, definitions[key] == nil {
                definitions[key] = bodyLines.joined(separator: "\n")
            }
            // Removing a definition must not join surrounding prose paragraphs.
            output.append(contentsOf: repeatElement("", count: max(1, pendingBlankLines)))
            index = next
        }

        return FootnoteSource(
            markdown: output.joined(separator: "\n"),
            definitions: definitions
        )
    }

    static func normalize(_ label: String) -> String {
        label
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private static func parseDefinition(_ line: String) -> (label: String, firstLine: String)? {
        guard line.hasPrefix("[^"),
              let marker = line.range(of: "]:"),
              marker.lowerBound > line.index(line.startIndex, offsetBy: 2) else {
            return nil
        }

        let labelStart = line.index(line.startIndex, offsetBy: 2)
        let label = String(line[labelStart..<marker.lowerBound])
        guard !label.contains(where: { $0.isNewline }), label.count <= 256 else {
            return nil
        }

        let remainder = line[marker.upperBound...].drop(while: { $0 == " " || $0 == "\t" })
        return (label, String(remainder))
    }
}

private struct Fence {
    let marker: Character
    let length: Int

    init?(opening line: String) {
        let trimmed = line.drop(while: { $0 == " " })
        let indentation = line.distance(from: line.startIndex, to: trimmed.startIndex)
        guard indentation <= 3, let first = trimmed.first, first == "`" || first == "~" else {
            return nil
        }

        let count = trimmed.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        marker = first
        length = count
    }

    func closes(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " })
        let indentation = line.distance(from: line.startIndex, to: trimmed.startIndex)
        guard indentation <= 3 else { return false }

        let markers = trimmed.prefix(while: { $0 == marker })
        guard markers.count >= length else { return false }
        return trimmed.dropFirst(markers.count).allSatisfy(\.isWhitespace)
    }
}
