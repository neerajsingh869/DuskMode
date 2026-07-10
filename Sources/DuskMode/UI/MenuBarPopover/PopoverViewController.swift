import AppKit
import DuskModeCore

/// The menu-bar popover: an Off / Manual / Auto mode selector, bedtime + live status
/// (Auto), warmth + dim sliders, a grayscale toggle, Emergency Color, and Reset.
/// Built programmatically (no .xib) so the whole app stays plain-text and buildable
/// without Xcode's Interface Builder.
///
/// Mode model (one control, three states — replaces the old master + schedule switches):
///  • Off    — screen untouched.
///  • Manual — the warmth/dim sliders drive; grayscale is an independent toggle.
///  • Auto   — the circadian timeline drives warmth/dim/grayscale; sliders show live
///             values. Dragging a slider in Auto forks to Manual keeping the current
///             look (grayscale included); clicking Manual/Off instead turns Auto's
///             grayscale off (see AppDelegate — REGRESSIONS #16).
final class PopoverViewController: NSViewController {

    private let overlayEngine: OverlayEngine
    private let circadianEngine: CircadianEngine
    private weak var emergencyController: ScreenStateControlling?
    private let prefs = PreferencesStore.shared

    /// Ticks once a second only while the popover is open AND Emergency Color is
    /// running, to keep the button's countdown fresh. Torn down on disappear.
    private var emergencyCountdownTimer: Timer?

