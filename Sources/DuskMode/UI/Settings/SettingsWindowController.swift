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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "DuskMode Settings"
        window.minSize = NSSize(width: 420, height: 360)
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
            tabControl.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            tabControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            tabControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            contentContainer.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 16),
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])

        window?.contentView = root
        showTab(0)
    }

    @objc private func tabChanged() { showTab(tabControl.selectedSegment) }

    private func showTab(_ index: Int) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let view: NSView
        switch index {
        case 0:
            // Rebuilt fresh each time, not cached — the launch-at-login status can
            // change from outside the app (System Settings → Login Items).
            view = GeneralTabView(isLaunchAtLoginEnabled: launchAtLogin.isLaunchAtLoginEnabled)
        case 1:
            timelineView.refresh(with: circadianEngine.currentTimeline)
            view = timelineView
        default:
            view = scienceView
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    func show() {
        // Refresh whichever tab is frontmost (launch-at-login status, tonight's
        // timeline) every time the window is (re)opened, not just at construction.
        showTab(tabControl.selectedSegment)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
