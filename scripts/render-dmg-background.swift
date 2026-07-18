#!/usr/bin/env swift
// Renders the DMG installer background (Support/WindowHopInstallerBackground.tiff,
// 1x+2x). The distinctive basename prevents Finder from reusing cached artwork
// from an older mounted WindowHop volume.
// Run from the repository root after changing the artwork:
//   swift scripts/render-dmg-background.swift && tiffutil -cathidpicheck \
//     artifacts/dmg-bg.png artifacts/dmg-bg@2x.png \
//     -out Support/WindowHopInstallerBackground.tiff
// The coordinates must stay in sync with the icon positions in make-dmg.sh:
// window 680x400, app icon centered at (180, 225), Applications at (500, 225).
import AppKit

let size = NSSize(width: 680, height: 400)

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

    // Quiet semantic-looking surface with WindowHop's blue used only as an
    // accent. Finder renders the actual draggable icons above this artwork.
    NSGradient(colors: [NSColor(calibratedRed: 0.97, green: 0.98, blue: 1, alpha: 1),
                        NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.98, alpha: 1)])!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    func text(_ string: String, font: NSFont, color: NSColor, centerYFromTop: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let measured = (string as NSString).size(withAttributes: attributes)
        (string as NSString).draw(at: NSPoint(x: (size.width - measured.width) / 2,
                                              y: size.height - centerYFromTop - measured.height / 2),
                                  withAttributes: attributes)
    }

    // Small paired-window brand mark, intentionally distinct from the two
    // draggable Finder items below it.
    let markBack = NSBezierPath(roundedRect: NSRect(x: 313, y: 352, width: 26, height: 20),
                                xRadius: 6, yRadius: 6)
    NSColor.systemBlue.withAlphaComponent(0.32).setFill()
    markBack.fill()
    let markFront = NSBezierPath(roundedRect: NSRect(x: 335, y: 346, width: 28, height: 21),
                                 xRadius: 7, yRadius: 7)
    NSColor.systemBlue.setFill()
    markFront.fill()

    text("WindowHop",
         font: .systemFont(ofSize: 25, weight: .semibold),
         color: NSColor(calibratedWhite: 0.12, alpha: 1), centerYFromTop: 72)
    text("Drag WindowHop to Applications",
         font: .systemFont(ofSize: 14.5, weight: .medium),
         color: NSColor(calibratedWhite: 0.39, alpha: 1), centerYFromTop: 108)

    // arrow between the two icon slots (centers 180 and 480, icon size 128)
    let arrowColor = NSColor.systemBlue.withAlphaComponent(0.58)
    arrowColor.setStroke()
    arrowColor.setFill()
    let arrowY = size.height - 225
    let shaft = NSBezierPath()
    shaft.lineWidth = 5
    shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: 276, y: arrowY))
    shaft.line(to: NSPoint(x: 388, y: arrowY))
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 384, y: arrowY + 14))
    head.line(to: NSPoint(x: 408, y: arrowY))
    head.line(to: NSPoint(x: 384, y: arrowY - 14))
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
