import AppKit

/// Renders research/citations.json as scrollable, clickable text — every feature in
/// DuskMode traces to a study here, including the honest "limitations" counter-evidence
/// (Cochrane 2023 etc.). Read-only, native link clicking (NSTextView opens `.link`
/// attributes itself when non-editable — no delegate needed).
final class ScienceTabView: NSView {
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    init() {
        super.init(frame: .zero)

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func render() {
        guard let db = CitationsDatabase.load() else {
            textView.string = "Couldn't load research/citations.json — it should be "
                + "bundled at Contents/Resources/citations.json."
            return
        }
        let result = NSMutableAttributedString()
        for topic in db.topics {
            result.append(heading(topic.title, strength: topic.effectStrength))
            result.append(paragraph(topic.summary))
            if !topic.implementationImpact.isEmpty {
                result.append(caption("Used for: " + topic.implementationImpact))
            }
            for citation in topic.citations {
                result.append(citationLine(citation))
            }
            result.append(NSAttributedString(string: "\n"))
        }
        textView.textStorage?.setAttributedString(result)
    }

    private func heading(_ text: String, strength: String) -> NSAttributedString {
        let s = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor
        ])
        s.append(NSAttributedString(string: "  \(strength.uppercased())\n", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: color(forStrength: strength)
        ]))
        return s
    }

    private func color(forStrength strength: String) -> NSColor {
        switch strength {
        case "strong":   return .systemGreen
        case "moderate": return .systemYellow
        case "emerging": return .systemOrange
        default:         return .secondaryLabelColor
        }
    }

    private func paragraph(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ])
    }

    private func caption(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }

    private func citationLine(_ c: CitationsDatabase.Citation) -> NSAttributedString {
        let s = NSMutableAttributedString(string: "• ", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor
        ])
        s.append(NSAttributedString(string: c.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.linkColor,
            .link: URL(string: c.link) as Any,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]))
        s.append(NSAttributedString(string: " — \(c.authors), \(c.journal) \(c.year)\n",
                                    attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        s.append(NSAttributedString(string: c.keyFinding + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]))
        return s
    }
}
