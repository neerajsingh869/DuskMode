import AppKit

/// The menu-bar popover: master switch, warmth + dim sliders, grayscale toggle.
/// Built programmatically (no .xib) so the whole app stays plain-text and buildable
/// without Xcode's Interface Builder.
final class PopoverViewController: NSViewController {

    private let overlayEngine: OverlayEngine
    private let grayscaleEngine: GrayscaleEngine
    private let prefs = PreferencesStore.shared

    private let masterSwitch = NSSwitch()
    private let warmthSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let dimSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let grayscaleButton = NSButton(title: "", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    init(overlayEngine: OverlayEngine, grayscaleEngine: GrayscaleEngine) {
        self.overlayEngine = overlayEngine
        self.grayscaleEngine = grayscaleEngine
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))

        let title = NSTextField(labelWithString: "NightFlow")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Scientifically-backed wind-down")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        // Master row
        let masterLabel = NSTextField(labelWithString: "Night mode")
        masterSwitch.target = self
        masterSwitch.action = #selector(masterChanged)
        let masterRow = NSStackView(views: [masterLabel, NSView(), masterSwitch])
        masterRow.orientation = .horizontal
        masterRow.distribution = .fill

        // Warmth
        let warmthLabel = NSTextField(labelWithString: "Warmth  (amber → red)")
        warmthLabel.font = .systemFont(ofSize: 11)
        warmthLabel.textColor = .secondaryLabelColor
        warmthSlider.target = self
        warmthSlider.action = #selector(warmthChanged)
        warmthSlider.isContinuous = true

        // Dim
        let dimLabel = NSTextField(labelWithString: "Dim  (below hardware minimum)")
        dimLabel.font = .systemFont(ofSize: 11)
        dimLabel.textColor = .secondaryLabelColor
        dimSlider.target = self
        dimSlider.action = #selector(dimChanged)
        dimSlider.isContinuous = true

        // Grayscale
        grayscaleButton.bezelStyle = .rounded
        grayscaleButton.target = self
        grayscaleButton.action = #selector(grayscaleTapped)

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [
            title, subtitle,
            separator(),
            masterRow,
            warmthLabel, warmthSlider,
            dimLabel, dimSlider,
            separator(),
            grayscaleButton,
            statusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        // Make the sliders span the popover width.
        warmthSlider.widthAnchor.constraint(equalToConstant: 268).isActive = true
        dimSlider.widthAnchor.constraint(equalToConstant: 268).isActive = true
        grayscaleButton.widthAnchor.constraint(equalToConstant: 268).isActive = true

        self.view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        syncFromPrefs()
    }

    // MARK: - Sync

    private func syncFromPrefs() {
        masterSwitch.state = prefs.masterEnabled ? .on : .off
        warmthSlider.doubleValue = prefs.warmth
        dimSlider.doubleValue = prefs.dim
        updateGrayscaleButton()
    }

    private func updateGrayscaleButton() {
        grayscaleButton.title = prefs.grayscaleOn ? "Grayscale: On" : "Toggle Grayscale"
        if grayscaleEngine.hasAccessibilityPermission {
            statusLabel.stringValue = "Grayscale uses macOS Color Filters (⌥⌘F5). Set it to Grayscale in System Settings if it doesn't change."
        } else {
            statusLabel.stringValue = "Grant Accessibility permission so NightFlow can toggle grayscale."
        }
    }

    // MARK: - Actions

    @objc private func masterChanged() {
        prefs.masterEnabled = (masterSwitch.state == .on)
    }

    @objc private func warmthChanged() {
        prefs.warmth = warmthSlider.doubleValue
    }

    @objc private func dimChanged() {
        prefs.dim = dimSlider.doubleValue
    }

    @objc private func grayscaleTapped() {
        if grayscaleEngine.toggle() {
            updateGrayscaleButton()
        } else {
            // No permission yet: prompt, and open the relevant settings pane.
            grayscaleEngine.requestAccessibilityPermission()
            grayscaleEngine.openColorFilterSettings()
            updateGrayscaleButton()
        }
    }

    // MARK: - Helpers

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 268).isActive = true
        return line
    }
}
