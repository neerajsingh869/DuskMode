import AppKit

/// A non-editable NSTextView that reports a real intrinsic height from its own laid-out
/// content, so it can live inside an NSStackView like any other control. Needed because
/// plain NSTextView has no usable intrinsicContentSize on its own.
private final class WrappingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(used.height) + 1)
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }
}

/// A flipped plain view so its NSStackView content lays out top-down inside a scroll
/// view's document view (same technique as the paused-apps list in the popover).
private final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

/// Renders research/citations.json as a scrollable list of topic sections — every
/// feature in DuskMode traces to a study here, including the honest "limitations"
/// counter-evidence (Cochrane 2023 etc.). Each topic is its own block (heading + strength
/// badge, summary, citations) separated from the next by a real divider line, so
/// unrelated topics (e.g. "Blue Light & Melatonin" vs. "Green Light & Circadian Rhythm")
/// read as distinct sections rather than running together. Read-only; links open via
/// NSTextView's own non-editable link handling — no delegate needed.
final class ScienceTabView: NSView {
    private let scrollView = NSScrollView()
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = FlippedContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = container
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            container.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func render() {
        guard let db = CitationsDatabase.load() else {
            let label = NSTextField(wrappingLabelWithString:
                "Couldn't load research/citations.json. It should be bundled at "
                + "Contents/Resources/citations.json.")
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return
        }

        // Every gap between consecutive arranged subviews is set explicitly right after
        // adding the view that starts the gap — no implicit/default stack spacing, so
        // there's no risk of an unstyled gap slipping through (e.g. the last citation of
        // a topic before the next topic's divider, which the previous index-into-
        // arrangedSubviews approach missed).
        func add(_ view: NSView, spacingAfter: CGFloat) {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.setCustomSpacing(spacingAfter, after: view)
        }

        for (index, topic) in db.topics.enumerated() {
            if index > 0 {
                let divider = NSBox()
                divider.boxType = .separator
                divider.translatesAutoresizingMaskIntoConstraints = false
                add(divider, spacingAfter: 20)
            }

            let hasImpact = !topic.implementationImpact.isEmpty
            let hasCitations = !topic.citations.isEmpty

            let heading = topicHeadingRow(title: topic.title, strength: topic.effectStrength)
            add(heading, spacingAfter: 8)

            let summary = wrappingText(topic.summary, font: .systemFont(ofSize: 12.5),
                                       color: .labelColor, lineSpacing: 4)
            // Whichever block ends up last in this topic gets 20pt after it, so the gap
            // before the next divider (or the end of the list) is always the same —
            // matching the divider's own 20pt gap before the next heading.
            add(summary, spacingAfter: hasImpact ? 8 : (hasCitations ? 16 : 20))

            if hasImpact {
                let impact = wrappingText("Used for: " + topic.implementationImpact,
                                          font: .systemFont(ofSize: 11),
                                          color: .secondaryLabelColor, lineSpacing: 3)
                add(impact, spacingAfter: hasCitations ? 16 : 20)
            }

            for (cIndex, citation) in topic.citations.enumerated() {
                let block = citationBlock(citation)
                let isLast = cIndex == topic.citations.count - 1
                add(block, spacingAfter: isLast ? 20 : 14)
            }
        }
    }

    private func topicHeadingRow(title: String, strength: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0

        let row = NSStackView(views: [titleLabel, strengthBadge(strength)])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func strengthBadge(_ strength: String) -> NSView {
        let color = color(forStrength: strength)
        let label = NSTextField(labelWithString: strength.uppercased())
        label.font = .systemFont(ofSize: 9.5, weight: .bold)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false

        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
        badge.layer?.cornerRadius = 6
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: badge.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -3)
        ])
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        return badge
    }

    private func color(forStrength strength: String) -> NSColor {
        switch strength {
        case "strong":   return .systemGreen
        case "moderate": return .systemYellow
        case "emerging": return .systemOrange
        default:         return .secondaryLabelColor
        }
    }

    private func wrappingText(_ text: String, font: NSFont, color: NSColor,
                              lineSpacing: CGFloat) -> WrappingTextView {
        let tv = WrappingTextView()
        configure(tv)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        tv.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style
        ]))
        return tv
    }

    /// A single citation's title (link) + authors/journal/year + key finding, all left
    /// aligned with one consistent inset — no bullet, no hanging indent, so every line
    /// (first and wrapped) sits at the same x with no unexplained gap.
    private func citationBlock(_ c: CitationsDatabase.Citation) -> WrappingTextView {
        let tv = WrappingTextView()
        configure(tv, horizontalInset: 12)

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.lineSpacing = 2
        titleStyle.paragraphSpacing = 3
        let metaStyle = NSMutableParagraphStyle()
        metaStyle.lineSpacing = 2
        metaStyle.paragraphSpacing = 5
        let findingStyle = NSMutableParagraphStyle()
        findingStyle.lineSpacing = 3

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: c.title + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.linkColor,
            .link: URL(string: c.link) as Any,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .paragraphStyle: titleStyle
        ]))
        result.append(NSAttributedString(string: "\(c.authors) · \(c.journal) · \(c.year)\n",
                                         attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: metaStyle
        ]))
        result.append(NSAttributedString(string: c.keyFinding, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: findingStyle
        ]))
        tv.textStorage?.setAttributedString(result)
        return tv
    }

    private func configure(_ tv: WrappingTextView, horizontalInset: CGFloat = 0) {
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: horizontalInset, height: 0)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.translatesAutoresizingMaskIntoConstraints = false
    }
}
