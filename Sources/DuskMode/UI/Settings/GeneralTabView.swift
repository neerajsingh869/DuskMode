import AppKit

/// General settings: app identity + a READ-ONLY launch-at-login status line. No
/// toggle here on purpose (settled 2026-07-16) — it's an OS-owned, set-once setting;
/// System Settings → General → Login Items is the real control surface.
final class GeneralTabView: NSView {

    private static let contentWidth: CGFloat = 380

    init(isLaunchAtLoginEnabled: Bool) {
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: "DuskMode")
        title.font = .systemFont(ofSize: 16, weight: .semibold)

        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String) ?? "0.1"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor

        let subtitle = NSTextField(wrappingLabelWithString:
            "Science-based evening wind-down: warm colour, dimming, and grayscale, "
            + "automatically timed to sunset and your bedtime.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = Self.contentWidth

        let loginTitle = NSTextField(labelWithString: "Launch at Login")
        loginTitle.font = .systemFont(ofSize: 12, weight: .medium)
        let loginStatus = NSTextField(labelWithString: isLaunchAtLoginEnabled ? "On" : "Off")
        loginStatus.font = .systemFont(ofSize: 12)
        loginStatus.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let loginRow = NSStackView(views: [loginTitle, spacer, loginStatus])
        loginRow.orientation = .horizontal
        loginRow.distribution = .fill
        loginRow.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true

        let loginCaption = NSTextField(wrappingLabelWithString:
            "DuskMode starts automatically when you log in. Manage this in "
            + "System Settings → General → Login Items.")
        loginCaption.font = .systemFont(ofSize: 11)
        loginCaption.textColor = .secondaryLabelColor
        loginCaption.preferredMaxLayoutWidth = Self.contentWidth

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true

        let stack = NSStackView(views: [
            title, versionLabel, subtitle, separator, loginRow, loginCaption
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(2, after: title)
        stack.setCustomSpacing(14, after: versionLabel)
        stack.setCustomSpacing(16, after: subtitle)
        stack.setCustomSpacing(14, after: separator)
        stack.setCustomSpacing(4, after: loginRow)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}
