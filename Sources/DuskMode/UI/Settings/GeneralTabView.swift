import AppKit

/// General settings: app identity + a READ-ONLY launch-at-login status line. No
/// toggle here on purpose (settled 2026-07-16) — it's an OS-owned, set-once setting;
/// System Settings → General → Login Items is the real control surface.
final class GeneralTabView: NSView {

    init(isLaunchAtLoginEnabled: Bool) {
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: "DuskMode")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String) ?? "0.1"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor

        let subtitle = NSTextField(wrappingLabelWithString:
            "A science based evening wind down: warm colour, dimming, and grayscale, "
            + "automatically timed to sunset and your bedtime.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        let loginTitle = NSTextField(labelWithString: "Launch at Login")
        loginTitle.font = .systemFont(ofSize: 13, weight: .medium)
        let loginStatus = NSTextField(labelWithString: isLaunchAtLoginEnabled ? "On" : "Off")
        loginStatus.font = .systemFont(ofSize: 13)
        loginStatus.textColor = .secondaryLabelColor
        loginStatus.setContentHuggingPriority(.required, for: .horizontal)
        let loginRow = NSStackView(views: [loginTitle, loginStatus])
        loginRow.orientation = .horizontal
        loginRow.distribution = .equalSpacing
        loginRow.translatesAutoresizingMaskIntoConstraints = false

        let loginCaption = NSTextField(wrappingLabelWithString:
            "DuskMode starts automatically when you log in. You can manage this in "
            + "System Settings, under General, then Login Items.")
        loginCaption.font = .systemFont(ofSize: 11)
        loginCaption.textColor = .secondaryLabelColor

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [
            title, versionLabel, subtitle, separator, loginRow, loginCaption
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(3, after: title)
        stack.setCustomSpacing(16, after: versionLabel)
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(18, after: separator)
        stack.setCustomSpacing(6, after: loginRow)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            // Pinning the bottom too (not just top) is what actually gives this view a
            // well-defined height equal to the stack's content — without it the view's
            // real height came from whatever the window happened to be, so the content
            // could end up flush against the window edge with no bottom breathing room.
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            loginRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            loginCaption.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}