    private static let contentWidth: CGFloat = 300
    private static let insets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)

    private let modeControl = NSSegmentedControl(labels: ["Off", "Manual", "Auto"],
                                                 trackingMode: .selectOne,
                                                 target: nil, action: nil)
    private let bedtimePicker = NSDatePicker()
    private let scheduleStatus = NSTextField(wrappingLabelWithString: "")
    private let warmthSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let dimSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let grayscaleSwitch = NSSwitch()
    private let emergencyButton = NSButton(title: "", target: nil, action: nil)

    private let bedtimeTitle = NSTextField(labelWithString: "Bedtime")
    private let grayscaleTitle = NSTextField(labelWithString: "Grayscale")
    private let warmthTitle = NSTextField(labelWithString: "Warmth")
    private let warmthValue = NSTextField(labelWithString: "")
    private let dimTitle = NSTextField(labelWithString: "Dimming")
    private let dimValue = NSTextField(labelWithString: "")

    init(overlayEngine: OverlayEngine,
         circadianEngine: CircadianEngine,
         emergencyController: ScreenStateControlling) {
        self.overlayEngine = overlayEngine
        self.circadianEngine = circadianEngine
        self.emergencyController = emergencyController
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(emergencyStateChanged),
            name: AppDelegate.emergencyColorChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func loadView() {
        let root = NSView()

        // Header: app name (left) + a subtle "Reset" text link (right), tagline beneath.
        let title = NSTextField(labelWithString: "DuskMode")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let resetButton = NSButton(title: "Reset", target: self, action: #selector(resetTapped))
        resetButton.isBordered = false
        resetButton.bezelStyle = .inline
        resetButton.font = .systemFont(ofSize: 11)
        resetButton.contentTintColor = .secondaryLabelColor
        resetButton.setContentHuggingPriority(.required, for: .horizontal)
        resetButton.toolTip =
            "Restore the original settings: 3500 K, no dimming, grayscale off, bedtime 23:00. The Off/Manual/Auto mode is left alone."
        let headerRow = row(leading: title, trailing: resetButton)

        let subtitle = NSTextField(labelWithString: "Science-based evening wind-down")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        // Mode selector: Off / Manual / Auto — the single top-level state.
        modeControl.segmentDistribution = .fillEqually
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.toolTip = "Off = screen untouched · Manual = you set warmth/dim · Auto = follows the wind-down schedule"

        // Bedtime (Auto only): the timeline deepens toward this time.
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
        grayscaleTitle.font = .systemFont(ofSize: 13)
        grayscaleSwitch.target = self
        grayscaleSwitch.action = #selector(grayscaleChanged)
        let grayscaleRow = row(leading: grayscaleTitle, trailing: grayscaleSwitch)

        let grayscaleCaption = NSTextField(wrappingLabelWithString:
            "Drains colour so scrolling feels less gripping.")
        grayscaleCaption.font = .systemFont(ofSize: 11)
        grayscaleCaption.textColor = .secondaryLabelColor
        grayscaleCaption.preferredMaxLayoutWidth = Self.contentWidth
        grayscaleCaption.isSelectable = false
        grayscaleSwitch.toolTip =
            "A separate anti-doomscroll tool — available in any mode. Auto turns it on near bedtime. macOS briefly shows its Colour Filters confirmation on toggle."

        // Emergency Color: a momentary "real colours NOW" override. Suspends every
        // filter for 60s, then the wind-down (manual or schedule) resumes on its own.
        emergencyButton.bezelStyle = .rounded
        emergencyButton.controlSize = .regular
        emergencyButton.target = self
        emergencyButton.action = #selector(emergencyTapped)
        emergencyButton.toolTip = "Restore true colour for 60 seconds — for when you need accurate colours — then your wind-down resumes automatically. Shortcut: ⌥⌘C."
        let emergencyCaption = NSTextField(wrappingLabelWithString:
            "True colour for 60 s, then resumes. ⌥⌘C")
        emergencyCaption.font = .systemFont(ofSize: 11)
        emergencyCaption.textColor = .secondaryLabelColor
        emergencyCaption.preferredMaxLayoutWidth = Self.contentWidth
        emergencyCaption.isSelectable = false

        let separator1 = separator()
        let separator2 = separator()
        let separator3 = separator()
        let separator4 = separator()
        let warmthRow = row(leading: warmthTitle, trailing: warmthValue)
        let dimRow = row(leading: dimTitle, trailing: dimValue)

        let stack = NSStackView(views: [
            headerRow,
            subtitle,
            separator1,
            modeControl,
            bedtimeRow,
            scheduleStatus,
            separator2,
            warmthRow,
            warmthSlider,
            dimRow,
            dimSlider,
            separator3,
            grayscaleRow,
            grayscaleCaption,
            separator4,
            emergencyButton,
            emergencyCaption
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
        stack.setCustomSpacing(10, after: modeControl)
        stack.setCustomSpacing(6, after: bedtimeRow)
        stack.setCustomSpacing(12, after: scheduleStatus)
        stack.setCustomSpacing(12, after: separator2)
        stack.setCustomSpacing(4, after: warmthRow)
        stack.setCustomSpacing(14, after: warmthSlider)
        stack.setCustomSpacing(4, after: dimRow)
        stack.setCustomSpacing(12, after: dimSlider)
        stack.setCustomSpacing(12, after: separator3)
        stack.setCustomSpacing(6, after: grayscaleRow)
        stack.setCustomSpacing(12, after: grayscaleCaption)
        stack.setCustomSpacing(10, after: separator4)
        stack.setCustomSpacing(6, after: emergencyButton)

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(
                equalToConstant: Self.contentWidth + Self.insets.left + Self.insets.right)
        ])
        for wide in [modeControl, warmthSlider, dimSlider, emergencyButton] as [NSView] {
            wide.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        }
        for caption in [scheduleStatus, grayscaleCaption, emergencyCaption] {
            caption.widthAnchor.constraint(
                lessThanOrEqualToConstant: Self.contentWidth).isActive = true
        }

        self.view = root
        preferredContentSize = root.fittingSize
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        syncFromState()
        startEmergencyCountdownIfNeeded()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        emergencyCountdownTimer?.invalidate()
        emergencyCountdownTimer = nil
    }

    // MARK: - Sync

    /// True when the screen is currently filtered — in Manual, or an active Auto phase.
    private var filtersActive: Bool {
        switch prefs.mode {
        case .auto:   return circadianEngine.currentTarget.active
        case .manual: return true
        case .off:    return false
        }
    }

    private func syncFromState() {
        let target = circadianEngine.currentTarget
        let mode = prefs.mode

        modeControl.selectedSegment = Self.segment(for: mode)
        bedtimePicker.dateValue = Self.date(fromMinutes: prefs.bedtimeMinutes)
        // In Auto, the sliders display the schedule's live values; otherwise the manual prefs.
        let showLive = (mode == .auto && target.active)
        warmthSlider.doubleValue = showLive ? target.warmth : prefs.warmth
        dimSlider.doubleValue = showLive ? target.dim : prefs.dim
        // Reflect grayscale INTENT, not the momentary system state. `prefs.grayscaleOn`
        // is the intent (every setGrayscale writes it) and, unlike the live UA getter,
        // never lags right after a set — so the switch can't show ON while the screen is
        // colour. During an emergency the system grayscale is suppressed but the setting
        // is intact, so OR the switch back ON.
        let grayscaleOn = prefs.grayscaleOn
            || (emergencyController?.grayscaleSuspendedForEmergency ?? false)
        grayscaleSwitch.state = grayscaleOn ? .on : .off
        updateValueLabels()
        updateEnabledStates()
        updateScheduleStatus()
        updateEmergencyButton()
        // Bedtime + status are only meaningful in Auto — collapse them otherwise.
        bedtimePicker.superview?.isHidden = (mode != .auto)
        scheduleStatus.isHidden = (mode != .auto)
        // Re-fit AFTER the hide takes effect so the popover hugs its content (no dead
        // space) — fittingSize is stale until the layout pass runs.
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    /// Reflects Emergency Color state: idle = "Emergency Color", active = a live
    /// countdown that doubles as a cancel button.
    private func updateEmergencyButton() {
        guard let controller = emergencyController else { return }
        if controller.isEmergencyColorActive, let end = controller.emergencyColorEndDate {
            let remaining = max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
            emergencyButton.title = "Full Color · \(remaining)s  (tap to end)"
            emergencyButton.isEnabled = true
        } else {
            emergencyButton.title = "Emergency Color"
            // Only offer it when something is actually being filtered.
            emergencyButton.isEnabled = controller.isEmergencyColorAvailable
        }
    }

    // MARK: - Emergency Color

    @objc private func emergencyTapped() {
        emergencyController?.toggleEmergencyColor()
        // State flips synchronously; refresh immediately (the notification also fires).
        updateEmergencyButton()
        startEmergencyCountdownIfNeeded()
    }

    @objc private func emergencyStateChanged() {
        // Full resync so the grayscale switch reflects its restored position when an
        // emergency ends, and the button's enabled state stays correct.
        syncFromState()
        startEmergencyCountdownIfNeeded()
    }

    private func startEmergencyCountdownIfNeeded() {
        emergencyCountdownTimer?.invalidate()
        emergencyCountdownTimer = nil
        guard emergencyController?.isEmergencyColorActive == true else { return }
        let t = Timer(timeInterval: 1, target: self,
                      selector: #selector(emergencyCountdownTick),
                      userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        emergencyCountdownTimer = t
    }

    @objc private func emergencyCountdownTick() {
        updateEmergencyButton()
        if emergencyController?.isEmergencyColorActive != true {
            emergencyCountdownTimer?.invalidate()
            emergencyCountdownTimer = nil
        }
    }

    private func updateValueLabels() {
        let kelvin = ColorTemperature.kelvin(forWarmth: warmthSlider.doubleValue)
        warmthValue.stringValue = "\(Int((kelvin / 100).rounded()) * 100) K"
        dimValue.stringValue = "\(Int((dimSlider.doubleValue * 100).rounded()))%"
    }

    private func updateEnabledStates() {
        let mode = prefs.mode
        // Warmth/dim belong to the colour wind-down, so they're inert in Off.
        let filtersOn = (mode != .off)
        for control in [warmthSlider, dimSlider] { control.isEnabled = filtersOn }
        for label in [warmthTitle, warmthValue, dimTitle, dimValue] {
            label.alphaValue = filtersOn ? 1.0 : 0.4
        }
        // Grayscale is a separate behavioral tool — always available, even in Off.
        grayscaleSwitch.isEnabled = true
        grayscaleTitle.alphaValue = 1.0
        bedtimePicker.isEnabled = (mode == .auto)
        bedtimeTitle.alphaValue = (mode == .auto) ? 1.0 : 0.4
    }

    private func updateScheduleStatus() {
        guard prefs.mode == .auto else { return }
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

    @objc private func modeChanged() {
        let newMode = Self.mode(forSegment: modeControl.selectedSegment)
        // Leaving Auto for Manual explicitly: carry the current warmth/dim so there's no
        // visual jump. Grayscale is NOT retained here — an explicit leave-Auto turns it
        // off (AppDelegate releases the schedule-owned grayscale). A slider drag is the
        // path that keeps grayscale (see forkToManualIfAuto).
        if newMode == .manual, prefs.mode == .auto {
            adoptCurrentScheduleValues()
        }
        prefs.mode = newMode
        syncFromState()
    }

    @objc private func bedtimeChanged() {
        prefs.bedtimeMinutes = Self.minutes(fromDate: bedtimePicker.dateValue)
        syncFromState()
    }

    @objc private func warmthChanged() {
        forkToManualIfAuto()
        prefs.warmth = warmthSlider.doubleValue
        updateValueLabels()
    }

    @objc private func dimChanged() {
        forkToManualIfAuto()
        prefs.dim = dimSlider.doubleValue
        updateValueLabels()
    }

    @objc private func grayscaleChanged() {
        // Route through the controller so this is marked a MANUAL, independent peer —
        // it won't be swept when leaving Auto (REGRESSIONS #15/#16). Deliberately does
        // NOT change the mode: a manual grayscale flip is a momentary choice, and Auto
        // only re-asserts grayscale at the next phase boundary (edge-triggered).
        emergencyController?.setManualGrayscale(grayscaleSwitch.state == .on)
        // Grayscale alone makes Emergency Color meaningful, so refresh its enabled state.
        updateEmergencyButton()
    }

    @objc private func resetTapped() {
        // Turn system grayscale off (edge-guarded inside setManualGrayscale — no bezel
        // when it was already off) and mark it manual, then restore the pref knobs and
        // refresh the whole UI. The mode is left as-is.
        emergencyController?.setManualGrayscale(false)
        prefs.resetToDefaults()
        syncFromState()
    }

    /// Dragging a slider while in Auto = fork to Manual, keeping the screen exactly
    /// as-is (adopt the schedule's current values first) AND keeping grayscale (transfer
    /// its ownership to manual so leaving Auto doesn't release it).
    private func forkToManualIfAuto() {
        guard prefs.mode == .auto else { return }
        adoptCurrentScheduleValues()
        emergencyController?.retainGrayscaleAsManual()
        prefs.mode = .manual
        modeControl.selectedSegment = Self.segment(for: .manual)
        updateEnabledStates()
        bedtimePicker.superview?.isHidden = true
        scheduleStatus.isHidden = true
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    private func adoptCurrentScheduleValues() {
        let target = circadianEngine.currentTarget
        guard target.active else { return }
        prefs.warmth = target.warmth
        prefs.dim = target.dim
    }

    // MARK: - Mode ↔ segment mapping

    private static func mode(forSegment index: Int) -> PreferencesStore.Mode {
        switch index {
        case 0:  return .off
        case 1:  return .manual
        default: return .auto
        }
    }

    private static func segment(for mode: PreferencesStore.Mode) -> Int {
        switch mode {
        case .off:    return 0
        case .manual: return 1
        case .auto:   return 2
        }
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
