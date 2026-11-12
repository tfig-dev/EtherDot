import AppKit
import EtherDotCore

// Usage: swift run IconGenerator [repo-root]
// Regenerates every piece of artwork from code: the AppIcon asset catalog,
// AppIcon.icns, the menu bar template image set, the DMG background and previews.

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let fm = FileManager.default

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func text(_ string: String, in rect: NSRect, color: NSColor, size: CGFloat, weight: NSFont.Weight = .regular) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (string as NSString).draw(in: rect, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
    ])
}

// MARK: App icon asset catalog + icns

let catalog = root.appendingPathComponent("Assets/Assets.xcassets")
let appIconSet = catalog.appendingPathComponent("AppIcon.appiconset")
let iconset = fm.temporaryDirectory.appendingPathComponent("EtherDot-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let rep = AppIconArtwork.bitmap(pixels: points * scale)
        try Canvas.writePNG(rep, to: appIconSet.appendingPathComponent(name))
        try Canvas.writePNG(rep, to: iconset.appendingPathComponent(name))
        images.append(["size": "\(points)x\(points)", "idiom": "mac", "filename": name, "scale": "\(scale)x"])
    }
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

let info: [String: Any] = ["author": "xcode", "version": 1]
try writeJSON(["info": info], to: catalog.appendingPathComponent("Contents.json"))
try writeJSON(["images": images, "info": info], to: appIconSet.appendingPathComponent("Contents.json"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Assets/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)

try Canvas.writePNG(AppIconArtwork.bitmap(pixels: 512), to: root.appendingPathComponent("docs/icon.png"))

// MARK: Menu bar template image set

let menuSet = catalog.appendingPathComponent("MenuBarIcon.imageset")
var menuImages: [[String: String]] = []
for scale in [1, 2, 3] {
    let name = "menubar-rj45\(scale > 1 ? "@\(scale)x" : "").png"
    let rep = Canvas.bitmap(pixelsWide: 18 * scale, pixelsHigh: 18 * scale, pointSize: NSSize(width: 18, height: 18)) {
        RJ45Glyph.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18), color: .black)
    }
    try Canvas.writePNG(rep, to: menuSet.appendingPathComponent(name))
    menuImages.append(["idiom": "mac", "filename": name, "scale": "\(scale)x"])
}
try writeJSON([
    "images": menuImages, "info": info,
    "properties": ["template-rendering-intent": "template"],
], to: menuSet.appendingPathComponent("Contents.json"))

// MARK: DMG background (600 x 400 pt window; icons centred at x 150 and 450, y 215 from the top)

func drawDMGBackground(in rect: NSRect) {
    NSGradient(starting: rgb(0xF7F8FA), ending: rgb(0xE3E7EE))?.draw(in: rect, angle: -90)
    text("EtherDot", in: NSRect(x: rect.minX, y: rect.maxY - 62, width: rect.width, height: 30), color: rgb(0x1B1D22), size: 22, weight: .semibold)
    text("Drag the app onto the Applications folder to install",
         in: NSRect(x: rect.minX, y: rect.maxY - 86, width: rect.width, height: 18), color: rgb(0x1B1D22, 0.55), size: 12)
    let y = rect.maxY - 215, start = rect.minX + 240, end = rect.minX + 360
    let arrow = NSBezierPath()
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: start, y: y))
    arrow.line(to: NSPoint(x: end, y: y))
    arrow.move(to: NSPoint(x: end - 16, y: y + 14))
    arrow.line(to: NSPoint(x: end, y: y))
    arrow.line(to: NSPoint(x: end - 16, y: y - 14))
    rgb(0x1B1D22, 0.28).setStroke()
    arrow.stroke()
    text("First launch: right-click the app → Open",
         in: NSRect(x: rect.minX, y: rect.minY + 22, width: rect.width, height: 16), color: rgb(0x1B1D22, 0.45), size: 11)
}

let dmgSize = NSSize(width: 600, height: 400)
for scale in [1, 2] {
    let rep = Canvas.bitmap(pixelsWide: 600 * scale, pixelsHigh: 400 * scale, pointSize: dmgSize) {
        drawDMGBackground(in: NSRect(origin: .zero, size: dmgSize))
    }
    try Canvas.writePNG(rep, to: root.appendingPathComponent("dmg/background\(scale == 2 ? "@2x" : "").png"))
}

// MARK: Preview sheet of the refined icon

let sheet = Canvas.bitmap(pixelsWide: 1240, pixelsHigh: 720, pointSize: NSSize(width: 620, height: 360)) {
    for (index, dark) in [false, true].enumerated() {
        let panel = NSRect(x: CGFloat(index) * 310, y: 0, width: 310, height: 360)
        (dark ? rgb(0x22252B) : rgb(0xE6E9EF)).setFill()
        panel.fill()
        AppIconArtwork.image(pixels: 512).draw(in: NSRect(x: panel.minX + 43, y: 110, width: 224, height: 224))
        var x = panel.minX + 60
        for size in [64, 32, 16] as [CGFloat] {
            AppIconArtwork.image(pixels: Int(size) * 2).draw(in: NSRect(x: x, y: 30 + (64 - size) / 2, width: size, height: size))
            x += size + 28
        }
    }
}
try Canvas.writePNG(sheet, to: root.appendingPathComponent("design/previews/app-icon-refined.png"))

print("Artwork written to \(root.path)")
