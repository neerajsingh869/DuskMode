import AppKit
import DuskModeCore

/// Read-only chart of tonight's wind-down: warmth (orange, solid) and dimming (blue,
/// dashed) sampled from `CircadianTimeline.target(at:)` across the sunset→sunrise
/// window, plus a colour-preview strip using the exact gamma formula (GammaEngine's
/// `currentMultiplier`) so the strip matches what the screen will actually look like.
/// No dragging/editing — settled 2026-07-16: this is "what is my evening doing", not
/// another surface for undermining the research-backed anchors (REGRESSIONS #20).
private final class TimelineChartView: NSView {
    private var timeline: CircadianTimeline?

    func configure(timeline: CircadianTimeline) {
        self.timeline = timeline
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let timeline, timeline.end > timeline.start else {
            NSAttributedString(string: "Waiting for a location fix…", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ]).draw(at: NSPoint(x: 8, y: bounds.midY - 8))
            return
        }

        let leftMargin: CGFloat = 40
        let rightMargin: CGFloat = 8
        // Room for two rows of anchor labels above the plot — Warm/Dusk/Grayscale/Red
        // can land within ~90 min of each other and would otherwise collide.
        let topMargin: CGFloat = 26
        let stripHeight: CGFloat = 16
        let axisHeight: CGFloat = 16
        let bottomMargin: CGFloat = stripHeight + axisHeight + 10

        let plot = NSRect(x: leftMargin, y: topMargin,
                          width: bounds.width - leftMargin - rightMargin,
                          height: bounds.height - topMargin - bottomMargin)
        guard plot.width > 0, plot.height > 0 else { return }

        // Domain is Sunset→Bedtime, NOT sunset→sunrise: everything after Bedtime holds
        // flat until sunrise, so including it would waste over half the chart's width
        // on a dead plateau and squeeze the anchors that actually matter.
        let displayEnd = timeline.anchors.last?.time ?? timeline.end
        let totalSpan = displayEnd.timeIntervalSince(timeline.start)
        guard totalSpan > 0 else { return }
        func x(_ date: Date) -> CGFloat {
            plot.minX + CGFloat(date.timeIntervalSince(timeline.start) / totalSpan) * plot.width
        }
        func y(_ value: Double) -> CGFloat {
            plot.minY + CGFloat(1 - max(0, min(1, value))) * plot.height
        }

        // Gridlines at 0/50/100%.
        NSColor.separatorColor.setStroke()
        for fraction: CGFloat in [0, 0.5, 1] {
            let line = NSBezierPath()
            let gy = plot.minY + fraction * plot.height
            line.move(to: NSPoint(x: plot.minX, y: gy))
            line.line(to: NSPoint(x: plot.maxX, y: gy))
            line.lineWidth = 0.5
            line.stroke()
        }
        NSAttributedString(string: "100%", attributes: axisLabelAttrs)
            .draw(at: NSPoint(x: 0, y: plot.minY - 5))
        NSAttributedString(string: "0%", attributes: axisLabelAttrs)
            .draw(at: NSPoint(x: 0, y: plot.maxY - 5))

        // Sample the timeline every 5 min: two curves + a colour-preview strip using
        // the SAME formula GammaEngine applies (blackbody multiplier × dim scale).
        let step: TimeInterval = 5 * 60
        let steps = max(1, Int(totalSpan / step))
        let sliceWidth = plot.width / CGFloat(steps) + 0.75
        let warmthPath = NSBezierPath()
        let dimPath = NSBezierPath()
        var t = timeline.start
        var first = true
        while t <= displayEnd {
            let target = timeline.target(at: t)
            let px = x(t)

            if first {
                warmthPath.move(to: NSPoint(x: px, y: y(target.warmth)))
                dimPath.move(to: NSPoint(x: px, y: y(target.dim)))
                first = false
            } else {
                warmthPath.line(to: NSPoint(x: px, y: y(target.warmth)))
                dimPath.line(to: NSPoint(x: px, y: y(target.dim)))
            }

            let m = ColorTemperature.multiplier(forWarmth: target.warmth)
            let s = 1 - min(1, max(0, target.dim)) * 0.92
            NSColor(calibratedRed: m.r * s, green: m.g * s, blue: m.b * s, alpha: 1).setFill()
            NSRect(x: px, y: plot.maxY + 6, width: sliceWidth, height: stripHeight).fill()

            t = t.addingTimeInterval(step)
        }

        NSColor.systemOrange.setStroke()
        warmthPath.lineWidth = 2
        warmthPath.stroke()

