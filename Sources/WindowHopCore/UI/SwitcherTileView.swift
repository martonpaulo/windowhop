import AppKit

/// A complete visible circle inside a larger pointer target. Drawing the badge
/// explicitly avoids SF Symbol optical bounds being cropped at the canvas edge.
private final class OverlayCloseButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let visible = DesignTokens.closeButtonVisibleSize
        let circleRect = NSRect(x: bounds.midX - visible / 2,
                                y: bounds.midY - visible / 2,
                                width: visible, height: visible)
        DesignTokens.overlayCircleColor.setFill()
        NSBezierPath(ovalIn: circleRect).fill()
        let configuration = NSImage.SymbolConfiguration(
            pointSize: DesignTokens.closeButtonGlyphSize,
            weight: .semibold)
            .applying(.init(paletteColors: [DesignTokens.overlayGlyphColor]))
        guard let glyph = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let glyphSize = glyph.size
        glyph.draw(at: NSPoint(x: bounds.midX - glyphSize.width / 2,
                               y: bounds.midY - glyphSize.height / 2),
                   from: .zero, operation: .sourceOver, fraction: 1)
    }
}

/// A native, dependency-free placeholder that reads as a simplified macOS
/// window. Loading pulses gently; unavailable and permission-blocked states
/// use the same geometry without animation or card-level error copy.
private final class PreviewSkeletonView: NSView {
    enum Variant: Equatable {
        case loading
        case unavailable
    }

    var variant: Variant = .loading {
        didSet {
            needsDisplay = true
            refreshAnimation()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            DesignTokens.previewSkeletonChromeFill.setFill()
            NSRect(x: bounds.minX,
                   y: bounds.maxY - DesignTokens.previewSkeletonTitleBarHeight,
                   width: bounds.width,
                   height: DesignTokens.previewSkeletonTitleBarHeight).fill()

            DesignTokens.previewSkeletonDotFill.setFill()
            let dot = DesignTokens.previewSkeletonDotSize
            for index in 0..<3 {
                let x = DesignTokens.previewSkeletonInset
                    + CGFloat(index) * (dot + DesignTokens.previewSkeletonDotSpacing)
                let y = bounds.maxY - DesignTokens.previewSkeletonTitleBarHeight / 2 - dot / 2
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dot, height: dot)).fill()
            }

            let fractions: [CGFloat]
            switch variant {
            case .loading:
                DesignTokens.previewSkeletonLineFill.setFill()
                fractions = DesignTokens.previewSkeletonLoadingLineFractions
            case .unavailable:
                DesignTokens.previewSkeletonUnavailableLineFill.setFill()
                fractions = DesignTokens.previewSkeletonUnavailableLineFractions
            }
            let availableWidth = bounds.width - DesignTokens.previewSkeletonInset * 2
            var y = bounds.maxY - DesignTokens.previewSkeletonTitleBarHeight
                - DesignTokens.previewSkeletonInset - DesignTokens.previewSkeletonLineHeight
            for fraction in fractions where y >= DesignTokens.previewSkeletonInset {
                let line = NSRect(x: DesignTokens.previewSkeletonInset,
                                  y: y,
                                  width: availableWidth * fraction,
                                  height: DesignTokens.previewSkeletonLineHeight)
                NSBezierPath(roundedRect: line,
                             xRadius: DesignTokens.previewSkeletonLineRadius,
                             yRadius: DesignTokens.previewSkeletonLineRadius).fill()
                y -= DesignTokens.previewSkeletonLineHeight
                    + DesignTokens.previewSkeletonLineSpacing
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshAnimation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func refreshAnimation() {
        layer?.removeAnimation(forKey: "previewSkeletonPulse")
        layer?.opacity = 1
        guard variant == .loading,
              window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = DesignTokens.previewSkeletonMinimumOpacity
        pulse.toValue = 1
        pulse.duration = DesignTokens.previewSkeletonPulseDuration
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(pulse, forKey: "previewSkeletonPulse")
    }

    func stopAnimation() {
        layer?.removeAnimation(forKey: "previewSkeletonPulse")
        layer?.opacity = 1
    }

    var isAnimatingForTesting: Bool {
        layer?.animation(forKey: "previewSkeletonPulse") != nil
    }
}

enum PreviewPresentationState: Equatable {
    case loading
    case permissionUnavailable
    case captureUnavailable
    case loaded
}

/// One switcher entry in either appearance:
/// - App Icons: a genuinely large application icon dominates the tile.
/// - Window Previews: an aspect-fit window snapshot with the app icon as a
///   corner badge; until (or unless) a preview arrives, a quiet fixed-size
///   skeleton remains behind that same corner-aligned badge.
/// Titles and optional metadata use one shared native typography hierarchy.
/// Hovering reveals an overlay close control that
/// routes through the same confirmation flow as Delete.
final class SwitcherTileView: NSView {
    struct Metrics {
        let tileSize: NSSize
        let contentHeight: CGFloat // icon or preview area height

