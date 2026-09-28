import AppKit

/// The menu bar mark: the site's nav logo (`site/assets/favicon.svg` without its tile).
/// An orange half-sun over three horizon lines. The sun keeps the brand orange; the
/// lines use `labelColor`, resolved each time the image is drawn, so they are white
/// on a dark menu bar and black on a light one. Not a template image on purpose:
/// a template would flatten the sun to the menu bar's text colour.
enum StatusBarIcon {

    /// The logo's 24-unit viewBox, cropped to the mark (sun top 8.0, bottom line 20.6
    /// plus half the 1.6 stroke).
    private static let crop = CGRect(x: 3.2, y: 7.2, width: 17.6, height: 14.2)

    static func make(height: CGFloat = 15) -> NSImage {
        let u = height / crop.height
        let size = NSSize(width: (crop.width * u).rounded(), height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: (x - crop.minX) * u, y: (y - crop.minY) * u)
            }

            // Half sun: circle (12, 14.5) r 6.5, clipped to above the horizon.
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: size.width, height: p(0, 14.5).y))
            let c = p(12, 14.5), r = 6.5 * u
            ctx.setFillColor(NSColor(srgbRed: 1, green: 0xB0 / 255, blue: 0x67 / 255, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ctx.restoreGState()

            // Horizon lines, in the menu bar's text colour.
            ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(1).cgColor)   // opaque: no sun showing through
            ctx.setLineWidth(1.6 * u)
            ctx.setLineCap(.round)
            for (x0, x1, y) in [(4.0, 20.0, 14.5), (7.0, 17.0, 17.8), (9.8, 14.2, 20.6)] {
                ctx.move(to: p(x0, y)); ctx.addLine(to: p(x1, y))
            }
            ctx.strokePath()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "DuskMode"
        return image
    }
}
