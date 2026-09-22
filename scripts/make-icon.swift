// Renders the WindowHop app icon and writes an .iconset directory.
// Usage: swift scripts/make-icon.swift <output-dir>
// Then: iconutil -c icns <output-dir>/AppIcon.iconset -o Support/AppIcon.icns
//
// Favicon: swift scripts/make-icon.swift --favicon site
// writes <dir>/favicon.ico (16, 32 and 48 px PNG entries) and <dir>/favicon-192.png
// from drawFavicon, a small-size rendition of the same mark (issue #93).
import AppKit

func drawIcon(canvas: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    let scale = canvas / 1024.0
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    // Big Sur-style rounded square, 824pt on the 1024 grid
    let plate = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                             xRadius: 185, yRadius: 185)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.32, blue: 0.85, alpha: 1),
                              ending: NSColor(calibratedRed: 0.33, green: 0.56, blue: 0.98, alpha: 1))!
    gradient.draw(in: plate, angle: 90)

    // back window (where you are leaving from)
    let backWindow = NSBezierPath(roundedRect: NSRect(x: 220, y: 420, width: 380, height: 270),
                                  xRadius: 40, yRadius: 40)
    NSColor(calibratedWhite: 1, alpha: 0.42).setFill()
    backWindow.fill()

    // front window (where you are hopping to)
    let frontWindow = NSBezierPath(roundedRect: NSRect(x: 430, y: 230, width: 380, height: 270),
                                   xRadius: 40, yRadius: 40)
    NSColor(calibratedWhite: 1, alpha: 0.97).setFill()
    frontWindow.fill()
    // front window title bar hint
    NSColor(calibratedRed: 0.13, green: 0.32, blue: 0.85, alpha: 0.25).setFill()
    NSBezierPath(roundedRect: NSRect(x: 466, y: 434, width: 150, height: 26),
                 xRadius: 13, yRadius: 13).fill()

    // hop arc from back to front
    let arc = NSBezierPath()
    arc.move(to: NSPoint(x: 400, y: 720))
    arc.curve(to: NSPoint(x: 700, y: 620),
              controlPoint1: NSPoint(x: 480, y: 870),
              controlPoint2: NSPoint(x: 650, y: 810))
    arc.lineWidth = 40
    arc.lineCapStyle = .round
    NSColor.white.setStroke()
    arc.stroke()

    // arrowhead at the arc's end, pointing toward the front window
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 700, y: 530))
    arrow.line(to: NSPoint(x: 762, y: 668))
    arrow.line(to: NSPoint(x: 612, y: 650))
    arrow.close()
    NSColor.white.setFill()
    arrow.fill()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL, pixels: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// The favicon is the app icon's mark redrawn for 16 to 48 pixels, where the app icon's
// transparent margin, 40-unit arc and 26-unit title-bar hint shrink below one pixel
// and Google Search shows a cramped mark (issue #93). Same palette and composition on
// the same 1024 grid; only the values below differ. The app icon itself is unchanged.
enum Favicon {
    /// The plate fills the canvas: the app icon's 100-unit margin is for the Dock, not
    /// for a 16 px tab. At most this fraction of the canvas stays clear, rounded down to
    /// whole pixels so the plate edge lands on the pixel grid.
    static let insetFraction: CGFloat = 0.02
    static let backWindowAlpha: CGFloat = 0.45   // app icon: 0.42
    static let arcWidth: CGFloat = 84            // app icon: 40
    static let arrowScale: CGFloat = 1.5         // about the arc's end point
    /// Below this size the title-bar hint is under one pixel and only adds noise.
    static let titleBarMinimumPixels = 32
    static let icoSizes = [16, 32, 48]
    /// Google Search asks for a square favicon larger than 48 px; 192 is 4 x 48.
    static let largeSize = 192
}

