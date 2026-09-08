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
    /// Settings is a compact global overlay. Most of the hit target remains
    /// inside the panel while a small named overlap keeps it attached to the
    /// outer top-right corner.
    static let chromeButtonHitSize: CGFloat = 44
    static let chromeButtonSymbolSize: CGFloat = 32
    static let chromeButtonOutsideOverlap: CGFloat = 10

    // MARK: Settings window
    /// Every pane renders into this one canvas, so selecting a pane never
    /// resizes the window (the native Settings behavior): panes with less
    /// content simply end in empty space, and a pane that outgrows the canvas —
    /// large Dynamic Type, a long localization — scrolls inside it. The height
    /// fits the tallest pane at the default text size and stays well inside a
    /// laptop display's usable height.
    static let settingsPaneWidth: CGFloat = 560
    static let settingsPaneHeight: CGFloat = 540
    static let settingsAboutIconSize: CGFloat = 64
    static let settingsAboutHeaderSpacing: CGFloat = 16
    static let settingsAboutTitleSpacing: CGFloat = 3
    static let settingsAboutHeaderPadding: CGFloat = 4

    // MARK: Tiles (both appearances)
    /// Preview canvases use this radius for their fixed content and focus ring.
    static let cardCornerRadius: CGFloat = 10
    /// App Icons follows the native switcher idiom: no neutral border, with a
    /// soft rounded selection background around the icon canvas.
    static let iconSelectionPadding: CGFloat = 6
    static let iconSelectionCornerRadius: CGFloat = 18
    /// Preview selection is a single accent-colored plate behind the canvas,
    /// not a border stacked over the image.
    static let previewSelectionPadding: CGFloat = 2
    /// One horizontal rhythm for every row; tiles never manufacture spacing by
    /// changing their own dimensions.
    static let tileSpacing: CGFloat = 18
    /// Full-card separation between wrapped rows. The tile height already
    /// includes preview overlays, title, and metadata; this is the remaining
    /// visual breathing room between complete cards.
    static let tileRowSpacing: CGFloat = 30
    static let tileLabelInset: CGFloat = 8
    /// Native system typography, tuned to the public product preview. Font
    /// family remains AppKit-owned so locale, rendering, and accessibility
    /// continue to follow macOS.
    static let titleFontSize: CGFloat = 14
    static let titleFontWeight: NSFont.Weight = .medium
    static let titleLetterSpacing: CGFloat = -0.08
    static let metadataFontSize: CGFloat = 12
    static let metadataFontWeight: NSFont.Weight = .regular
    static let metadataLetterSpacing: CGFloat = 0
    /// Titles wrap to two lines before truncating; the zone is always two lines
    /// tall so tiles never resize between one- and two-line titles. A single
    /// line centers vertically inside the zone.
    static let titleZoneHeight: CGFloat = 36
    static let titleMaxLines = 2
    static let metadataHeight: CGFloat = 16
    static let labelBottomInset: CGFloat = 6
    static let titleMetadataSpacing: CGFloat = 1
    static let contentTopInset: CGFloat = 10
    /// The one gap between the bottom of the content (icon or preview) and the
    /// top of the title zone — identical on every card, in both appearances.
    static let contentTitleGap: CGFloat = 12

    /// Tile height derived from the content height, so the label zone and the
    /// content-to-title gap stay identical across appearances and screens.
    static func titleY(showMetadata: Bool) -> CGFloat {
        labelBottomInset + (showMetadata ? metadataHeight + titleMetadataSpacing : 0)
    }

    static func tileHeight(contentHeight: CGFloat, showMetadata: Bool) -> CGFloat {
        titleY(showMetadata: showMetadata) + titleZoneHeight
            + contentTitleGap + contentHeight + contentTopInset
    }

    // MARK: App Icons appearance (density matched to the native switcher)
    static let appIconsTileWidth: CGFloat = 124
    static let appIconsContentHeight: CGFloat = 92
    static let largeIconSize: CGFloat = 88

    // MARK: Window Previews appearance
    static let previewsTileWidth: CGFloat = 204
    /// Every preview canvas is this fixed shape, so all cards have identical
    /// dimensions and any window aspect-fits inside without cropping (unused
    /// area uses the semantic preview surface instead of exposing content
    /// behind the panel). It is deliberately independent of the monitor:
    /// deriving it from the display made every card a shallow strip on an
    /// ultrawide screen, where previews are hardest to recognize.
    static let previewCanvasAspect: CGFloat = 16.0 / 10.0
    static func previewContentHeight(width: CGFloat) -> CGFloat {
        (width / previewCanvasAspect).rounded()
    }
    static let previewCornerRadius = cardCornerRadius
    /// The badge is 60% of its previous rendered size and overlaps the fixed
    /// canvas corner, independent of the source image's aspect-fit bounds.
    static let previewBadgeSize: CGFloat = 48
    static let previewOverlayOverlap: CGFloat = 8
    /// The snapshot's own soft shadow (the capture itself is shadow-free); the
    /// path follows the preview's rounded shape, never a plain rectangle.
    static let previewShadowRadius: CGFloat = 6
    static let previewShadowOpacity: Float = 0.16
    static let previewShadowOffset = CGSize(width: 0, height: -2)

    // MARK: Overlay close control
    static let closeButtonHitSize: CGFloat = 44
    static let closeButtonVisibleSize: CGFloat = 28
    static let closeButtonGlyphSize: CGFloat = 12
    /// The centered control extends beyond the canvas. The panel reuses its
    /// existing padding as clip-safe overflow, so neither cards nor the visible
    /// panel grow to accommodate it.
    static let closeButtonLeadingOverflow = max(
        0, closeButtonHitSize / 2 - tileLabelInset)
    static let closeButtonTopOverflow = max(
        0, closeButtonHitSize / 2 - contentTopInset)
    // MARK: Preview skeleton (while loading or unavailable)
    static let previewFillInFadeDuration: TimeInterval = 0.15
    /// Crossfade used when a fresh capture replaces a cached snapshot mid-session.
    static let previewRefreshFadeDuration: TimeInterval = 0.25
    static let previewSkeletonPulseDuration: TimeInterval = 1.15
    static let previewSkeletonMinimumOpacity: Float = 0.5
    static let previewSkeletonTitleBarHeight: CGFloat = 17
    static let previewSkeletonInset: CGFloat = 12
    static let previewSkeletonDotSize: CGFloat = 4
    static let previewSkeletonDotSpacing: CGFloat = 5
    static let previewSkeletonLineHeight: CGFloat = 6
    static let previewSkeletonLineSpacing: CGFloat = 8
    static let previewSkeletonLineRadius: CGFloat = 3
    static let previewSkeletonLoadingLineFractions: [CGFloat] = [0.72, 0.88, 0.58, 0.81, 0.66]
    static let previewSkeletonUnavailableLineFractions: [CGFloat] = [0.62, 0.78, 0.48]

    // MARK: Colors
    static var iconSelectionFill: NSColor { .labelColor.withAlphaComponent(0.14) }
    static var iconEmphasisFill: NSColor { .labelColor.withAlphaComponent(0.075) }
    static var previewSelectionFill: NSColor {
        NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.78)
    }
    static var previewEmphasisFill: NSColor {
        NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.14)
    }
    /// A semantic, adaptive canvas surface makes letterboxing and placeholders
    /// intentional without framing every window with a gray rectangle.
    static var previewSurfaceFill: NSColor {
        NSColor.controlBackgroundColor.withAlphaComponent(0.76)
    }
    static var previewSkeletonChromeFill: NSColor {
        .separatorColor.withAlphaComponent(0.22)
    }
    static var previewSkeletonDotFill: NSColor {
        .tertiaryLabelColor.withAlphaComponent(0.42)
    }
    static var previewSkeletonLineFill: NSColor {
        .tertiaryLabelColor.withAlphaComponent(0.28)
    }
    static var previewSkeletonUnavailableLineFill: NSColor {
        .tertiaryLabelColor.withAlphaComponent(0.16)
    }
    static let settingsVisibilityFadeDuration: TimeInterval = 0.14

    // MARK: Expanded dwell preview
    static let expandedPreviewMinimumWidth: CGFloat = 720
    static let expandedPreviewMinimumHeight: CGFloat = 440
    static let expandedPreviewPanelInset: CGFloat = 24
    static let expandedPreviewTitleHeight: CGFloat = 34
    static let expandedPreviewBadgeSize: CGFloat = 56
    static let expandedPreviewBadgeInset: CGFloat = 10
    static let expandedPreviewCornerRadius: CGFloat = 16

    /// The expanded dwell presentation wraps its snapshot: the canvas takes the
    /// captured window's own shape, so the image fills it with no wasted
    /// surface and is never upscaled. Sizing it from the grid panel's measured
    /// frame instead made it a letterbox on wide displays, and a fixed ratio
    /// left a small image floating in a screen-sized panel.
    ///
    /// `imageSize` nil (nothing captured yet) falls back to the shared
    /// `previewCanvasAspect`, so the panel never jumps between shapes for the
    /// same window once its image arrives.
    static func expandedPreviewPanelSize(imageSize: CGSize?,
                                         visibleFrame: CGSize) -> CGSize {
        let chrome = CGSize(width: expandedPreviewPanelInset * 2,
                            height: expandedPreviewPanelInset * 2 + expandedPreviewTitleHeight)
        let aspect: CGFloat
        if let imageSize, imageSize.width > 0, imageSize.height > 0 {
            aspect = imageSize.width / imageSize.height
        } else {
            aspect = previewCanvasAspect
        }
        // the canvas may grow to the image's own points, but never past the
        // screen fractions or below the documented minimum
        let maxCanvas = CGSize(
            width: max(1, visibleFrame.width * panelMaxWidthFraction - chrome.width),
            height: max(1, visibleFrame.height * panelMaxHeightFraction - chrome.height))
        let minCanvas = CGSize(width: expandedPreviewMinimumWidth - chrome.width,
                               height: expandedPreviewMinimumHeight - chrome.height)
        var canvasWidth = min(imageSize?.width ?? maxCanvas.width, maxCanvas.width)
        canvasWidth = max(canvasWidth, min(minCanvas.width, maxCanvas.width))
        canvasWidth = min(canvasWidth, maxCanvas.height * aspect)
        var canvasHeight = canvasWidth / aspect
        if canvasHeight < minCanvas.height {
            canvasHeight = min(minCanvas.height, maxCanvas.height)
            canvasWidth = min(canvasHeight * aspect, maxCanvas.width)
        }
        return CGSize(width: canvasWidth + chrome.width,
                      height: canvasHeight + chrome.height)
    }
    /// Fallback panel material for macOS 14/15, close to the pre-Tahoe native
    /// switcher; on macOS 26+ the panel uses the system glass effect instead
    /// (see SwitcherPanel), which is what the native switcher draws with.
    static let panelMaterial: NSVisualEffectView.Material = .hudWindow
    /// Overlay controls use the Apple badge idiom (notification/Safari-tab
    /// close): a filled gray circle with a white glyph — legible on any content.
    static var overlayGlyphColor: NSColor { .white }
    static var overlayCircleColor: NSColor { NSColor(white: 0.3, alpha: 0.85) }
}
