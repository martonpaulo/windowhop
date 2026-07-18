import AppKit

/// One switcher entry in either appearance:
/// - App Icons: a genuinely large application icon dominates the tile.
/// - Window Previews: an aspect-fit window snapshot with the app icon as a
///   corner badge; until (or unless) a preview arrives, a quiet fixed-size
///   placeholder remains behind that same corner-aligned badge.
/// Every tile keeps a compact title and the reserved tab-count line, so tiles
/// never shift as data arrives. Hovering reveals an overlay close control that
/// routes through the same confirmation flow as Delete.
final class SwitcherTileView: NSView {
    struct Metrics {
        let tileSize: NSSize
        let contentHeight: CGFloat // icon or preview area height

        static let appIcons = Metrics(
            tileSize: NSSize(width: DesignTokens.appIconsTileWidth,
                             height: DesignTokens.tileHeight(contentHeight: DesignTokens.appIconsContentHeight)),
            contentHeight: DesignTokens.appIconsContentHeight)

        /// Preview containers share the presenting display's aspect ratio, so
        /// every card is identical and any window aspect-fits without cropping.
        static func windowPreviews(displayAspect: CGFloat) -> Metrics {
            let contentHeight = DesignTokens.previewContentHeight(
                width: DesignTokens.previewsTileWidth - DesignTokens.tileLabelInset * 2,
                displayAspect: displayAspect)
            return Metrics(
                tileSize: NSSize(width: DesignTokens.previewsTileWidth,
                                 height: DesignTokens.tileHeight(contentHeight: contentHeight)),
                contentHeight: contentHeight)
        }

        static func metrics(for mode: AppearanceMode) -> Metrics {
            mode == .appIcons ? .appIcons : .windowPreviews(displayAspect: mainDisplayAspect)
        }

        /// Aspect ratio of the display the switcher is presented on.
        static var mainDisplayAspect: CGFloat {
            guard let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame,
                  frame.height > 0 else { return 16.0 / 10.0 }
            return frame.width / frame.height
        }
    }

    var onClick: (() -> Void)?
    var onCloseRequest: (() -> Void)?
    private(set) var accessibilityText = ""

    private var metrics = Metrics.appIcons
    private var mode = AppearanceMode.appIcons
    private var hasPreview = false

    private let selectionView = NSView()
    private let iconView = NSImageView()
    private let previewView = NSImageView()
    /// Carries the snapshot's soft shadow: the shadow path follows the
    /// preview's rounded shape, so no rectangular halo can appear (the clip on
    /// previewView would swallow a shadow set on it directly).
    private let previewShadowView = NSView()
    /// Canvas-aligned outline above the image. It never participates in layout,
    /// so changing state cannot resize or move a card.
    private let previewOutlineView = NSView()
    /// Rounded card shown while a window has no snapshot yet, so the tile's
    /// geometry never jumps when the first capture fades in.
    private let placeholderView = NSView()
    private let badgeIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let tabsLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var trackingArea: NSTrackingArea?

    var isSelected = false {
        didSet { applySelectionStyle() }
    }

    var isTemporarilyActive = false {
        didSet { applySelectionStyle() }
    }

    private var isHovered = false {
        didSet { applySelectionStyle() }
    }

    /// Whether the tile currently shows a window snapshot (test hook for the
    /// stale-state regression coverage; pooled tiles must never carry a
    /// previous window's image).
    var showsPreviewImage: Bool { hasPreview && !previewView.isHidden && previewView.image != nil }
    var previewCanvasFrameForTesting: NSRect { previewOutlineView.frame }
    var previewImageFrameForTesting: NSRect { previewView.frame }
    var badgeFrameForTesting: NSRect { badgeIconView.frame }
    var closeFrameForTesting: NSRect { closeButton.frame }
    var previewOutlineWidthForTesting: CGFloat { previewOutlineView.layer?.borderWidth ?? 0 }
    var previewSelectionBackingAlphaForTesting: CGFloat {
        selectionView.layer?.backgroundColor?.alpha ?? 0
    }

