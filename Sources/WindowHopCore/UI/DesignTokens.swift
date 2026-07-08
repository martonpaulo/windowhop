import AppKit

/// Every size, inset, radius, and font size the switcher UI uses, in one place.
/// Tuned against the native macOS ⌘⇥ switcher's proportions. Views never hardcode
/// dimensions — change a token here and every surface follows.
enum DesignTokens {
    // MARK: Panel chrome
    static let panelPadding: CGFloat = 16
    static let panelCornerRadius: CGFloat = 28
    /// The grid may use up to this fraction of the screen's width/height.
    static let panelMaxWidthFraction: CGFloat = 0.88
    static let panelMaxHeightFraction: CGFloat = 0.85
    /// The panel Settings control (top-right corner), matched to the tile close
    /// control so the two overlay buttons read as one family, on one inset grid.
    static let chromeButtonSize: CGFloat = 26
    static let chromeButtonSymbolSize: CGFloat = 19
    static let overlayInset: CGFloat = 8

    // MARK: Tiles (both appearances)
    static let tileSelectionCornerRadius: CGFloat = 18
    static let tileSelectionInset: CGFloat = 4
    static let tileLabelInset: CGFloat = 8
    static let titleFontSize: CGFloat = 13
    static let tabsFontSize: CGFloat = 11
    /// Titles wrap to two lines before truncating; the zone is always two lines
    /// tall so tiles never resize between one- and two-line titles.
    static let titleZoneHeight: CGFloat = 34
    static let titleMaxLines = 2
    static let titleY: CGFloat = 22
    static let tabsHeight: CGFloat = 15
    static let tabsY: CGFloat = 6
    static let contentTopInset: CGFloat = 10

    // MARK: App Icons appearance (density matched to the native switcher)
    static let appIconsTileSize = NSSize(width: 124, height: 162)
    static let appIconsContentHeight: CGFloat = 92
    static let largeIconSize: CGFloat = 88

    // MARK: Window Previews appearance
    static let previewsTileSize = NSSize(width: 204, height: 170)
    static let previewsContentHeight: CGFloat = 100
    static let previewFallbackIconSize: CGFloat = 72
    static let previewCornerRadius: CGFloat = 10
    /// The app icon badged onto a snapshot — large enough to identify at a glance.
    static let previewBadgeSize: CGFloat = 40
    static let previewBadgeOutset: CGFloat = 8

    // MARK: Overlay close control
    static let closeButtonSize: CGFloat = 26
    static let closeButtonSymbolSize: CGFloat = 20
    /// Overlay controls hang half over the content corner, badge-style
    /// (the Mission Control / Safari tab-close idiom).
    static let closeButtonCornerOverlap: CGFloat = 10

    // MARK: Preview placeholder (while a first snapshot loads)
    static let previewPlaceholderIconSize: CGFloat = 48
    static let previewFillInFadeDuration: TimeInterval = 0.15

    // MARK: Colors
    /// Selection: the native switcher's rounded rectangle is LIGHTER than the
    /// panel in Dark Mode and darker in Light Mode — labelColor with low alpha
    /// gives exactly that in both, resolved under the panel's appearance.
    static var selectionFill: NSColor { .labelColor.withAlphaComponent(0.16) }
    /// Placeholder card behind a not-yet-captured preview (a quieter step of
    /// the same ramp so it never competes with the selection).
    static var previewPlaceholderFill: NSColor { .labelColor.withAlphaComponent(0.07) }
    /// The native switcher's stable dark-glass panel (adaptive HUD material —
    /// far less see-through than a popover, so bright desktops can't wash it out).
    static let panelMaterial: NSVisualEffectView.Material = .hudWindow
    /// Overlay controls use the Apple badge idiom (notification/Safari-tab
    /// close): a filled gray circle with a white glyph — legible on any content.
    static var overlayGlyphColor: NSColor { .white }
    static var overlayCircleColor: NSColor { NSColor(white: 0.3, alpha: 0.85) }
}