func drawFavicon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Map the app icon's plate (100...924 on the 1024 grid) onto the canvas.
    let canvas = CGFloat(pixels)
    let inset = (canvas * Favicon.insetFraction).rounded(.down)
    let transform = NSAffineTransform()
    transform.translateX(by: inset, yBy: inset)
    transform.scale(by: (canvas - 2 * inset) / 824)
    transform.translateX(by: -100, yBy: -100)
    transform.concat()

    let blue = NSColor(calibratedRed: 0.13, green: 0.32, blue: 0.85, alpha: 1)
    let plate = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                             xRadius: 185, yRadius: 185)
    NSGradient(starting: blue,
               ending: NSColor(calibratedRed: 0.33, green: 0.56, blue: 0.98, alpha: 1))!
        .draw(in: plate, angle: 90)

    NSColor(calibratedWhite: 1, alpha: Favicon.backWindowAlpha).setFill()
    NSBezierPath(roundedRect: NSRect(x: 220, y: 420, width: 380, height: 270),
                 xRadius: 40, yRadius: 40).fill()

    NSColor(calibratedWhite: 1, alpha: 0.97).setFill()
    NSBezierPath(roundedRect: NSRect(x: 430, y: 230, width: 380, height: 270),
                 xRadius: 40, yRadius: 40).fill()
    if pixels >= Favicon.titleBarMinimumPixels {
        blue.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: NSRect(x: 466, y: 434, width: 150, height: 26),
                     xRadius: 13, yRadius: 13).fill()
    }

    let arcEnd = NSPoint(x: 700, y: 620)
    let arc = NSBezierPath()
    arc.move(to: NSPoint(x: 400, y: 720))
    arc.curve(to: arcEnd,
              controlPoint1: NSPoint(x: 480, y: 870),
              controlPoint2: NSPoint(x: 650, y: 810))
    arc.lineWidth = Favicon.arcWidth
    arc.lineCapStyle = .round
    NSColor.white.setStroke()
    arc.stroke()

    // The app icon's arrowhead, enlarged about the arc's end so the join is kept.
    func scaled(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: arcEnd.x + (x - arcEnd.x) * Favicon.arrowScale,
                y: arcEnd.y + (y - arcEnd.y) * Favicon.arrowScale)
    }
    let arrow = NSBezierPath()
    arrow.move(to: scaled(700, 530))
    arrow.line(to: scaled(762, 668))
    arrow.line(to: scaled(612, 650))
    arrow.close()
    NSColor.white.setFill()
    arrow.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func pngData(_ rep: NSBitmapImageRep) -> Data {
    rep.representation(using: .png, properties: [:])!
}

/// An ICO file whose entries are PNG images, which every current browser and Google
/// Search read: a 6-byte header, one 16-byte directory entry per image, then the data.
/// https://learn.microsoft.com/en-us/previous-versions/ms997538(v=msdn.10)
func icoData(_ images: [(pixels: Int, png: Data)]) -> Data {
    var data = Data()
    func append16(_ value: Int) { data.append(contentsOf: [UInt8(value & 0xff), UInt8(value >> 8 & 0xff)]) }
    func append32(_ value: Int) { append16(value & 0xffff); append16(value >> 16 & 0xffff) }
    append16(0)                 // reserved
    append16(1)                 // type: icon
    append16(images.count)
    var offset = 6 + 16 * images.count
    for image in images {
        let side = UInt8(image.pixels >= 256 ? 0 : image.pixels)  // 0 means 256
        data.append(contentsOf: [side, side, 0, 0])  // width, height, palette, reserved
        append16(1)             // colour planes
        append16(32)            // bits per pixel
        append32(image.png.count)
        append32(offset)
        offset += image.png.count
    }
    for image in images { data.append(image.png) }
    return data
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--favicon" {
    let dir = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "site")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let entries = Favicon.icoSizes.map { (pixels: $0, png: pngData(drawFavicon(pixels: $0))) }
    try icoData(entries).write(to: dir.appendingPathComponent("favicon.ico"))
    try pngData(drawFavicon(pixels: Favicon.largeSize))
        .write(to: dir.appendingPathComponent("favicon-\(Favicon.largeSize).png"))
    print("wrote \(dir.path)/favicon.ico and favicon-\(Favicon.largeSize).png")
} else {
    let outputDir = arguments.first ?? "build/icon"
    let iconsetURL = URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    let master = drawIcon(canvas: 1024)
    for size in [16, 32, 128, 256, 512] {
        writePNG(master, to: iconsetURL.appendingPathComponent("icon_\(size)x\(size).png"), pixels: size)
        writePNG(master, to: iconsetURL.appendingPathComponent("icon_\(size)x\(size)@2x.png"), pixels: size * 2)
    }
    print("wrote \(iconsetURL.path)")
}
