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
    private var previewIsUnavailable = false

    private let selectionBackgroundView = NSView()
    private let iconView = NSImageView()
    private let previewView = NSImageView()
    /// Carries the snapshot's soft shadow: the shadow path follows the
    /// preview's rounded shape, so no rectangular halo can appear (the clip on
    /// previewView would swallow a shadow set on it directly).
    private let previewShadowView = NSView()
    /// Canvas-aligned outline above the image. It never participates in layout,
    /// so changing state cannot resize or move a card.
    private let cardOutlineView = NSView()
    /// Rounded card shown while a window has no snapshot yet, so the tile's
    /// geometry never jumps when the first capture fades in.
    private let placeholderView = NSView()
    private let unavailableSymbolView = NSImageView()
    private let unavailableLabel = NSTextField(labelWithString: "Preview unavailable")
    private let badgeIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let tabsLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var suppressHoverForRendering = false

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
    var previewCanvasFrameForTesting: NSRect { cardOutlineView.frame }
    var previewImageFrameForTesting: NSRect { previewView.frame }
    var badgeFrameForTesting: NSRect { badgeIconView.frame }
    var closeFrameForTesting: NSRect { closeButton.frame }
    var previewOutlineWidthForTesting: CGFloat { cardOutlineView.layer?.borderWidth ?? 0 }
    var previewOutlineCornerRadiusForTesting: CGFloat {
        cardOutlineView.layer?.cornerRadius ?? 0
    }
    var previewOutlineColorForTesting: NSColor? {
        cardOutlineView.layer?.borderColor.map(NSColor.init(cgColor:)) ?? nil
    }
    var showsCardOutlineForTesting: Bool { !cardOutlineView.isHidden }
    var selectionBackgroundAlphaForTesting: CGFloat {
        selectionBackgroundView.layer?.backgroundColor?.alpha ?? 0
    }
    var showsUnavailableStateForTesting: Bool {
        previewIsUnavailable && !unavailableLabel.isHidden && !unavailableSymbolView.isHidden
    }
    var showsLoadingStateForTesting: Bool {
        !previewIsUnavailable && !hasPreview
            && !unavailableLabel.isHidden && !unavailableSymbolView.isHidden
    }

    /// Tiles are pooled and reconfigured (never recreated per session) so the
    /// panel opens fast even with 100+ windows.
    init() {
        super.init(frame: NSRect(origin: .zero, size: Metrics.appIcons.tileSize))

        selectionBackgroundView.wantsLayer = true
        selectionBackgroundView.layer?.cornerRadius = DesignTokens.iconSelectionCornerRadius
        selectionBackgroundView.layer?.cornerCurve = .continuous
        addSubview(selectionBackgroundView)

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

        unavailableSymbolView.image = NSImage(
            systemSymbolName: "rectangle.slash",
            accessibilityDescription: "Preview unavailable")?
            .withSymbolConfiguration(.init(
                pointSize: DesignTokens.previewUnavailableSymbolSize,
                weight: .regular))
        unavailableSymbolView.contentTintColor = DesignTokens.previewUnavailableSymbolColor
        unavailableSymbolView.imageScaling = .scaleProportionallyDown
        addSubview(unavailableSymbolView)

        unavailableLabel.font = .systemFont(ofSize: DesignTokens.previewUnavailableFontSize)
        unavailableLabel.textColor = .secondaryLabelColor
        unavailableLabel.alignment = .center
        addSubview(unavailableLabel)

        cardOutlineView.wantsLayer = true
        cardOutlineView.layer?.cornerCurve = .continuous
        addSubview(cardOutlineView)

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
        previewIsUnavailable = false
        setPreview(preview)
        applySelectionStyle()
    }

    /// Applies (or clears) the window preview. While a window has no snapshot
    /// the tile shows a labelled loading card under the corner badge, and the first
    /// capture fades in over it. When a fresh capture replaces a cached
    /// snapshot mid-session it crossfades in place — same geometry, no blank
    /// frame, no layout shift. Reduce Motion disables both animations.
    func setPreview(_ image: NSImage?, fadeIn: Bool = false) {
        let hadPreview = hasPreview
        hasPreview = mode == .windowPreviews && image != nil
        if hasPreview {
            previewIsUnavailable = false
        }
        updatePlaceholderContent()
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

    /// Marks a first capture as unavailable without disturbing a cached or
    /// loaded preview. The fixed canvas, badge, title, and outline never move.
    func setPreviewUnavailable() {
        guard mode == .windowPreviews, !hasPreview else { return }
        previewIsUnavailable = true
        updatePlaceholderContent()
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
        selectionBackgroundView.frame = contentBox.insetBy(
            dx: -DesignTokens.iconSelectionPadding,
            dy: -DesignTokens.iconSelectionPadding)
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
            let badge = DesignTokens.previewBadgeSize
            badgeIconView.frame = NSRect(x: contentBox.maxX - badge + DesignTokens.previewOverlayOverlap,
                                         y: contentBox.minY - DesignTokens.previewOverlayOverlap,
                                         width: badge, height: badge)
        } else if mode == .windowPreviews {
            // placeholder card keeps the geometry stable until a snapshot fades in
            placeholderView.frame = contentBox
            let badge = DesignTokens.previewBadgeSize
            badgeIconView.frame = NSRect(x: contentBox.maxX - badge + DesignTokens.previewOverlayOverlap,
                                         y: contentBox.minY - DesignTokens.previewOverlayOverlap,
                                         width: badge, height: badge)
        } else {
            let iconSize = DesignTokens.largeIconSize
            iconView.frame = NSRect(x: contentBox.midX - iconSize / 2,
                                    y: contentBox.midY - iconSize / 2,
                                    width: iconSize, height: iconSize)
        }
        iconView.isHidden = mode == .windowPreviews
        placeholderView.isHidden = hasPreview || mode == .appIcons
        unavailableSymbolView.isHidden = mode != .windowPreviews || hasPreview
        unavailableLabel.isHidden = unavailableSymbolView.isHidden
        if !unavailableSymbolView.isHidden {
            let symbol = DesignTokens.previewUnavailableSymbolSize
            let labelHeight = ceil(unavailableLabel.intrinsicContentSize.height)
            let groupHeight = symbol + DesignTokens.previewUnavailableSpacing + labelHeight
            unavailableSymbolView.frame = NSRect(
                x: contentBox.midX - symbol / 2,
                y: contentBox.midY + groupHeight / 2 - symbol,
                width: symbol,
                height: symbol)
            unavailableLabel.frame = NSRect(
                x: contentBox.minX,
                y: unavailableSymbolView.frame.minY
                    - DesignTokens.previewUnavailableSpacing - labelHeight,
                width: contentBox.width,
                height: labelHeight)
        }
        previewShadowView.isHidden = !hasPreview
        cardOutlineView.isHidden = mode == .appIcons
        cardOutlineView.frame = contentBox
        cardOutlineView.layer?.cornerRadius = DesignTokens.cardCornerRadius
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
        // Unlike the app badge, Close is centered exactly on the fixed
        // canvas's top-left point. Its overlay frame never participates in
        // measurement and intentionally extends beyond the canvas.
        let button = DesignTokens.closeButtonHitSize
        closeButton.frame = NSRect(x: contentBox.minX - button / 2,
                                   y: contentBox.maxY - button / 2,
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
        // Preview states share exactly one canvas outline; App Icons uses only
        // the native-style rounded background. CGColor resolution must run
        // under this view's effective appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let emphasized = isHovered || isTemporarilyActive
            selectionBackgroundView.layer?.backgroundColor = mode == .appIcons
                ? (isSelected
                    ? DesignTokens.iconSelectionFill.cgColor
                    : (emphasized
                        ? DesignTokens.iconEmphasisFill.cgColor
                        : NSColor.clear.cgColor))
                : NSColor.clear.cgColor
            placeholderView.layer?.backgroundColor = DesignTokens.previewPlaceholderFill.cgColor
            unavailableSymbolView.contentTintColor = DesignTokens.previewUnavailableSymbolColor
            cardOutlineView.layer?.borderColor = isSelected
                ? DesignTokens.selectionOutline.cgColor
                : (emphasized
                    ? DesignTokens.previewEmphasisOutline.cgColor
                    : DesignTokens.previewOutline.cgColor)
            cardOutlineView.layer?.borderWidth = isSelected
                ? DesignTokens.selectionOutlineWidth
                : (emphasized
                    ? DesignTokens.previewEmphasisOutlineWidth
                    : DesignTokens.previewOutlineWidth)
        }
        needsLayout = true
    }

    private func updatePlaceholderContent() {
        let text = previewIsUnavailable ? "Preview unavailable" : "Loading preview…"
        let symbol = previewIsUnavailable ? "rectangle.slash" : "ellipsis.rectangle"
        unavailableLabel.stringValue = text
        unavailableSymbolView.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: text)?
            .withSymbolConfiguration(.init(
                pointSize: DesignTokens.previewUnavailableSymbolSize,
                weight: .regular))
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
        guard !suppressHoverForRendering else { return }
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

    /// Offscreen render harness hook. Production visibility continues to be
    /// driven exclusively by pointer hover and the keyboard/VoiceOver action.
    func prepareCloseControlForRendering(visible: Bool) {
        suppressHoverForRendering = true
        isHovered = visible
        closeButton.isHidden = !visible
    }

    /// Allows the document view to preserve the complete overlay hit target
    /// even for the portion intentionally outside this tile's bounds.
    func closeControlHitTest(_ point: NSPoint) -> NSView? {
        guard !closeButton.isHidden, closeButton.frame.contains(point) else { return nil }
        return closeButton
    }

    @objc private func closeClicked() {
        onCloseRequest?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
