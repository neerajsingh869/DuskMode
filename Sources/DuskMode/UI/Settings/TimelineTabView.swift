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

        let leftMargin: CGFloat = 46
        let rightMargin: CGFloat = 10
        let stripHeight: CGFloat = 18
        let axisHeight: CGFloat = 18
        let bottomMargin: CGFloat = stripHeight + axisHeight + 12

        // Domain is Sunset→Bedtime, NOT sunset→sunrise: everything after Bedtime holds
        // flat until sunrise, so including it would waste over half the chart's width
        // on a dead plateau and squeeze the anchors that actually matter.
        let displayEnd = timeline.anchors.last?.time ?? timeline.end
        let totalSpan = displayEnd.timeIntervalSince(timeline.start)
        guard totalSpan > 0 else { return }

        // The label rows need to be sized BEFORE the plot rect exists (they set the
        // top margin), but row packing only depends on the horizontal (x) axis, which
        // in turn only depends on left/right margins — not on top margin. So compute
        // the x-scale first, pack labels against it, then build the real plot rect
        // tall enough for however many rows came out, and finally draw.
        let plotMinX = leftMargin
        let plotWidth = bounds.width - leftMargin - rightMargin
        guard plotWidth > 0 else { return }
        func x(_ date: Date) -> CGFloat {
            plotMinX + CGFloat(date.timeIntervalSince(timeline.start) / totalSpan) * plotWidth
        }

        struct Marker { let time: Date; let name: String; let color: NSColor }
        var markers = timeline.anchors.map {
            Marker(time: $0.time, name: $0.name, color: NSColor.tertiaryLabelColor)
        }
        markers.append(Marker(time: timeline.grayscaleStart, name: "Grayscale",
                              color: .secondaryLabelColor))
        markers.sort { $0.time < $1.time }

        let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let labelGap: CGFloat = 10
        let rowHeight: CGFloat = 18
        // Anchors on this timeline can land within ~30 min of each other (Warm/Dusk/
        // Grayscale/Red), so labels alternate rows in a fixed zigzag by chronological
        // index rather than a left-to-right greedy pack — a greedy pack can leave one
        // label (e.g. Red) stacked alone several rows above its neighbours purely
        // because of where earlier labels happened to claim space, which reads as
        // arbitrary. Alternating rows is deterministic and symmetric regardless of the
        // exact anchor spacing; a label only escalates to the next same-parity row in
        // the rare case it would still collide with its same-lane neighbour.
        var rowNextFreeX: [CGFloat] = [-.greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        var placedMarkers: [(marker: Marker, row: Int, alignRight: Bool, labelWidth: CGFloat)] = []
        for (index, marker) in markers.enumerated() {
            let px = x(marker.time)
            let labelWidth = NSAttributedString(string: marker.name, attributes: [.font: labelFont])
                .size().width
            // Right-align labels that would otherwise run past the plot's edge
            // (Bedtime, the rightmost anchor, was clipped by the window before this).
            let alignRight = px + labelWidth + 4 > plotMinX + plotWidth
            let rangeMinX = alignRight ? px - labelWidth - 2 : px + 2
            let rangeMaxX = alignRight ? px - 2 : px + 2 + labelWidth
            var row = index % 2
            while rangeMinX < rowNextFreeX[row] {
                row += 2
                while row >= rowNextFreeX.count { rowNextFreeX.append(-.greatestFiniteMagnitude) }
            }
            rowNextFreeX[row] = rangeMaxX + labelGap
            placedMarkers.append((marker, row, alignRight, labelWidth))
        }

        // Room for however many label rows the packing above produced, plus a little
        // breathing space before the plot itself starts.
        let topMargin: CGFloat = CGFloat(rowNextFreeX.count) * rowHeight + 14

        let plot = NSRect(x: leftMargin, y: topMargin,
                          width: plotWidth,
                          height: bounds.height - topMargin - bottomMargin)
        guard plot.height > 0 else { return }
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

        // Draw the anchor markers (Sunset/Warm/Dusk/Red/Bedtime) + the grayscale edge
        // using the rows already worked out above, before the plot rect existed.
        for placed in placedMarkers {
            drawMarker(at: x(placed.marker.time), plot: plot, label: placed.marker.name,
                      color: placed.marker.color, row: placed.row,
                      alignRight: placed.alignRight, labelWidth: placed.labelWidth,
                      font: labelFont, rowHeight: rowHeight)
        }

        drawTimeLabel(timeline.start, x: plot.minX, alignRight: false)
        drawTimeLabel(displayEnd, x: plot.maxX, alignRight: true)
    }

    private var axisLabelAttrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
    }

    private func drawMarker(at px: CGFloat, plot: NSRect, label: String, color: NSColor,
                            row: Int, alignRight: Bool, labelWidth: CGFloat,
                            font: NSFont, rowHeight: CGFloat) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: px, y: plot.minY))
        line.line(to: NSPoint(x: px, y: plot.maxY))
        line.lineWidth = 0.5
        line.setLineDash([2, 2], count: 2, phase: 0)
        color.setStroke()
        line.stroke()
        let labelY = plot.minY - CGFloat(row + 1) * rowHeight
        let labelX = alignRight ? px - 2 - labelWidth : px + 2
        NSAttributedString(string: label, attributes: [
            .font: font, .foregroundColor: color
        ]).draw(at: NSPoint(x: labelX, y: labelY))
    }

    private func drawTimeLabel(_ date: Date, x: CGFloat, alignRight: Bool) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let s = NSAttributedString(string: formatter.string(from: date), attributes: axisLabelAttrs)
        let px = alignRight ? x - s.size().width : x
        s.draw(at: NSPoint(x: px, y: bounds.height - 16))
    }
}

