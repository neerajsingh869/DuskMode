import AppKit
import DuskModeCore

/// The Settings window, opened from the status item's right-click menu (left-click
/// keeps opening the quick popover — nightly controls stay separate from set-once
/// settings). Three tabs: General (app info + read-only launch-at-login status),
/// Timeline (read-only chart of tonight's wind-down), Science (citations.json).
final class SettingsWindowController: NSWindowController {

    private let circadianEngine: CircadianEngine
    private let launchAtLogin: LaunchAtLoginControlling

    private let tabControl = NSSegmentedControl(labels: ["General", "Timeline", "Science"],
                                                trackingMode: .selectOne, target: nil, action: nil)
    private let contentContainer = NSView()

    private lazy var timelineView = TimelineTabView()
    private lazy var scienceView = ScienceTabView()

    init(circadianEngine: CircadianEngine, launchAtLogin: LaunchAtLoginControlling) {
        self.circadianEngine = circadianEngine
        self.launchAtLogin = launchAtLogin
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "DuskMode Settings"
        window.minSize = NSSize(width: 440, height: 400)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func buildContent() {
        tabControl.segmentDistribution = .fillEqually
        tabControl.target = self
        tabControl.action = #selector(tabChanged)
        tabControl.selectedSegment = 0

        let root = NSView()
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tabControl)
        root.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            tabControl.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            tabControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            tabControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            contentContainer.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 18),
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])

        window?.contentView = root
        showTab(0)
    }

    @objc private func tabChanged() { showTab(tabControl.selectedSegment) }

    // Science's content is long-form (multiple topics + citations) and is meant to
    // scroll, so it keeps one fixed, comfortable height. General and Timeline are both
    // short, self-contained panels — sizing the window to their real content (instead of
    // reusing one fixed height for every tab) is what keeps them from either leaving a
    // mismatched slab of dead space or crowding against the window edge.
    private let scienceTabHeight: CGFloat = 420

    private func showTab(_ index: Int) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let view: NSView
        let fixedHeight: CGFloat?
        switch index {
        case 0:
            // Rebuilt fresh each time, not cached — the launch-at-login status can
            // change from outside the app (System Settings → Login Items).
            view = GeneralTabView(isLaunchAtLoginEnabled: launchAtLogin.isLaunchAtLoginEnabled)
            fixedHeight = nil
        case 1:
            timelineView.refresh(with: circadianEngine.currentTimeline)
            view = timelineView
            fixedHeight = nil
        default:
            view = scienceView
            fixedHeight = scienceTabHeight
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor)
        ])

        let height: CGFloat
        if let fixedHeight {
            height = fixedHeight
        } else {
            // Force a layout pass with the view's width already pinned (leading/trailing
            // above) so wrapping labels/text views report their real, width-dependent
            // height, then lock that height in — the same "layoutSubtreeIfNeeded before
            // reading fittingSize" trick used for the popover's own auto-sizing.
            contentContainer.layoutSubtreeIfNeeded()
            height = max(view.fittingSize.height, 1)
        }
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        resizeWindow(toFitTabContentHeight: height)
    }

    /// Resizes the window's height to exactly fit `tabHeight` of tab content plus the
    /// fixed chrome around it (tab control + margins), keeping the top-left corner
    /// stationary so the window doesn't jump around the screen when switching tabs.
    private func resizeWindow(toFitTabContentHeight tabHeight: CGFloat) {
        guard let window else { return }
        let topChrome: CGFloat = 18 + tabControl.fittingSize.height + 18
        let bottomMargin: CGFloat = 20
        let contentWidth = window.contentLayoutRect.width
        let desiredContentRect = NSRect(x: 0, y: 0, width: contentWidth,
                                        height: topChrome + tabHeight + bottomMargin)
        let desiredFrame = window.frameRect(forContentRect: desiredContentRect)

        var newFrame = window.frame
        let heightDelta = desiredFrame.height - newFrame.height
        newFrame.origin.y -= heightDelta
        newFrame.size.height = desiredFrame.height
        if newFrame.size.height < window.minSize.height {
            let clampDelta = window.minSize.height - newFrame.size.height
            newFrame.origin.y -= clampDelta
            newFrame.size.height = window.minSize.height
        }
        window.setFrame(newFrame, display: true, animate: window.isVisible)
    }

    func show() {
        // Refresh whichever tab is frontmost (launch-at-login status, tonight's
        // timeline) every time the window is (re)opened, not just at construction.
        showTab(tabControl.selectedSegment)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
