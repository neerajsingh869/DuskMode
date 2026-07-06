import AppKit
import DuskModeCore

/// The menu-bar popover: automatic schedule (switch + bedtime + status), master
/// switch, warmth + dim sliders, grayscale toggle.
/// Built programmatically (no .xib) so the whole app stays plain-text and buildable
/// without Xcode's Interface Builder.
///
/// Layout follows macOS control-panel conventions (Wi-Fi/Bluetooth menu extras):
/// one title row with the master switch, labelled sliders with live value readouts
/// (Kelvin, like f.lux, so the numbers are meaningful), switches instead of buttons
/// for on/off state, and controls that visibly disable when nothing is active.
///
/// Mode model: when "Automatic schedule" is ON, the circadian timeline owns the
/// screen — the master switch and sliders display what the schedule is currently
/// doing, and touching any of them adopts those values into manual mode and turns
/// the schedule off (a seamless handoff, no visual jump).
final class PopoverViewController: NSViewController {

    private let overlayEngine: OverlayEngine
    private let grayscaleEngine: GrayscaleEngine
    private let circadianEngine: CircadianEngine
    private let prefs = PreferencesStore.shared

    private static let contentWidth: CGFloat = 300
    private static let insets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)

    private let masterSwitch = NSSwitch()
    private let scheduleSwitch = NSSwitch()
    private let bedtimePicker = NSDatePicker()
    private let scheduleStatus = NSTextField(wrappingLabelWithString: "")
    private let warmthSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let dimSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let grayscaleSwitch = NSSwitch()

    private let bedtimeTitle = NSTextField(labelWithString: "Bedtime")
    private let warmthTitle = NSTextField(labelWithString: "Warmth")
    private let warmthValue = NSTextField(labelWithString: "")
    private let dimTitle = NSTextField(labelWithString: "Dimming")
    private let dimValue = NSTextField(labelWithString: "")

    init(overlayEngine: OverlayEngine,
         grayscaleEngine: GrayscaleEngine,
         circadianEngine: CircadianEngine) {
        self.overlayEngine = overlayEngine
        self.grayscaleEngine = grayscaleEngine
        self.circadianEngine = circadianEngine
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

        // Automatic schedule: switch row, bedtime picker row, live status caption.
        let scheduleTitle = NSTextField(labelWithString: "Automatic schedule")
        scheduleTitle.font = .systemFont(ofSize: 13)
        scheduleSwitch.target = self
        scheduleSwitch.action = #selector(scheduleChanged)
        let scheduleRow = row(leading: scheduleTitle, trailing: scheduleSwitch)

        bedtimeTitle.font = .systemFont(ofSize: 13)
        bedtimePicker.datePickerStyle = .textFieldAndStepper
        bedtimePicker.datePickerElements = .hourMinute
        bedtimePicker.datePickerMode = .single
        bedtimePicker.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        bedtimePicker.target = self
        bedtimePicker.action = #selector(bedtimeChanged)
        bedtimePicker.toolTip = "Wind-down deepens toward this time; grayscale starts 2 h before"
        let bedtimeRow = row(leading: bedtimeTitle, trailing: bedtimePicker)

        scheduleStatus.font = .systemFont(ofSize: 11)
        scheduleStatus.textColor = .secondaryLabelColor
        scheduleStatus.preferredMaxLayoutWidth = Self.contentWidth
        scheduleStatus.isSelectable = false

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
            "Turns the whole screen black-and-white to make endless scrolling less gripping. macOS briefly shows its Colour Filters confirmation.")
        grayscaleCaption.font = .systemFont(ofSize: 11)
        grayscaleCaption.textColor = .secondaryLabelColor
        grayscaleCaption.preferredMaxLayoutWidth = Self.contentWidth
        grayscaleCaption.isSelectable = false

        let separator1 = separator()
        let separator2 = separator()
        let separator3 = separator()
        let warmthRow = row(leading: warmthTitle, trailing: warmthValue)
        let dimRow = row(leading: dimTitle, trailing: dimValue)

        let stack = NSStackView(views: [
            headerRow,
            subtitle,
            separator1,
            scheduleRow,
            bedtimeRow,
            scheduleStatus,
            separator2,
            warmthRow,
            warmthSlider,
            dimRow,
            dimSlider,
            separator3,
            grayscaleRow,
            grayscaleCaption
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = Self.insets
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Breathing room around the sections; tight pairing of label ↔ control.
        stack.setCustomSpacing(2, after: headerRow)
        stack.setCustomSpacing(12, after: subtitle)
        stack.setCustomSpacing(12, after: separator1)
        stack.setCustomSpacing(8, after: scheduleRow)
        stack.setCustomSpacing(6, after: bedtimeRow)
        stack.setCustomSpacing(12, after: scheduleStatus)
        stack.setCustomSpacing(12, after: separator2)
        stack.setCustomSpacing(4, after: warmthRow)
        stack.setCustomSpacing(14, after: warmthSlider)
        stack.setCustomSpacing(4, after: dimRow)
        stack.setCustomSpacing(12, after: dimSlider)
        stack.setCustomSpacing(12, after: separator3)
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
        for caption in [scheduleStatus, grayscaleCaption] {
            caption.widthAnchor.constraint(
                lessThanOrEqualToConstant: Self.contentWidth).isActive = true
        }

        self.view = root
        preferredContentSize = root.fittingSize
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        syncFromState()
        // The status caption's length varies (phase names, times) — re-fit so the
        // popover never clips it.
        preferredContentSize = view.fittingSize
    }

    // MARK: - Sync

    /// True when the screen is currently filtered — by schedule or by hand.
    private var filtersActive: Bool {
        prefs.scheduleEnabled ? circadianEngine.currentTarget.active : prefs.masterEnabled
    }

    private func syncFromState() {
        let target = circadianEngine.currentTarget
        let scheduleOn = prefs.scheduleEnabled

        scheduleSwitch.state = scheduleOn ? .on : .off
        bedtimePicker.dateValue = Self.date(fromMinutes: prefs.bedtimeMinutes)
        masterSwitch.state = filtersActive ? .on : .off
        warmthSlider.doubleValue = (scheduleOn && target.active) ? target.warmth : prefs.warmth
        dimSlider.doubleValue = (scheduleOn && target.active) ? target.dim : prefs.dim
        grayscaleSwitch.state = grayscaleEngine.isGrayscaleEnabled() ? .on : .off
        updateValueLabels()
        updateEnabledStates()
        updateScheduleStatus()
    }

    private func updateValueLabels() {
        let kelvin = ColorTemperature.kelvin(forWarmth: warmthSlider.doubleValue)
        warmthValue.stringValue = "\(Int((kelvin / 100).rounded()) * 100) K"
        dimValue.stringValue = "\(Int((dimSlider.doubleValue * 100).rounded()))%"
    }

    private func updateEnabledStates() {
        let on = filtersActive
        for control in [warmthSlider, dimSlider] { control.isEnabled = on }
        for label in [warmthTitle, warmthValue, dimTitle, dimValue] {
            label.alphaValue = on ? 1.0 : 0.4
        }
        bedtimePicker.isEnabled = prefs.scheduleEnabled
        bedtimeTitle.alphaValue = prefs.scheduleEnabled ? 1.0 : 0.4
    }

    private func updateScheduleStatus() {
        guard prefs.scheduleEnabled else {
            scheduleStatus.stringValue =
                "Runs the whole wind-down for you: warm at sunset, grayscale and deep red as bedtime nears, off at sunrise."
            return
        }
        let target = circadianEngine.currentTarget
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        var text: String
        if !target.active {
            if let time = target.nextEventTime {
                text = "Daytime — starts at sunset, \(formatter.string(from: time))."
            } else {
                text = "Daytime — screen untouched."
            }
        } else if let nextName = target.nextEventName, let nextTime = target.nextEventTime {
            text = "\(target.phaseName) phase · \(nextName) at \(formatter.string(from: nextTime))."
        } else {
            text = "\(target.phaseName) phase."
        }
        if circadianEngine.usesApproximateLocation {
            text += " Using timezone-estimated location — allow Location access for exact sunset."
        }
        scheduleStatus.stringValue = text
    }

    // MARK: - Actions

    @objc private func scheduleChanged() {
        prefs.scheduleEnabled = (scheduleSwitch.state == .on)
        syncFromState()
    }

    @objc private func bedtimeChanged() {
        prefs.bedtimeMinutes = Self.minutes(fromDate: bedtimePicker.dateValue)
        syncFromState()
    }

    @objc private func masterChanged() {
        let wantOn = (masterSwitch.state == .on)
        // Order matters for a flicker-free handoff: park the manual master state
        // first (a no-op while the schedule still owns the screen), then release
        // the schedule so the manual path applies exactly that state.
        prefs.masterEnabled = wantOn
        if prefs.scheduleEnabled {
            if wantOn {
                // Master flipped on during daytime: keep the current manual sliders.
                adoptScheduleValuesIfActive()
            }
            prefs.scheduleEnabled = false
        }
        syncFromState()
    }

    @objc private func warmthChanged() {
        handOffToManualIfScheduled()
        prefs.warmth = warmthSlider.doubleValue
        updateValueLabels()
    }

    @objc private func dimChanged() {
        handOffToManualIfScheduled()
        prefs.dim = dimSlider.doubleValue
        updateValueLabels()
    }

    @objc private func grayscaleChanged() {
        // Deliberately does NOT turn the schedule off: a manual grayscale flip is a
        // momentary choice, and the schedule only re-asserts grayscale at the next
        // phase boundary (edge-triggered in AppDelegate).
        grayscaleEngine.setGrayscale(grayscaleSwitch.state == .on)
    }

    /// Dragging a slider while the schedule runs = switch to manual, keeping the
    /// screen exactly as-is (adopt the schedule's current values first).
    private func handOffToManualIfScheduled() {
        guard prefs.scheduleEnabled else { return }
        adoptScheduleValuesIfActive()
        prefs.masterEnabled = true
        prefs.scheduleEnabled = false
        scheduleSwitch.state = .off
        updateEnabledStates()
        updateScheduleStatus()
    }

    private func adoptScheduleValuesIfActive() {
        let target = circadianEngine.currentTarget
        guard target.active else { return }
        prefs.warmth = target.warmth
        prefs.dim = target.dim
    }

    // MARK: - Bedtime ↔ Date conversion

    private static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes) * 60)
    }

    private static func minutes(fromDate date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 23) * 60 + (components.minute ?? 0)
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
