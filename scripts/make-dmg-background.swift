// Renders the DMG background (restrained: wordmark + drag direction arrow).
// Usage: swift scripts/make-dmg-background.swift <output-dir>
// Emits background.png (660x400) and background@2x.png; combine with tiffutil.
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/dmg-bg"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let canvas = NSSize(width: 660, height: 400)

func draw() {
    // soft neutral backdrop
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSRect(origin: .zero, size: canvas).fill()

    // wordmark
    let title = "WindowHop" as NSString
    title.draw(at: NSPoint(x: 28, y: canvas.height - 52),
               withAttributes: [
                   .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                   .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1),
               ])
    let subtitle = "Drag to Applications to install" as NSString
    let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14),
        .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1),
    ]
    let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
    subtitle.draw(at: NSPoint(x: (canvas.width - subtitleSize.width) / 2, y: 44),
                  withAttributes: subtitleAttributes)

    // arrow between the two icon positions (icons sit at x=165 and x=495,
    // centered around y=210 in Finder coordinates → y≈190 here)
    let arrowColor = NSColor(calibratedWhite: 0.62, alpha: 1)
    arrowColor.setStroke()
    arrowColor.setFill()
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 268, y: 190))
    shaft.line(to: NSPoint(x: 368, y: 190))
    shaft.lineWidth = 10
    shaft.lineCapStyle = .round
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 366, y: 212))
    head.line(to: NSPoint(x: 400, y: 190))
    head.line(to: NSPoint(x: 366, y: 168))
    head.close()
    head.fill()
}

for scale in [1, 2] {
    let pixels = NSSize(width: canvas.width * CGFloat(scale), height: canvas.height * CGFloat(scale))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvas // points, so the 2x rep reports 144 dpi
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: outputDir).appendingPathComponent(name))
}
print("wrote \(outputDir)/background.png and background@2x.png")
