import AppKit

/// The menu-bar popover: master switch, warmth + dim sliders, grayscale toggle.
/// Built programmatically (no .xib) so the whole app stays plain-text and buildable
/// without Xcode's Interface Builder.
///
/// Layout follows macOS control-panel conventions (Wi-Fi/Bluetooth menu extras):
/// one title row with the master switch, labelled sliders with live value readouts
/// (Kelvin, like f.lux, so the numbers are meaningful), switches instead of buttons
/// for on/off state, and controls that visibly disable when the master is off.
final class PopoverViewController: NSViewController {

    private let overlayEngine: OverlayEngine
    private let grayscaleEngine: GrayscaleEngine
    private let prefs = PreferencesStore.shared

    private static let contentWidth: CGFloat = 300
    private static let insets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)

    private let masterSwitch = NSSwitch()
    private let warmthSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let dimSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let grayscaleSwitch = NSSwitch()

    private let warmthTitle = NSTextField(labelWithString: "Warmth")
    private let warmthValue = NSTextField(labelWithString: "")
    private let dimTitle = NSTextField(labelWithString: "Dimming")
    private let dimValue = NSTextField(labelWithString: "")

    init(overlayEngine: OverlayEngine, grayscaleEngine: GrayscaleEngine) {
        self.overlayEngine = overlayEngine
        self.grayscaleEngine = grayscaleEngine
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func loadView() {
        let root = NSView()

        // Header: app name + master switch on one row, tagline beneath.
        let title = NSTextField(labelWithString: "DuskMode")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        masterSwitch.target = self
        masterSwitch.action = #selector(masterChanged)
        let headerRow = row(leading: title, trailing: masterSwitch)

        let subtitle = NSTextField(labelWithString: "Science-based evening wind-down")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        // Warmth: label + live Kelvin readout, slider beneath.
        styleSliderTitle(warmthTitle)
        styleValueLabel(warmthValue)
        warmthSlider.target = self
        warmthSlider.action = #selector(warmthChanged)
        warmthSlider.isContinuous = true
        warmthSlider.toolTip = "Colour temperature: 6500 K (neutral) to 1900 K (candlelight)"

        // Dimming: label + live percentage, slider beneath.
        styleSliderTitle(dimTitle)
        styleValueLabel(dimValue)
        dimSlider.target = self
        dimSlider.action = #selector(dimChanged)
        dimSlider.isContinuous = true
        dimSlider.toolTip = "Darkens the screen below the hardware brightness minimum"

        // Grayscale: switch row + explanatory caption.
        let grayscaleTitle = NSTextField(labelWithString: "Grayscale")
        grayscaleTitle.font = .systemFont(ofSize: 13)
        grayscaleSwitch.target = self
        grayscaleSwitch.action = #selector(grayscaleChanged)
        let grayscaleRow = row(leading: grayscaleTitle, trailing: grayscaleSwitch)

        let grayscaleCaption = NSTextField(wrappingLabelWithString:
            "Turns the whole screen black-and-white to make endless scrolling less gripping.")
        grayscaleCaption.font = .systemFont(ofSize: 11)
        grayscaleCaption.textColor = .secondaryLabelColor
        grayscaleCaption.preferredMaxLayoutWidth = Self.contentWidth
        grayscaleCaption.isSelectable = false

        let topSeparator = separator()
        let bottomSeparator = separator()
        let warmthRow = row(leading: warmthTitle, trailing: warmthValue)
        let dimRow = row(leading: dimTitle, trailing: dimValue)

        let stack = NSStackView(views: [
            headerRow,
            subtitle,
            topSeparator,
            warmthRow,
            warmthSlider,
            dimRow,
            dimSlider,
            bottomSeparator,
            grayscaleRow,
            grayscaleCaption
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = Self.insets
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Breathing room around the sections; tight pairing of label ↔ slider.
        stack.setCustomSpacing(2, after: headerRow)
        stack.setCustomSpacing(12, after: subtitle)
        stack.setCustomSpacing(12, after: topSeparator)
        stack.setCustomSpacing(4, after: warmthRow)
        stack.setCustomSpacing(14, after: warmthSlider)
        stack.setCustomSpacing(4, after: dimRow)
        stack.setCustomSpacing(12, after: dimSlider)
        stack.setCustomSpacing(12, after: bottomSeparator)
        stack.setCustomSpacing(6, after: grayscaleRow)

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(
                equalToConstant: Self.contentWidth + Self.insets.left + Self.insets.right)
        ])
        for wide in [warmthSlider, dimSlider] as [NSView] {
            wide.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        }
        grayscaleCaption.widthAnchor.constraint(
            lessThanOrEqualToConstant: Self.contentWidth).isActive = true

        self.view = root
        preferredContentSize = root.fittingSize
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
        grayscaleSwitch.state = grayscaleEngine.isGrayscaleEnabled() ? .on : .off
        updateValueLabels()
        updateEnabledStates()
    }

    private func updateValueLabels() {
        let kelvin = ColorTemperature.kelvin(forWarmth: warmthSlider.doubleValue)
        warmthValue.stringValue = "\(Int((kelvin / 100).rounded()) * 100) K"
        dimValue.stringValue = "\(Int((dimSlider.doubleValue * 100).rounded()))%"
    }

    private func updateEnabledStates() {
        let on = prefs.masterEnabled
        for control in [warmthSlider, dimSlider] { control.isEnabled = on }
        for label in [warmthTitle, warmthValue, dimTitle, dimValue] {
            label.alphaValue = on ? 1.0 : 0.4
        }
    }

    // MARK: - Actions

    @objc private func masterChanged() {
        prefs.masterEnabled = (masterSwitch.state == .on)
        updateEnabledStates()
    }

    @objc private func warmthChanged() {
        prefs.warmth = warmthSlider.doubleValue
        updateValueLabels()
    }

    @objc private func dimChanged() {
        prefs.dim = dimSlider.doubleValue
        updateValueLabels()
    }

    @objc private func grayscaleChanged() {
        grayscaleEngine.setGrayscale(grayscaleSwitch.state == .on)
    }

    // MARK: - Helpers

    private func row(leading: NSView, trailing: NSView) -> NSStackView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [leading, spacer, trailing])
        row.orientation = .horizontal
        row.distribution = .fill
        row.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        return row
    }

    private func styleSliderTitle(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 13)
    }

    private func styleValueLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        return line
    }
}
