import AppKit

/// Draws the menu bar icon as a template image so it adapts to light/dark menu bars.
/// Focus is a shrinking pie inside a circle; breaks are a shrinking ring.
enum StatusIcon {
    static func image(fraction: Double, isBreak: Bool) -> NSImage {
        let f = max(0, min(1, fraction))
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            if isBreak {
                let radius: CGFloat = 6.5
                let circle = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                let track = NSBezierPath(ovalIn: circle)
                track.lineWidth = 2
                NSColor.black.withAlphaComponent(0.3).setStroke()
                track.stroke()

                guard f > 0 else { return true }
                let arc: NSBezierPath
                if f >= 1 {
                    arc = NSBezierPath(ovalIn: circle)
                } else {
                    arc = NSBezierPath()
                    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
                    arc.lineCapStyle = .round
                }
                arc.lineWidth = 2
                NSColor.black.setStroke()
                arc.stroke()
            } else {
                NSColor.black.set()
                let outline = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                outline.lineWidth = 1.5
                outline.stroke()

                guard f > 0 else { return true }
                let radius: CGFloat = 4.5
                let pie: NSBezierPath
                if f >= 1 {
                    pie = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                } else {
                    pie = NSBezierPath()
                    pie.move(to: center)
                    pie.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
                    pie.close()
                }
                pie.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

enum Format {
    /// "24:59". Rounds up so the display reads 25:00 at the start and hits 0:00 exactly at the end.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int((seconds - 0.05).rounded(.up)))
        let s = total % 60
        return "\(total / 60):\(s < 10 ? "0" : "")\(s)"
    }

    /// "1h 15m" / "45m"
    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}
