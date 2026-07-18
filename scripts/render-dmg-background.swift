#!/usr/bin/env swift
// Renders the DMG installer background (Support/dmg-background.tiff, 1x+2x).
// Run from the repository root after changing the artwork:
//   swift scripts/render-dmg-background.swift && tiffutil -cathidpicheck \
//     artifacts/dmg-bg.png artifacts/dmg-bg@2x.png -out Support/dmg-background.tiff
// The coordinates must stay in sync with the icon positions in make-dmg.sh:
// window 660x420, app icon centered at (180, 220), Applications at (480, 220).
import AppKit

let size = NSSize(width: 660, height: 420)

func draw(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size.width * scale),
                               pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // soft neutral gradient, readable in Light and Dark Finder chrome
    NSGradient(colors: [NSColor(calibratedWhite: 0.965, alpha: 1),
                        NSColor(calibratedWhite: 0.905, alpha: 1)])!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    func text(_ string: String, font: NSFont, color: NSColor, centerYFromTop: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let measured = (string as NSString).size(withAttributes: attributes)
        (string as NSString).draw(at: NSPoint(x: (size.width - measured.width) / 2,
                                              y: size.height - centerYFromTop - measured.height / 2),
                                  withAttributes: attributes)
    }

    text("Install WindowHop",
         font: .systemFont(ofSize: 27, weight: .semibold),
         color: NSColor(calibratedWhite: 0.13, alpha: 1), centerYFromTop: 64)
    text("Drag WindowHop into the Applications folder",
         font: .systemFont(ofSize: 14),
         color: NSColor(calibratedWhite: 0.42, alpha: 1), centerYFromTop: 100)
    text("First launch: right-click WindowHop, then choose Open",
         font: .systemFont(ofSize: 11.5),
         color: NSColor(calibratedWhite: 0.52, alpha: 1), centerYFromTop: 392)

    // arrow between the two icon slots (centers 180 and 480, icon size 128)
    let arrowColor = NSColor(calibratedWhite: 0.62, alpha: 1)
    arrowColor.setStroke()
    arrowColor.setFill()
    let arrowY = size.height - 220
    let shaft = NSBezierPath()
    shaft.lineWidth = 5
    shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: 270, y: arrowY))
    shaft.line(to: NSPoint(x: 372, y: arrowY))
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 368, y: arrowY + 14))
    head.line(to: NSPoint(x: 392, y: arrowY))
    head.line(to: NSPoint(x: 368, y: arrowY - 14))
    head.close()
    head.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outputDirectory = "artifacts"
try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
for (scale, name) in [(CGFloat(1), "dmg-bg.png"), (2, "dmg-bg@2x.png")] {
    let rep = draw(scale: scale)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(outputDirectory)/\(name)"))
    print("wrote \(outputDirectory)/\(name)")
}