        static func appIcons(showTabCounts: Bool) -> Metrics {
            Metrics(
                tileSize: NSSize(
                    width: DesignTokens.appIconsTileWidth,
                    height: DesignTokens.tileHeight(
                        contentHeight: DesignTokens.appIconsContentHeight,
                        showMetadata: showTabCounts)),
                contentHeight: DesignTokens.appIconsContentHeight)
        }

        /// Preview containers share one fixed canvas shape, so every card is
        /// identical and any window aspect-fits without cropping.
        static func windowPreviews(showTabCounts: Bool) -> Metrics {
            let contentHeight = DesignTokens.previewContentHeight(
                width: DesignTokens.previewsTileWidth - DesignTokens.tileLabelInset * 2)
            return Metrics(
                tileSize: NSSize(width: DesignTokens.previewsTileWidth,
                                 height: DesignTokens.tileHeight(
                                    contentHeight: contentHeight,
                                    showMetadata: showTabCounts)),
                contentHeight: contentHeight)
        }

        static func metrics(for mode: AppearanceMode,
                            showTabCounts: Bool) -> Metrics {
            mode == .appIcons
                ? .appIcons(showTabCounts: showTabCounts)
                : .windowPreviews(showTabCounts: showTabCounts)
        }
    }

    var onClick: (() -> Void)?
    var onCloseRequest: (() -> Void)?
    private(set) var accessibilityText = ""

    private var metrics = Metrics.appIcons(showTabCounts: false)
    private var mode = AppearanceMode.appIcons
    private var previewState = PreviewPresentationState.loading
    private var showTabCounts = false
    private var hasPreview: Bool { previewState == .loaded }

    private let selectionBackgroundView = NSView()
    private let iconView = NSImageView()
    private let previewView = NSImageView()
    /// Carries the snapshot's soft shadow: the shadow path follows the
    /// preview's rounded shape, so no rectangular halo can appear (the clip on
    /// previewView would swallow a shadow set on it directly).
    private let previewShadowView = NSView()
    /// Semantic canvas surface behind loaded, letterboxed, loading, blocked,
    /// and unavailable content. It is always the same fixed geometry.
    private let previewSurfaceView = NSView()
    private let skeletonView = PreviewSkeletonView()
    private let badgeIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let tabsLabel = NSTextField(labelWithString: "")
    private let closeButton = OverlayCloseButton()
    private var trackingArea: NSTrackingArea?
    private var suppressHoverForRendering = false

    var isSelected = false {
        didSet { applySelectionStyle() }
    }

    private var isHovered = false {
        didSet { applySelectionStyle() }
    }

    /// Whether the tile currently shows a window snapshot (test hook for the
    /// stale-state regression coverage; pooled tiles must never carry a
    /// previous window's image).
    var showsPreviewImage: Bool { hasPreview && !previewView.isHidden && previewView.image != nil }
    var previewCanvasFrameForTesting: NSRect { previewSurfaceView.frame }
    var previewImageFrameForTesting: NSRect { previewView.frame }
    var badgeFrameForTesting: NSRect { badgeIconView.frame }
    var closeFrameForTesting: NSRect { closeButton.frame }
    var previewSurfaceColorForTesting: NSColor? {
        guard let color = previewSurfaceView.layer?.backgroundColor else { return nil }
        return NSColor(cgColor: color)
    }
    var selectionBackgroundColorForTesting: NSColor? {
        guard let color = selectionBackgroundView.layer?.backgroundColor else { return nil }
        return NSColor(cgColor: color)
    }
    var selectionBackgroundFrameForTesting: NSRect { selectionBackgroundView.frame }
    var showsCardOutlineForTesting: Bool { false }
    var selectionBackgroundAlphaForTesting: CGFloat {
        selectionBackgroundView.layer?.backgroundColor?.alpha ?? 0
    }
    var showsUnavailableStateForTesting: Bool {
        previewState == .captureUnavailable && !skeletonView.isHidden
    }
    var showsLoadingStateForTesting: Bool {
        previewState == .loading && !skeletonView.isHidden
    }
    var showsPermissionUnavailableStateForTesting: Bool {
        previewState == .permissionUnavailable && !skeletonView.isHidden
    }
    var skeletonIsAnimatingForTesting: Bool { skeletonView.isAnimatingForTesting }
    var metadataIsHiddenForTesting: Bool { tabsLabel.isHidden }
    var titleFrameForTesting: NSRect { titleLabel.frame }
    var metadataFrameForTesting: NSRect { tabsLabel.frame }
    var titleFontForTesting: NSFont? { titleLabel.font }
    var metadataFontForTesting: NSFont? { tabsLabel.font }

