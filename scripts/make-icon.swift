// Draws the DuskMode app icon (the site logo, site/assets/favicon.svg, on Apple's
// macOS icon grid) and writes Resources/AppIcon.icns.
//   swift scripts/make-icon.swift
// Re-run only when the logo changes; the .icns is committed and build.sh copies it.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)
    // Flip so the SVG's y-down coordinates can be used as-is.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // Apple's grid: an 824 pt body centred on the 1024 canvas, with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    // Shadow offsets are in device space (y up), so negative drops it downward.
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                  color: NSColor.black.withAlphaComponent(0.5).cgColor)
    ctx.addPath(bodyPath)
    ctx.setFillColor(NSColor(srgbRed: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    // Faint edge so the black body still reads on a dark Dock or Launchpad.
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
    ctx.setLineWidth(4)
    ctx.strokePath()

    // The logo's 24-unit viewBox mapped onto the body.
    let u = body.width / 24
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: body.minX + x * u, y: body.minY + y * u) }

    // Half sun: circle (12, 14.5) r 6.5, clipped to above the horizon.
    ctx.saveGState()
    ctx.clip(to: CGRect(x: body.minX, y: body.minY, width: body.width, height: 14.5 * u))
    let c = p(12, 14.5), r = 6.5 * u
    ctx.setFillColor(NSColor(srgbRed: 1, green: 0xB0 / 255, blue: 0x67 / 255, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.restoreGState()

    // Horizon lines.
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(1.6 * u)
    ctx.setLineCap(.round)
    for (x0, x1, y) in [(4.0, 20.0, 14.5), (7.0, 17.0, 17.8), (9.8, 14.2, 20.6)] {
        ctx.move(to: p(x0, y)); ctx.addLine(to: p(x1, y))
    }
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for pt in [16, 32, 128, 256, 512] {
    try render(pt).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try render(pt * 2).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
try render(1024).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-preview.png"))
print("Wrote \(out.path)")
