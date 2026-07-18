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
    static let chromeButtonSize: CGFloat = 78
    static let chromeButtonSymbolSize: CGFloat = 57
    static let overlayInset: CGFloat = 8
    /// Chrome strip above the grid reserving room for the Settings control, so
    /// the enlarged gear never overlays tiles.
    static var panelTopChromeHeight: CGFloat { chromeButtonSize + overlayInset * 2 }

    // MARK: Tiles (both appearances)
    static let tileSelectionCornerRadius: CGFloat = 18
    /// The selection surrounds only the content area (icon or preview) — the
    /// title always stays outside the highlighted region.
    static let selectionPadding: CGFloat = 6
    static let tileLabelInset: CGFloat = 8
    static let titleFontSize: CGFloat = 13
    static let tabsFontSize: CGFloat = 11
    /// Titles wrap to two lines before truncating; the zone is always two lines
    /// tall so tiles never resize between one- and two-line titles. A single
    /// line centers vertically inside the zone.
    static let titleZoneHeight: CGFloat = 34
    static let titleMaxLines = 2
    static let titleY: CGFloat = 22
    static let tabsHeight: CGFloat = 15
    static let tabsY: CGFloat = 6
    static let contentTopInset: CGFloat = 10
    /// The one gap between the bottom of the content (icon or preview) and the
    /// top of the title zone — identical on every card, in both appearances.
    static let contentTitleGap: CGFloat = 12

    /// Tile height derived from the content height, so the label zone and the
    /// content-to-title gap stay identical across appearances and screens.
    static func tileHeight(contentHeight: CGFloat) -> CGFloat {
        titleY + titleZoneHeight + contentTitleGap + contentHeight + contentTopInset
    }

    // MARK: App Icons appearance (density matched to the native switcher)
    static let appIconsTileWidth: CGFloat = 124
    static let appIconsContentHeight: CGFloat = 92
    static let largeIconSize: CGFloat = 88

    // MARK: Window Previews appearance
    static let previewsTileWidth: CGFloat = 204
    /// Preview containers all share the aspect ratio of the display the
    /// switcher is presented on, so every card has identical dimensions and
    /// any window fits inside without cropping (unused area stays transparent).
    static func previewContentHeight(width: CGFloat, displayAspect: CGFloat) -> CGFloat {
        (width / max(displayAspect, 0.2)).rounded()
    }
    static let previewCornerRadius: CGFloat = 10
    /// The app icon badged onto a snapshot — large enough to identify at a glance.
    static let previewBadgeSize: CGFloat = 80
    static let previewBadgeOutset: CGFloat = 8
    /// The snapshot's own soft shadow (the capture itself is shadow-free); the
    /// path follows the preview's rounded shape, never a plain rectangle.
    static let previewShadowRadius: CGFloat = 8
    static let previewShadowOpacity: Float = 0.35
    static let previewShadowOffset = CGSize(width: 0, height: -3)

    // MARK: Overlay close control
    static let closeButtonSize: CGFloat = 78
    static let closeButtonSymbolSize: CGFloat = 60
    /// Overlay controls hang half over the content corner, badge-style
    /// (the Mission Control / Safari tab-close idiom).
    static let closeButtonCornerOverlap: CGFloat = 10

    // MARK: Preview placeholder (while a first snapshot loads)
    static let previewPlaceholderIconSize: CGFloat = 48
    static let previewFillInFadeDuration: TimeInterval = 0.15
    /// Crossfade used when a fresh capture replaces a cached snapshot mid-session.
    static let previewRefreshFadeDuration: TimeInterval = 0.25

    // MARK: Colors
    /// Selection: the native switcher's rounded rectangle is LIGHTER than the
    /// panel in Dark Mode and darker in Light Mode — labelColor with low alpha
    /// gives exactly that in both, resolved under the panel's appearance.
    static var selectionFill: NSColor { .labelColor.withAlphaComponent(0.16) }
    /// Placeholder card behind a not-yet-captured preview (a quieter step of
    /// the same ramp so it never competes with the selection).
    static var previewPlaceholderFill: NSColor { .labelColor.withAlphaComponent(0.07) }
    /// Fallback panel material for macOS 14/15, close to the pre-Tahoe native
    /// switcher; on macOS 26+ the panel uses the system glass effect instead
    /// (see SwitcherPanel), which is what the native switcher draws with.
    static let panelMaterial: NSVisualEffectView.Material = .hudWindow
    /// Overlay controls use the Apple badge idiom (notification/Safari-tab
    /// close): a filled gray circle with a white glyph — legible on any content.
    static var overlayGlyphColor: NSColor { .white }
    static var overlayCircleColor: NSColor { NSColor(white: 0.3, alpha: 0.85) }
}