    /// Tiles are pooled and reconfigured (never recreated per session) so the
    /// panel opens fast even with 100+ windows.
    init() {
        super.init(frame: NSRect(
            origin: .zero,
            size: Metrics.appIcons(showTabCounts: false).tileSize))

        selectionBackgroundView.wantsLayer = true
        selectionBackgroundView.layer?.cornerRadius = DesignTokens.iconSelectionCornerRadius
        selectionBackgroundView.layer?.cornerCurve = .continuous
        addSubview(selectionBackgroundView)

        previewSurfaceView.wantsLayer = true
        previewSurfaceView.layer?.cornerRadius = DesignTokens.previewCornerRadius
        previewSurfaceView.layer?.cornerCurve = .continuous
        addSubview(previewSurfaceView)

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

        addSubview(skeletonView)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        addSubview(iconView)

        badgeIconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(badgeIconView)

        titleLabel.font = .systemFont(
            ofSize: DesignTokens.titleFontSize,
            weight: DesignTokens.titleFontWeight)
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

        tabsLabel.font = .systemFont(
            ofSize: DesignTokens.metadataFontSize,
            weight: DesignTokens.metadataFontWeight)
        tabsLabel.textColor = .secondaryLabelColor
        tabsLabel.alignment = .center
        tabsLabel.lineBreakMode = .byTruncatingTail
        addSubview(tabsLabel)

        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
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

    func configure(item: SwitcherItem,
                   mode: AppearanceMode,
                   showTabCounts: Bool,
                   preview: NSImage?) {
        self.mode = mode
        self.showTabCounts = showTabCounts
        metrics = Metrics.metrics(for: mode, showTabCounts: showTabCounts)
        let tabsText = item.tabCount.map { "\($0) tabs" } ?? ""
        var accessibilityParts = [item.title, item.appName]
        if showTabCounts, !tabsText.isEmpty { accessibilityParts.append(tabsText) }
        accessibilityText = accessibilityParts.joined(separator: ", ")
        iconView.image = item.icon
        badgeIconView.image = item.icon
        setTypography(title: item.title, metadata: tabsText)
        tabsLabel.isHidden = !showTabCounts
        setAccessibilityLabel(accessibilityText)
        // a pooled tile may be re-representing another window: any in-flight
        // crossfade belongs to the previous occupant, never the next one
        previewView.layer?.removeAllAnimations()
        previewState = .loading
        setPreview(preview)
        applySelectionStyle()
    }

    /// Applies (or clears) the window preview. While a window has no snapshot
    /// the tile shows a quiet loading skeleton under the corner badge, and the first
    /// capture fades in over it. When a fresh capture replaces a cached
    /// snapshot mid-session it crossfades in place — same geometry, no blank
    /// frame, no layout shift. Reduce Motion disables both animations.
    func setPreview(_ image: NSImage?, fadeIn: Bool = false) {
        let hadPreview = hasPreview
        previewState = mode == .windowPreviews && image != nil ? .loaded : .loading
        updateSkeletonPresentation()
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
        previewState = .captureUnavailable
        updateSkeletonPresentation()
        needsLayout = true
    }

    func setPreviewPermissionUnavailable() {
        guard mode == .windowPreviews, !hasPreview else { return }
        previewState = .permissionUnavailable
        updateSkeletonPresentation()
        needsLayout = true
    }

    func setPreviewLoading() {
        guard mode == .windowPreviews, !hasPreview else { return }
        previewState = .loading
        updateSkeletonPresentation()
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
        let selectionPadding = mode == .appIcons
            ? DesignTokens.iconSelectionPadding
            : DesignTokens.previewSelectionPadding
        selectionBackgroundView.frame = contentBox.insetBy(
            dx: -selectionPadding, dy: -selectionPadding)
        selectionBackgroundView.layer?.cornerRadius = mode == .appIcons
            ? DesignTokens.iconSelectionCornerRadius
            : DesignTokens.previewCornerRadius + selectionPadding
        if hasPreview {
            // Aspect-fit inside the fixed display-aspect container: the whole
            // window stays visible and the semantic surface owns letterboxing.
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
            previewSurfaceView.frame = contentBox
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
        previewSurfaceView.frame = contentBox
        previewSurfaceView.isHidden = mode == .appIcons
        skeletonView.frame = contentBox
        skeletonView.isHidden = mode != .windowPreviews || hasPreview
        previewShadowView.isHidden = mode == .appIcons
        previewShadowView.frame = contentBox
        previewShadowView.layer?.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: contentBox.size),
            cornerWidth: DesignTokens.previewCornerRadius,
            cornerHeight: DesignTokens.previewCornerRadius, transform: nil)
        let labelWidth = size.width - DesignTokens.tileLabelInset * 2
        // the zone is two lines tall; a single-line title centers within it so
        // one- and two-line cards read as the same layout
        let zone = NSRect(
            x: DesignTokens.tileLabelInset,
            y: DesignTokens.titleY(showMetadata: showTabCounts),
                          width: labelWidth, height: DesignTokens.titleZoneHeight)
        let textHeight = min(titleLabel.cell?.cellSize(forBounds: zone).height
                                 ?? DesignTokens.titleZoneHeight,
                             DesignTokens.titleZoneHeight)
        titleLabel.frame = NSRect(x: zone.minX,
                                  y: zone.minY + ((zone.height - textHeight) / 2).rounded(.down),
                                  width: labelWidth, height: textHeight)
        tabsLabel.frame = NSRect(
            x: DesignTokens.tileLabelInset,
            y: DesignTokens.labelBottomInset,
            width: labelWidth,
            height: DesignTokens.metadataHeight)
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
        // Both appearances use one background plate for selection; previews
        // never stack a neutral border and a focus ring.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let emphasized = isHovered
            let fill: NSColor
            if mode == .appIcons {
                fill = isSelected
                    ? DesignTokens.iconSelectionFill
                    : (emphasized ? DesignTokens.iconEmphasisFill : .clear)
            } else {
                fill = isSelected
                    ? DesignTokens.previewSelectionFill
                    : (emphasized ? DesignTokens.previewEmphasisFill : .clear)
            }
            selectionBackgroundView.layer?.backgroundColor = fill.cgColor
            previewSurfaceView.layer?.backgroundColor = DesignTokens.previewSurfaceFill.cgColor
        }
        needsLayout = true
    }