        NSColor.systemBlue.setStroke()
        dimPath.lineWidth = 1.5
        dimPath.setLineDash([4, 3], count: 2, phase: 0)
        dimPath.stroke()

        // Anchor markers (Sunset/Warm/Dusk/Red/Bedtime) + the grayscale edge, time-sorted
        // and greedily packed into rows so labels never collide even when anchors
        // cluster (Warm/Dusk/Grayscale/Red can land within ~90 min of each other).
        struct Marker { let time: Date; let name: String; let color: NSColor }
        var markers = timeline.anchors.map {
            Marker(time: $0.time, name: $0.name, color: NSColor.tertiaryLabelColor)
        }
        markers.append(Marker(time: timeline.grayscaleStart, name: "Grayscale",
                              color: .secondaryLabelColor))
        markers.sort { $0.time < $1.time }

        var rowNextFreeX: [CGFloat] = []
        let labelGap: CGFloat = 6
        for marker in markers {
            let px = x(marker.time)
            let labelWidth = NSAttributedString(string: marker.name, attributes: [
                .font: NSFont.systemFont(ofSize: 9)
            ]).size().width
            // Right-align labels that would otherwise run past the plot's edge
            // (Bedtime, the rightmost anchor, was clipped by the window before this).
            let alignRight = px + labelWidth + 4 > plot.maxX
            let rangeMinX = alignRight ? px - labelWidth - 2 : px + 2
            let rangeMaxX = alignRight ? px - 2 : px + 2 + labelWidth
            var row = 0
            while row < rowNextFreeX.count && rangeMinX < rowNextFreeX[row] { row += 1 }
            if row == rowNextFreeX.count { rowNextFreeX.append(-.greatestFiniteMagnitude) }
            rowNextFreeX[row] = rangeMaxX + labelGap
            drawMarker(at: px, plot: plot, label: marker.name, color: marker.color,
                      row: row, alignRight: alignRight, labelWidth: labelWidth)
        }

        drawTimeLabel(timeline.start, x: plot.minX, alignRight: false)
        drawTimeLabel(displayEnd, x: plot.maxX, alignRight: true)
    }

    private var axisLabelAttrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor]
    }

    private func drawMarker(at px: CGFloat, plot: NSRect, label: String, color: NSColor,
                            row: Int, alignRight: Bool, labelWidth: CGFloat) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: px, y: plot.minY))
        line.line(to: NSPoint(x: px, y: plot.maxY))
        line.lineWidth = 0.5
        line.setLineDash([2, 2], count: 2, phase: 0)
        color.setStroke()
        line.stroke()
        let labelY = plot.minY - 4 - CGFloat(row) * 11
        let labelX = alignRight ? px - 2 - labelWidth : px + 2
        NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 9), .foregroundColor: color
        ]).draw(at: NSPoint(x: labelX, y: labelY))
    }

    private func drawTimeLabel(_ date: Date, x: CGFloat, alignRight: Bool) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let s = NSAttributedString(string: formatter.string(from: date), attributes: axisLabelAttrs)
        let px = alignRight ? x - s.size().width : x
        s.draw(at: NSPoint(x: px, y: bounds.height - 14))
    }
}

/// Wraps the chart with a legend + explanatory caption.
final class TimelineTabView: NSView {
    private let chart = TimelineChartView()
    private let caption = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)

        let legend = NSTextField(labelWithString: "── Warmth    ╌╌ Dimming    ▬ Colour preview")
        legend.font = .systemFont(ofSize: 10)
        legend.textColor = .secondaryLabelColor

        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.preferredMaxLayoutWidth = 380

        chart.translatesAutoresizingMaskIntoConstraints = false
        legend.translatesAutoresizingMaskIntoConstraints = false
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)
        addSubview(legend)
        addSubview(caption)
        NSLayoutConstraint.activate([
            chart.topAnchor.constraint(equalTo: topAnchor),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor),
            chart.heightAnchor.constraint(equalToConstant: 220),

            legend.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 10),
            legend.leadingAnchor.constraint(equalTo: leadingAnchor),

            caption.topAnchor.constraint(equalTo: legend.bottomAnchor, constant: 6),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func refresh(with timeline: CircadianTimeline) {
        chart.configure(timeline: timeline)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        caption.stringValue =
            "Tonight's wind-down, computed automatically from today's sunset and your "
            + "bedtime, shown through Bedtime — deepest values then hold flat until "
            + "sunrise (\(formatter.string(from: timeline.end))). Read-only — the timing "
            + "and intensity come straight from the research (see the Science tab)."
    }
}
