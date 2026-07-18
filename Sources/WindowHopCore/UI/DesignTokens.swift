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
    /// Settings is a compact global overlay. The visible glyph is half its
    /// previous size while the hit target remains comfortably clickable.
    static let chromeButtonHitSize: CGFloat = 44
    static let chromeButtonSymbolSize: CGFloat = 29

    // MARK: Tiles (both appearances)
    static let tileSelectionCornerRadius: CGFloat = 18
    /// The selection surrounds only the content area (icon or preview) — the
    /// title always stays outside the highlighted region.
    static let selectionPadding: CGFloat = 6
    /// One horizontal rhythm for every row; tiles never manufacture spacing by
    /// changing their own dimensions.
    static let tileSpacing: CGFloat = 18
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
    /// The badge is 60% of its previous rendered size and overlaps the fixed
    /// canvas corner, independent of the source image's aspect-fit bounds.
    static let previewBadgeSize: CGFloat = 48
    static let previewOverlayOverlap: CGFloat = 8
    /// The snapshot's own soft shadow (the capture itself is shadow-free); the
    /// path follows the preview's rounded shape, never a plain rectangle.
    static let previewShadowRadius: CGFloat = 8
    static let previewShadowOpacity: Float = 0.35
    static let previewShadowOffset = CGSize(width: 0, height: -3)

    // MARK: Overlay close control
    static let closeButtonHitSize: CGFloat = 44
    static let closeButtonSymbolSize: CGFloat = 30
    /// Overlay controls hang half over the content corner, badge-style
    /// (the Mission Control / Safari tab-close idiom).
    static let closeButtonBoundaryOverlap: CGFloat = 8

    // MARK: Preview placeholder (while a first snapshot loads)
    static let previewFillInFadeDuration: TimeInterval = 0.15
    /// Crossfade used when a fresh capture replaces a cached snapshot mid-session.
    static let previewRefreshFadeDuration: TimeInterval = 0.25

    // MARK: Colors
    /// Selection: the native switcher's rounded rectangle is LIGHTER than the
    /// panel in Dark Mode and darker in Light Mode — labelColor with low alpha
    /// gives exactly that in both, resolved under the panel's appearance.
    static var selectionFill: NSColor { .labelColor.withAlphaComponent(0.16) }
    static var temporaryTargetFill: NSColor { .labelColor.withAlphaComponent(0.09) }
    static var previewOutline: NSColor { .labelColor.withAlphaComponent(0.26) }
    static var previewEmphasisOutline: NSColor { .labelColor.withAlphaComponent(0.58) }
    static var previewSelectionOutline: NSColor { .keyboardFocusIndicatorColor }
    static let previewOutlineWidth: CGFloat = 1
    static let previewEmphasisOutlineWidth: CGFloat = 2
    static let previewSelectionOutlineWidth: CGFloat = 5
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
