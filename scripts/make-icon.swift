// Renders the WindowHop app icon and writes an .iconset directory.
// Usage: swift scripts/make-icon.swift <output-dir>
// Then: iconutil -c icns <output-dir>/AppIcon.iconset -o Support/AppIcon.icns
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon"

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

let iconsetURL = URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
let master = drawIcon(canvas: 1024)
for size in [16, 32, 128, 256, 512] {
    writePNG(master, to: iconsetURL.appendingPathComponent("icon_\(size)x\(size).png"), pixels: size)
    writePNG(master, to: iconsetURL.appendingPathComponent("icon_\(size)x\(size)@2x.png"), pixels: size * 2)
}
print("wrote \(iconsetURL.path)")