    private func updateSkeletonPresentation() {
        switch previewState {
        case .loading:
            skeletonView.variant = .loading
        case .permissionUnavailable, .captureUnavailable:
            skeletonView.variant = .unavailable
        case .loaded:
            skeletonView.stopAnimation()
        }
    }

    private func setTypography(title: String, metadata: String) {
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.alignment = .center
        titleParagraph.lineBreakMode = .byWordWrapping
        titleLabel.attributedStringValue = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: DesignTokens.titleFontSize,
                    weight: DesignTokens.titleFontWeight),
                .foregroundColor: NSColor.labelColor,
                .kern: DesignTokens.titleLetterSpacing,
                .paragraphStyle: titleParagraph,
            ])

        let metadataParagraph = NSMutableParagraphStyle()
        metadataParagraph.alignment = .center
        metadataParagraph.lineBreakMode = .byTruncatingTail
        tabsLabel.attributedStringValue = NSAttributedString(
            string: metadata,
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: DesignTokens.metadataFontSize,
                    weight: DesignTokens.metadataFontWeight),
                .foregroundColor: NSColor.secondaryLabelColor,
                .kern: DesignTokens.metadataLetterSpacing,
                .paragraphStyle: metadataParagraph,
            ])
    }

    func refreshMotionPreference() {
        skeletonView.refreshAnimation()
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

    /// The exposed AXButton role promises a standard Press action, so assistive
    /// technology must reach the same activation path as a pointer click.
    /// Apple: Implementing Accessibility for Custom Controls.
    override func accessibilityPerformPress() -> Bool {
        guard let onClick else { return false }
        onClick()
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
