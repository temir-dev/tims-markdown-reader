import AppKit

@MainActor
final class ReadingSettingsWindowController: NSWindowController {
    private let preferences: ReadingPreferences
    private let fontChoice = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizeSlider = NSSlider(value: ReadingPreferences.defaultTextSize,
                                      minValue: ReadingPreferences.sizeRange.lowerBound,
                                      maxValue: ReadingPreferences.sizeRange.upperBound, target: nil, action: nil)
    private let sizeLabel = NSTextField(labelWithString: String(Int(ReadingPreferences.defaultTextSize)))
    private let smaller = NSButton(title: "−", target: nil, action: nil)
    private let larger = NSButton(title: "+", target: nil, action: nil)
    private let widthChoice = NSSegmentedControl(labels: ["Centered", "Full Width"], trackingMode: .selectOne, target: nil, action: nil)

    init(preferences: ReadingPreferences) {
        self.preferences = preferences
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 230),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent(in: window)
        refreshControls()
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: ReadingPreferences.didChange, object: preferences)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func buildContent(in window: NSWindow) {
        guard let content = window.contentView else { return }
        fontChoice.addItems(withTitles: ReadingPreferences.Font.allCases.map(\.title))
        fontChoice.target = self
        fontChoice.action = #selector(changeFont)
        fontChoice.setAccessibilityLabel("Reading font")
        sizeSlider.target = self
        sizeSlider.action = #selector(changeSize)
        sizeSlider.isContinuous = true
        sizeSlider.setAccessibilityLabel("Text size")
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        sizeLabel.alignment = .right
        sizeLabel.setAccessibilityLabel("Text size value")
        for (button, action, label) in [(smaller, #selector(decreaseSize), "Decrease text size"), (larger, #selector(increaseSize), "Increase text size")] {
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
            button.setAccessibilityLabel(label)
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        }
        widthChoice.target = self
        widthChoice.action = #selector(changeWidth)
        widthChoice.setAccessibilityLabel("Content width")
        let sizeRow = NSStackView(views: [smaller, sizeSlider, larger, sizeLabel])
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 6
        sizeSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        sizeLabel.widthAnchor.constraint(equalToConstant: 24).isActive = true
        let grid = NSGridView(views: [[NSTextField(labelWithString: "Font"), fontChoice],
                                      [NSTextField(labelWithString: "Text size"), sizeRow],
                                      [NSTextField(labelWithString: "Layout"), widthChoice]])
        grid.rowSpacing = 18
        grid.columnSpacing = 18
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }
        let note = NSTextField(labelWithString: "Applies to every document. Changes are saved automatically.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        reset.bezelStyle = .rounded
        for view in [grid, note, reset] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            note.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            note.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20),
            reset.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            reset.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 16),
            reset.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
    }

    @objc private func changeFont() {
        let choices = ReadingPreferences.Font.allCases
        guard choices.indices.contains(fontChoice.indexOfSelectedItem) else { return }
        preferences.update(font: choices[fontChoice.indexOfSelectedItem])
    }
    @objc private func changeSize() { preferences.update(textSize: sizeSlider.doubleValue) }
    @objc private func decreaseSize() { preferences.update(textSize: preferences.textSize - 1) }
    @objc private func increaseSize() { preferences.update(textSize: preferences.textSize + 1) }
    @objc private func changeWidth() { preferences.update(width: widthChoice.selectedSegment == 1 ? .full : .centered) }
    @objc private func restoreDefaults() { preferences.restoreDefaults() }
    @objc private func preferencesChanged() { refreshControls() }

    private func refreshControls() {
        fontChoice.selectItem(at: ReadingPreferences.Font.allCases.firstIndex(of: preferences.font) ?? 0)
        sizeSlider.doubleValue = preferences.textSize
        sizeLabel.stringValue = String(Int(preferences.textSize))
        smaller.isEnabled = preferences.textSize > ReadingPreferences.sizeRange.lowerBound
        larger.isEnabled = preferences.textSize < ReadingPreferences.sizeRange.upperBound
        widthChoice.selectedSegment = preferences.width == .full ? 1 : 0
    }
}