    /// Tiles are pooled and reconfigured (never recreated per session) so the
    /// panel opens fast even with 100+ windows.
    init() {
        super.init(frame: NSRect(origin: .zero, size: Metrics.appIcons.tileSize))

        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = DesignTokens.tileSelectionCornerRadius
        selectionView.layer?.cornerCurve = .continuous
        addSubview(selectionView)

        placeholderView.wantsLayer = true
        placeholderView.layer?.cornerRadius = DesignTokens.previewCornerRadius
        placeholderView.layer?.cornerCurve = .continuous
        addSubview(placeholderView)

        previewShadowView.wantsLayer = true
        previewShadowView.layer?.shadowColor = NSColor.black.cgColor
        previewShadowView.layer?.shadowOpacity = DesignTokens.previewShadowOpacity
        previewShadowView.layer?.shadowRadius = DesignTokens.previewShadowRadius
        previewShadowView.layer?.shadowOffset = DesignTokens.previewShadowOffset
        addSubview(previewShadowView)

        previewView.imageScaling = .scaleProportionallyDown
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = DesignTokens.previewCornerRadius
        previewView.layer?.cornerCurve = .continuous
        previewView.layer?.masksToBounds = true
        addSubview(previewView)

        previewOutlineView.wantsLayer = true
        previewOutlineView.layer?.cornerCurve = .continuous
        addSubview(previewOutlineView)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        addSubview(iconView)

        badgeIconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(badgeIconView)

        titleLabel.font = .systemFont(ofSize: DesignTokens.titleFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        // wrap to two lines, then truncate — never an ellipsis a line early.
        // word-wrap + truncatesLastVisibleLine is the frame-based recipe;
        // .byTruncatingTail alone keeps the field single-line
        titleLabel.usesSingleLineMode = false
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.cell?.wraps = true
        titleLabel.cell?.isScrollable = false
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.maximumNumberOfLines = DesignTokens.titleMaxLines
        titleLabel.allowsDefaultTighteningForTruncation = false
        addSubview(titleLabel)

        // the line is always reserved so tiles with and without counts align
        tabsLabel.font = .systemFont(ofSize: DesignTokens.tabsFontSize)
        tabsLabel.textColor = .secondaryLabelColor
        tabsLabel.alignment = .center
        tabsLabel.lineBreakMode = .byTruncatingTail
        addSubview(tabsLabel)

        // palette fill: white glyph on a gray circle — the Apple overlay-close
        // badge (notifications, Safari tabs); legible over any snapshot
        let closeConfiguration = NSImage.SymbolConfiguration(pointSize: DesignTokens.closeButtonSymbolSize,
                                                             weight: .semibold)
            .applying(.init(paletteColors: [DesignTokens.overlayGlyphColor,
                                            DesignTokens.overlayCircleColor]))
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                    accessibilityDescription: "Close Window")?
            .withSymbolConfiguration(closeConfiguration)
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = "Close Window"
        closeButton.setAccessibilityLabel("Close Window")
        closeButton.isHidden = true
        addSubview(closeButton)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        // essential actions stay keyboard-reachable (Delete); this mirrors the
        // hover control for VoiceOver users
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Close Window") { [weak self] in
                self?.onCloseRequest?()
                return true
            },
        ])

        applySelectionStyle()
    }

    func configure(item: SwitcherItem, mode: AppearanceMode, preview: NSImage?) {
        self.mode = mode
        metrics = Metrics.metrics(for: mode)
        let tabsText = item.tabCount.map { "\($0) tabs" } ?? ""
        var accessibilityParts = [item.title, item.appName]
        if !tabsText.isEmpty { accessibilityParts.append(tabsText) }
        accessibilityText = accessibilityParts.joined(separator: ", ")
        iconView.image = item.icon
        badgeIconView.image = item.icon
        titleLabel.stringValue = item.title
        tabsLabel.stringValue = tabsText
        setAccessibilityLabel(accessibilityText)
        // a pooled tile may be re-representing another window: any in-flight
        // crossfade belongs to the previous occupant, never the next one
        previewView.layer?.removeAllAnimations()
        setPreview(preview)
        applySelectionStyle()
    }

    /// Applies (or clears) the window preview. While a window has no snapshot
    /// the tile shows a quiet placeholder card under the corner badge, and the first
    /// capture fades in over it. When a fresh capture replaces a cached
    /// snapshot mid-session it crossfades in place — same geometry, no blank
    /// frame, no layout shift. Reduce Motion disables both animations.
    func setPreview(_ image: NSImage?, fadeIn: Bool = false) {
        let hadPreview = hasPreview
        hasPreview = mode == .windowPreviews && image != nil
        let animatable = fadeIn && hasPreview && window != nil && !isHidden
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animatable, hadPreview {
            // cached → fresh: crossfade the layer contents in place
            let crossfade = CATransition()
            crossfade.duration = DesignTokens.previewRefreshFadeDuration
            crossfade.type = .fade
            previewView.layer?.add(crossfade, forKey: "previewRefresh")
            previewView.image = image
            previewView.alphaValue = 1
        } else {
            previewView.image = hasPreview ? image : nil
            if animatable {
                // placeholder → first capture: fade in over the card
                previewView.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = DesignTokens.previewFillInFadeDuration
                    previewView.animator().alphaValue = 1
                }
            } else {
                previewView.alphaValue = 1
            }
        }
        previewView.isHidden = !hasPreview
        badgeIconView.isHidden = mode != .windowPreviews
        needsLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let size = metrics.tileSize
        let contentHeight = metrics.contentHeight
        let contentBox = NSRect(x: DesignTokens.tileLabelInset,
                                y: size.height - DesignTokens.contentTopInset - contentHeight,
                                width: size.width - DesignTokens.tileLabelInset * 2,
                                height: contentHeight)
        // the selection surrounds only the content, concentric with its corner
        // radius; the title zone below stays outside the highlight
        selectionView.frame = contentBox.insetBy(dx: -DesignTokens.selectionPadding,
                                                 dy: -DesignTokens.selectionPadding)
        selectionView.layer?.cornerRadius = mode == .windowPreviews
            ? DesignTokens.previewCornerRadius + DesignTokens.selectionPadding
            : DesignTokens.tileSelectionCornerRadius
        var closeAnchor = contentBox
        if hasPreview {
            // aspect-fit inside the fixed display-aspect container: the whole
            // window stays visible, centered, unused area transparent
            let fitted = fittedImageRect(in: contentBox, imageSize: previewView.image?.size)
            previewView.frame = fitted
            previewShadowView.frame = contentBox
            previewShadowView.layer?.shadowPath = CGPath(
                roundedRect: CGRect(origin: .zero, size: contentBox.size),
                cornerWidth: DesignTokens.previewCornerRadius,
                cornerHeight: DesignTokens.previewCornerRadius, transform: nil)
            // Both overlays belong to the fixed display-aspect canvas, never
            // the source image's fitted bounds.
            closeAnchor = contentBox
            let badge = DesignTokens.previewBadgeSize
            badgeIconView.frame = NSRect(x: contentBox.maxX - badge + DesignTokens.previewOverlayOverlap,
                                         y: contentBox.minY - DesignTokens.previewOverlayOverlap,
                                         width: badge, height: badge)
        } else if mode == .windowPreviews {
            // placeholder card keeps the geometry stable until a snapshot fades in
            placeholderView.frame = contentBox
            closeAnchor = contentBox
            let badge = DesignTokens.previewBadgeSize
            badgeIconView.frame = NSRect(x: contentBox.maxX - badge + DesignTokens.previewOverlayOverlap,
                                         y: contentBox.minY - DesignTokens.previewOverlayOverlap,
                                         width: badge, height: badge)
        } else {
            let iconSize = DesignTokens.largeIconSize
            iconView.frame = NSRect(x: contentBox.midX - iconSize / 2,
                                    y: contentBox.midY - iconSize / 2,
                                    width: iconSize, height: iconSize)
            closeAnchor = iconView.frame
        }
        iconView.isHidden = mode == .windowPreviews
        placeholderView.isHidden = hasPreview || mode == .appIcons
        previewShadowView.isHidden = !hasPreview
        previewOutlineView.isHidden = mode != .windowPreviews
        previewOutlineView.frame = contentBox
        previewOutlineView.layer?.cornerRadius = DesignTokens.previewCornerRadius
        previewOutlineView.layer?.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: contentBox.size),
            cornerWidth: DesignTokens.previewCornerRadius,
            cornerHeight: DesignTokens.previewCornerRadius, transform: nil)
        let labelWidth = size.width - DesignTokens.tileLabelInset * 2
        // the zone is two lines tall; a single-line title centers within it so
        // one- and two-line cards read as the same layout
        let zone = NSRect(x: DesignTokens.tileLabelInset, y: DesignTokens.titleY,
                          width: labelWidth, height: DesignTokens.titleZoneHeight)
        let textHeight = min(titleLabel.cell?.cellSize(forBounds: zone).height
                                 ?? DesignTokens.titleZoneHeight,
                             DesignTokens.titleZoneHeight)
        titleLabel.frame = NSRect(x: zone.minX,
                                  y: zone.minY + ((zone.height - textHeight) / 2).rounded(.down),
                                  width: labelWidth, height: textHeight)
        tabsLabel.frame = NSRect(x: DesignTokens.tileLabelInset, y: DesignTokens.tabsY,
                                 width: labelWidth, height: DesignTokens.tabsHeight)
        // badge-style over the content's top-left corner (Mission Control idiom),
        // clamped inside the tile
        let button = DesignTokens.closeButtonHitSize
        let overlap = DesignTokens.closeButtonBoundaryOverlap
        closeButton.frame = NSRect(x: max(closeAnchor.minX - overlap, 0),
                                   y: min(closeAnchor.maxY - button + overlap, size.height - button),
                                   width: button, height: button)
    }

    private func fittedImageRect(in frame: NSRect, imageSize: NSSize?) -> NSRect {
        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else { return frame }
        let scale = min(frame.width / imageSize.width, frame.height / imageSize.height, 1)
        let fittedSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(x: frame.midX - fittedSize.width / 2,
                      y: frame.midY - fittedSize.height / 2,
                      width: fittedSize.width, height: fittedSize.height)
    }

    private func applySelectionStyle() {
        // neutral rounded-rect selection like the native switcher; semantic color
        // adapts to Dark Mode and Increase Contrast. CGColor resolution must run
        // under this view's effective appearance, whatever thread state says.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let emphasized = isHovered || isTemporarilyActive
            selectionView.layer?.backgroundColor = mode == .windowPreviews
                ? NSColor.clear.cgColor
                : (isSelected
                    ? DesignTokens.selectionFill.cgColor
                    : (emphasized ? DesignTokens.temporaryTargetFill.cgColor : NSColor.clear.cgColor))
            placeholderView.layer?.backgroundColor = DesignTokens.previewPlaceholderFill.cgColor
            if mode == .windowPreviews {
                previewOutlineView.layer?.borderColor = isSelected
                    ? DesignTokens.previewSelectionOutline.cgColor
                    : (emphasized
                        ? DesignTokens.previewEmphasisOutline.cgColor
                        : DesignTokens.previewOutline.cgColor)
                previewOutlineView.layer?.borderWidth = isSelected
                    ? DesignTokens.previewSelectionOutlineWidth
                    : (emphasized
                        ? DesignTokens.previewEmphasisOutlineWidth
                        : DesignTokens.previewOutlineWidth)
                previewOutlineView.layer?.shadowOpacity = 0
            }
        }
        needsLayout = true
    }

    /// Selection color is CGColor-backed; refresh when the appearance flips.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySelectionStyle()
    }

    // MARK: - Hover close control (overlay: never shifts layout)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        closeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        closeButton.isHidden = true
    }

    /// Pooled tiles can be hidden/reused while a stale hover state lingers.
    func resetHoverState() {
        isHovered = false
        closeButton.isHidden = true
    }

    @objc private func closeClicked() {
        onCloseRequest?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
