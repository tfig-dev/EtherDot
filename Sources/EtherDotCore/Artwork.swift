import AppKit

/// The RJ45 port shape shared by the menu bar glyph and the app icon.
public enum RJ45Glyph {
    /// A jack opening: wide cavity, latch notch at the bottom, pin slots cut in from the top.
    public static func portPath(left: CGFloat, right: CGFloat, top: CGFloat, shoulder: CGFloat, bottom: CGFloat,
                                notchLeft: CGFloat, notchRight: CGFloat,
                                slots: [CGFloat], slotWidth: CGFloat, slotBottom: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: left, y: top))
        for x in slots.sorted() {
            path.line(to: NSPoint(x: x - slotWidth / 2, y: top))
            path.line(to: NSPoint(x: x - slotWidth / 2, y: slotBottom))
            path.line(to: NSPoint(x: x + slotWidth / 2, y: slotBottom))
            path.line(to: NSPoint(x: x + slotWidth / 2, y: top))
        }
        path.line(to: NSPoint(x: right, y: top))
        path.line(to: NSPoint(x: right, y: shoulder))
        path.line(to: NSPoint(x: notchRight, y: shoulder))
        path.line(to: NSPoint(x: notchRight, y: bottom))
        path.line(to: NSPoint(x: notchLeft, y: bottom))
        path.line(to: NSPoint(x: notchLeft, y: shoulder))
        path.line(to: NSPoint(x: left, y: shoulder))
        path.close()
        path.lineJoinStyle = .round
        return path
    }

    /// Menu bar glyph on a 16-unit grid: rounded-square outline, solid port, three pins.
    public static func draw(in rect: NSRect, color: NSColor) {
        let s = rect.width / 16
        color.setStroke()
        color.setFill()

        let outline = NSBezierPath(
            roundedRect: NSRect(x: rect.minX + 1.6 * s, y: rect.minY + 1.6 * s, width: 12.8 * s, height: 12.8 * s),
            xRadius: 3.2 * s, yRadius: 3.2 * s
        )
        outline.lineWidth = 1.3 * s
        outline.stroke()

        let transform = AffineTransform(translationByX: rect.minX, byY: rect.minY)
        let port = portPath(left: 4.6 * s, right: 11.4 * s, top: 11.4 * s, shoulder: 6.9 * s, bottom: 4.9 * s,
                            notchLeft: 6.3 * s, notchRight: 9.7 * s,
                            slots: [6.2 * s, 8.0 * s, 9.8 * s], slotWidth: 1.5 * s, slotBottom: 8.4 * s)
        port.transform(using: transform)
        port.lineWidth = 0.5 * s
        port.fill()
        port.stroke()
    }

    /// Monochrome template image for the status item.
    public static func templateImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ethernet"
        return image
    }
}

/// The app icon, drawn in a 1024-unit space on Apple's macOS icon grid
/// (824 x 824 rounded rectangle, 100 unit margin, drop shadow).
public enum AppIconArtwork {
    static func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    static let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    static func bodyPath(inset: CGFloat = 0) -> NSBezierPath {
        NSBezierPath(roundedRect: body.insetBy(dx: inset, dy: inset), xRadius: 185 - inset, yRadius: 185 - inset)
    }

    /// `simplified` uses three wide pins so the icon survives at 16 and 32 px.
    public static func draw(simplified: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        rgb(0x1B1D22).setFill()
        bodyPath().fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(starting: rgb(0x474B55), ending: rgb(0x1B1D22))?.draw(in: bodyPath(), angle: -90)
        let highlight = bodyPath(inset: 3)
        highlight.lineWidth = 6
        NSColor.white.withAlphaComponent(0.16).setStroke()
        highlight.stroke()

        // Link LED: sits behind the plug, glowing out from under its lower-right corner.
        let center = NSPoint(x: 706, y: 338), radius: CGFloat = 112
        let dot = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        NSGraphicsContext.saveGraphicsState()
        bodyPath().addClip()
        let glow = NSShadow()
        glow.shadowColor = rgb(0x34D058, 0.8)
        glow.shadowBlurRadius = 70
        glow.set()
        rgb(0x34D058).setFill()
        NSBezierPath(ovalIn: dot).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: rgb(0x6BEA88), ending: rgb(0x22B14C))?.draw(in: NSBezierPath(ovalIn: dot), angle: -90)

        // Plug, in front of the LED.
        let slots: [CGFloat] = simplified ? [398, 512, 626] : [356, 434, 512, 590, 668]
        let port = RJ45Glyph.portPath(left: 282, right: 742, top: 712, shoulder: 446, bottom: 332,
                                      notchLeft: 392, notchRight: 632,
                                      slots: slots, slotWidth: simplified ? 84 : 70, slotBottom: 540)
        port.lineWidth = 36
        NSGraphicsContext.saveGraphicsState()
        let lift = NSShadow()
        lift.shadowColor = NSColor.black.withAlphaComponent(0.35)
        lift.shadowBlurRadius = 18
        lift.shadowOffset = NSSize(width: 0, height: -6)
        lift.set()
        NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        rgb(0xF4F6FA).setFill()
        rgb(0xF4F6FA).setStroke()
        port.fill()
        port.stroke()
        NSGraphicsContext.current?.cgContext.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }

    public static func bitmap(pixels: Int) -> NSBitmapImageRep {
        Canvas.bitmap(pixelsWide: pixels, pixelsHigh: pixels, pointSize: NSSize(width: 1024, height: 1024)) {
            draw(simplified: pixels <= 64)
        }
    }

    public static func image(pixels: Int) -> NSImage {
        let rep = bitmap(pixels: pixels)
        rep.size = NSSize(width: pixels, height: pixels)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

public enum Canvas {
    public static func bitmap(pixelsWide: Int, pixelsHigh: Int, pointSize: NSSize, draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = pointSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    public static func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }
}
