#!/usr/bin/env swift
// Renders the WindowHop app icon and writes an .iconset directory.
// Usage: scripts/make-icon.swift <output-dir>  (or `make icon`, which runs every art generator)
// Then: iconutil -c icns <output-dir>/AppIcon.iconset -o Support/AppIcon.icns
//
// Favicon: scripts/make-icon.swift --favicon site
// writes <dir>/favicon.ico (16, 32 and 48 px PNG entries) and <dir>/favicon-192.png
// from drawFavicon, a small-size rendition of the same mark (issue #93), plus the
// page's app icon (<dir>/assets/app-icon.png) and <dir>/apple-touch-icon.png.
import AppKit

/// AppKit returns nil here only when it cannot allocate the object; stop with its name.
func required<T>(_ value: T?, _ what: String) -> T {
    guard let value else { fatalError("could not create \(what)") }
    return value
}

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
    let gradient = required(NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.32, blue: 0.85, alpha: 1),
                                       ending: NSColor(calibratedRed: 0.33, green: 0.56, blue: 0.98, alpha: 1)),
                            "the plate gradient")
    gradient.draw(in: plate, angle: 90)

    drawWindows(plate: plate, shadowScale: scale, titleBar: true, backAlpha: 0.42)

    image.unlockFocus()
    return image
}

/// The two windows on the 1024 grid: the one you leave, faded behind, and the one you
/// land on, in front and floating on a soft shadow. No arrow: the overlap and the
/// shadow say "switch". Drawn in the caller's transform.
///
/// NSShadow offset and blur are in device space and ignore the current transform, so
/// `shadowScale` (device units per grid unit) scales them; without it the 16 and 32 px
/// renditions would carry a shadow as large as the 1024 one.
func drawWindows(plate: NSBezierPath, shadowScale: CGFloat, titleBar: Bool, backAlpha: CGFloat) {
    let blue = NSColor(calibratedRed: 0.13, green: 0.32, blue: 0.85, alpha: 1)

    NSColor(calibratedWhite: 1, alpha: backAlpha).setFill()
    NSBezierPath(roundedRect: NSRect(x: 227, y: 402, width: 460, height: 330),
                 xRadius: 44, yRadius: 44).fill()

    // clipped to the plate so the shadow never leaves it
    NSGraphicsContext.saveGraphicsState()
    plate.addClip()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -22 * shadowScale)
    shadow.shadowBlurRadius = 48 * shadowScale
    shadow.shadowColor = NSColor(calibratedRed: 0.03, green: 0.10, blue: 0.35, alpha: 0.55)
    shadow.set()
    NSColor(calibratedWhite: 1, alpha: 0.97).setFill()
    NSBezierPath(roundedRect: NSRect(x: 337, y: 292, width: 460, height: 330),
                 xRadius: 44, yRadius: 44).fill()
    NSGraphicsContext.restoreGraphicsState()

    // front window title bar hint
    if titleBar {
        blue.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: NSRect(x: 377, y: 550, width: 166, height: 28),
                     xRadius: 14, yRadius: 14).fill()
    }
}

func writePNG(_ image: NSImage, to url: URL, pixels: Int, background: NSColor? = nil) throws {
    let rep = required(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                       "a \(pixels) px bitmap")
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if let background {
        background.setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    }
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: background == nil ? .copy : .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try pngData(rep).write(to: url)
}

// The favicon is the app icon's mark redrawn for 16 to 48 pixels, where the app icon's
// transparent margin and 28-unit title-bar hint shrink below one pixel
// and Google Search shows a cramped mark (issue #93). Same palette and composition on
// the same 1024 grid; only the values below differ. The app icon itself is unchanged.
enum Favicon {
    /// The plate fills the canvas: the app icon's 100-unit margin is for the Dock, not
    /// for a 16 px tab. At most this fraction of the canvas stays clear, rounded down to
    /// whole pixels so the plate edge lands on the pixel grid.
    static let insetFraction: CGFloat = 0.02
    static let backWindowAlpha: CGFloat = 0.45   // app icon: 0.42
    /// Below this size the title-bar hint is under one pixel and only adds noise.
    static let titleBarMinimumPixels = 32
    static let icoSizes = [16, 32, 48]
    /// Google Search asks for a square favicon larger than 48 px; 192 is 4 x 48.
    static let largeSize = 192
}

func drawFavicon(pixels: Int) -> NSBitmapImageRep {
    let rep = required(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                       "a \(pixels) px bitmap")
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
    required(NSGradient(starting: blue,
                        ending: NSColor(calibratedRed: 0.33, green: 0.56, blue: 0.98, alpha: 1)),
             "the plate gradient")
        .draw(in: plate, angle: 90)

    drawWindows(plate: plate, shadowScale: (canvas - 2 * inset) / 824,
                titleBar: pixels >= Favicon.titleBarMinimumPixels,
                backAlpha: Favicon.backWindowAlpha)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func pngData(_ rep: NSBitmapImageRep) -> Data {
    required(rep.representation(using: .png, properties: [:]), "PNG data")
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
    // The page's own copies of the app icon: the 512 px header and hero image, and the
    // 180 px Apple touch icon, which is opaque because iOS fills transparency with black.
    let icon = drawIcon(canvas: 1024)
    try FileManager.default.createDirectory(
        at: dir.appendingPathComponent("assets"), withIntermediateDirectories: true)
    try writePNG(icon, to: dir.appendingPathComponent("assets/app-icon.png"), pixels: 512)
    try writePNG(icon, to: dir.appendingPathComponent("apple-touch-icon.png"), pixels: 180,
                 background: .white)
    print("wrote \(dir.path)/favicon.ico, favicon-\(Favicon.largeSize).png, assets/app-icon.png and apple-touch-icon.png")
} else {
    let outputDir = arguments.first ?? "build/icon"
    let iconsetURL = URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    let source = drawIcon(canvas: 1024)
    for size in [16, 32, 128, 256, 512] {
        try writePNG(source, to: iconsetURL.appendingPathComponent("icon_\(size)x\(size).png"), pixels: size)
        try writePNG(source, to: iconsetURL.appendingPathComponent("icon_\(size)x\(size)@2x.png"), pixels: size * 2)
    }
    print("wrote \(iconsetURL.path)")
}
