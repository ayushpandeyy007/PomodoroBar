// Renders the app icon into an .iconset folder.
// Usage: swift scripts/make_icon.swift <out.iconset>
import AppKit

let outDir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024) // draw in a 1024pt space at any pixel size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Body: macOS icon grid (824pt rounded square on a 1024pt canvas) with a soft drop shadow.
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(srgbRed: 0.9, green: 0.25, blue: 0.18, alpha: 1).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.42, blue: 0.32, alpha: 1),
               ending: NSColor(srgbRed: 0.85, green: 0.19, blue: 0.15, alpha: 1))!
        .draw(in: body, angle: -90)

    // Timer face: faint full disc + solid wedge of time remaining (matches the menu bar icon).
    let center = NSPoint(x: 512, y: 470)
    let radius: CGFloat = 260
    NSColor.white.withAlphaComponent(0.25).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    let wedge = NSBezierPath()
    wedge.move(to: center)
    wedge.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * 0.7, clockwise: true)
    wedge.close()
    NSColor.white.setFill()
    wedge.fill()

    // Tomato calyx: stem + two leaves on top of the face.
    let green = NSColor(srgbRed: 0.3, green: 0.72, blue: 0.32, alpha: 1)
    green.setFill()
    NSBezierPath(roundedRect: NSRect(x: 494, y: 730, width: 36, height: 100), xRadius: 18, yRadius: 18).fill()
    for angle in [20.0, 160.0] {
        var transform = AffineTransform(translationByX: 512, byY: 735)
        transform.rotate(byDegrees: angle)
        let leaf = NSBezierPath(ovalIn: NSRect(x: 0, y: -34, width: 190, height: 68))
        leaf.transform(using: transform)
        leaf.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, pixels) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    try render(pixels: pixels).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
