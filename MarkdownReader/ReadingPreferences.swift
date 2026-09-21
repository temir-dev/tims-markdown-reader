import Foundation

@MainActor
final class ReadingPreferences: NSObject {
    enum Font: String, CaseIterable {
        case system, serif, monospaced
        var title: String {
            switch self {
            case .system: return "System"
            case .serif: return "Serif"
            case .monospaced: return "Monospaced"
            }
        }
        var css: String {
            switch self {
            case .system: return "-apple-system, BlinkMacSystemFont, sans-serif"
            case .serif: return "Georgia, Times, serif"
            case .monospaced: return "ui-monospace, SFMono-Regular, Menlo, monospace"
            }
        }
    }
    enum Width: String { case centered, full }
    static let shared = ReadingPreferences()
    static let didChange = Notification.Name("ReadingPreferencesDidChange")
    static let defaultTextSize = 17.0
    static let sizeRange = 12.0...28.0
    private let defaults: UserDefaults
    private(set) var font: Font
    private(set) var textSize: Double
    private(set) var width: Width

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let values = defaults.dictionary(forKey: "readingAppearance") ?? [:]
        font = Font(rawValue: values["font"] as? String ?? "") ?? .system
        width = Width(rawValue: values["width"] as? String ?? "") ?? .centered
        textSize = Self.validSize(values["textSize"] as? Double ?? Self.defaultTextSize)
        super.init()
    }

    func update(font: Font? = nil, textSize: Double? = nil, width: Width? = nil) {
        let newFont = font ?? self.font
        let newSize = Self.validSize(textSize ?? self.textSize)
        let newWidth = width ?? self.width
        guard newFont != self.font || newSize != self.textSize || newWidth != self.width else { return }
        self.font = newFont
        self.textSize = newSize
        self.width = newWidth
        defaults.set(["font": newFont.rawValue, "textSize": newSize, "width": newWidth.rawValue], forKey: "readingAppearance")
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func restoreDefaults() { update(font: .system, textSize: Self.defaultTextSize, width: .centered) }

    private static func validSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTextSize }
        return min(max(value.rounded(), sizeRange.lowerBound), sizeRange.upperBound)
    }

    // Only fixed enum values and a bounded number are interpolated, never document text.
    var applicationScript: String {
        """
        (() => {
          const apply = () => {
            const root = document.documentElement;
            if (!root) return;
            root.style.setProperty('--reader-font', '\(font.css)');
            root.style.setProperty('--reader-text-size', '\(Int(textSize))px');
            root.dataset.readerWidth = '\(width.rawValue)';
            window.dispatchEvent(new Event('reader-settings-changed'));
          };
          if (document.documentElement) apply();
          else document.addEventListener('DOMContentLoaded', apply, {once: true});
        })();
        """
    }
}
