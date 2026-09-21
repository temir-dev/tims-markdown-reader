import Foundation

enum HTML {
    static func text(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)

        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }

        return result
    }

    static func attribute(_ value: String) -> String {
        text(value).replacingOccurrences(of: "\n", with: "&#10;")
    }
}
