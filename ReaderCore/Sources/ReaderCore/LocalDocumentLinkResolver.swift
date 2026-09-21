import Foundation

public struct LocalDocumentLink: Hashable, Sendable {
    public let path: String
    public let fragment: String?

    public init(path: String, fragment: String? = nil) {
        self.path = path
        self.fragment = fragment
    }
}

public enum LocalDocumentLinkResolver {
    private static let supportedExtensions = Set(["md", "markdown", "mdx"])

    public static func parse(_ destination: String) -> LocalDocumentLink? {
        guard !destination.isEmpty,
              !destination.contains("\0"),
              !destination.contains(where: { $0.isNewline || $0.isASCIIControl }),
              !destination.hasPrefix("/"),
              !destination.hasPrefix("~"),
              !NSString(string: destination).isAbsolutePath,
              let urlComponents = URLComponents(string: destination),
              urlComponents.scheme == nil,
              urlComponents.host == nil,
              urlComponents.user == nil,
              urlComponents.password == nil,
              urlComponents.query == nil,
              let decodedPath = urlComponents.percentEncodedPath.removingPercentEncoding,
              !decodedPath.isEmpty,
              !decodedPath.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
              !decodedPath.hasPrefix("/"),
              !NSString(string: decodedPath).isAbsolutePath else {
            return nil
        }

        let pathComponents = decodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." }
        guard !pathComponents.isEmpty,
              pathComponents.allSatisfy({ $0 != ".." }) else {
            return nil
        }

        let normalizedPath = pathComponents.joined(separator: "/")
        guard supportedExtensions.contains(
            NSString(string: normalizedPath).pathExtension.lowercased()
        ) else {
            return nil
        }

        let fragment = urlComponents.percentEncodedFragment?.removingPercentEncoding
        guard fragment?.contains(where: { $0.isNewline || $0.isASCIIControl }) != true,
              fragment?.utf8.count ?? 0 <= 1_024 else {
            return nil
        }
        return LocalDocumentLink(
            path: normalizedPath,
            fragment: fragment?.isEmpty == false ? fragment : nil
        )
    }

    public static func resolve(
        _ link: LocalDocumentLink,
        relativeTo documentURL: URL
    ) -> URL? {
        let documentDirectory = documentURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let candidate = documentDirectory
            .appendingPathComponent(link.path, isDirectory: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        let rootComponents = documentDirectory.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidate != documentDirectory,
              candidateComponents.count > rootComponents.count,
              candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents),
              supportedExtensions.contains(candidate.pathExtension.lowercased()),
              let values = try? candidate.resourceValues(forKeys: [
                  .isRegularFileKey,
                  .isDirectoryKey,
              ]),
              values.isRegularFile == true,
              values.isDirectory != true else {
            return nil
        }
        return candidate
    }
}

private extension Character {
    var isASCIIControl: Bool {
        unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}