/// Wraps the chart with a legend + explanatory caption.
final class TimelineTabView: NSView {
    private let chart = TimelineChartView()
    private let caption = NSTextField(wrappingLabelWithString: "")

    private func legendSwatch(color: NSColor, dashed: Bool = false) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = dashed ? NSColor.clear.cgColor : color.cgColor
        if dashed {
            let dash = CAShapeLayer()
            dash.strokeColor = color.cgColor
            dash.lineWidth = 2
            dash.lineDashPattern = [3, 2]
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 1))
            path.addLine(to: CGPoint(x: 16, y: 1))
            dash.path = path
            box.layer?.addSublayer(dash)
        }
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 16).isActive = true
        box.heightAnchor.constraint(equalToConstant: dashed ? 2 : 3).isActive = true
        return box
    }

    private func legendItem(swatch: NSView, text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        let row = NSStackView(views: [swatch, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    init() {
        super.init(frame: .zero)

        let legend = NSStackView(views: [
            legendItem(swatch: legendSwatch(color: .systemOrange), text: "Warmth"),
            legendItem(swatch: legendSwatch(color: .systemBlue, dashed: true), text: "Dimming"),
            legendItem(swatch: legendSwatch(color: .secondaryLabelColor), text: "Colour preview")
        ])
        legend.orientation = .horizontal
        legend.alignment = .centerY
        legend.spacing = 18

        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor

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
            chart.heightAnchor.constraint(equalToConstant: 260),

            legend.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 14),
            legend.leadingAnchor.constraint(equalTo: leadingAnchor),

            caption.topAnchor.constraint(equalTo: legend.bottomAnchor, constant: 10),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Pinning the bottom (not just top-down) gives this view a real, well-defined
            // height equal to its content, matching GeneralTabView — needed so the
            // Settings window can size itself to fit whichever tab is showing instead of
            // leaving mismatched blank space depending on the window's last height.
            caption.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func refresh(with timeline: CircadianTimeline) {
        chart.configure(timeline: timeline)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        caption.stringValue =
            "Tonight's wind down, computed automatically from today's sunset and your "
            + "bedtime, shown through Bedtime. Values then hold flat until sunrise at "
            + "\(formatter.string(from: timeline.end)). This chart is read only. The "
            + "timing and intensity come straight from the research (see the Science tab)."
    }
}
