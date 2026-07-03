import AppKit

/// One switcher entry in either appearance:
/// - App Icons: a genuinely large application icon dominates the tile.
/// - Window Previews: an aspect-fit window snapshot with the app icon as a
///   corner badge; until (or unless) a preview arrives, the large icon shows.
/// Every tile keeps a compact title and the reserved tab-count line, so tiles
/// never shift as data arrives. Hovering reveals an overlay close control that
/// routes through the same confirmation flow as Delete.
final class SwitcherTileView: NSView {
    struct Metrics {
        let tileSize: NSSize
        let contentHeight: CGFloat // icon or preview area height

        static let appIcons = Metrics(tileSize: NSSize(width: 132, height: 168),
                                      contentHeight: 104)
        static let windowPreviews = Metrics(tileSize: NSSize(width: 248, height: 200),
                                            contentHeight: 136)

        static func metrics(for mode: AppearanceMode) -> Metrics {
            mode == .appIcons ? .appIcons : .windowPreviews
        }
    }

    private static let iconSize: CGFloat = 96
    private static let previewFallbackIconSize: CGFloat = 72
    private static let badgeSize: CGFloat = 30
    private static let selectionInset: CGFloat = 5
    private static let labelInset: CGFloat = 10
    private static let closeButtonSize: CGFloat = 20

    var onClick: (() -> Void)?
    var onCloseRequest: (() -> Void)?
    private(set) var accessibilityText = ""

    private var metrics = Metrics.appIcons
    private var mode = AppearanceMode.appIcons
    private var hasPreview = false

    private let selectionView = NSView()
    private let iconView = NSImageView()
    private let previewView = NSImageView()
    private let badgeIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let tabsLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var trackingArea: NSTrackingArea?

    var isSelected = false {
        didSet { applySelectionStyle() }
    }

    /// Tiles are pooled and reconfigured (never recreated per session) so the
    /// panel opens fast even with 100+ windows.
    init() {
        super.init(frame: NSRect(origin: .zero, size: Metrics.appIcons.tileSize))

        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 14
        selectionView.layer?.cornerCurve = .continuous
        addSubview(selectionView)

        previewView.imageScaling = .scaleProportionallyDown
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = 8
        previewView.layer?.cornerCurve = .continuous
        previewView.layer?.masksToBounds = true
        addSubview(previewView)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        badgeIconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(badgeIconView)

        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.allowsDefaultTighteningForTruncation = false
        addSubview(titleLabel)

        // the line is always reserved so tiles with and without counts align
        tabsLabel.font = .systemFont(ofSize: 9.5)
        tabsLabel.textColor = .secondaryLabelColor
        tabsLabel.alignment = .center
        tabsLabel.lineBreakMode = .byTruncatingTail
        addSubview(tabsLabel)

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                    accessibilityDescription: "Close Window")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
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
        setPreview(preview)
    }

    /// Applies (or clears) the window preview. Missing previews leave the large
    /// icon in place — never a blank tile.
    func setPreview(_ image: NSImage?) {
        hasPreview = mode == .windowPreviews && image != nil
        previewView.image = hasPreview ? image : nil
        previewView.isHidden = !hasPreview
        badgeIconView.isHidden = !hasPreview
        needsLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let size = metrics.tileSize
        let contentHeight = metrics.contentHeight
        let contentTop = size.height - 10
        selectionView.frame = bounds.insetBy(dx: SwitcherTileView.selectionInset,
                                             dy: SwitcherTileView.selectionInset)
        if hasPreview {
            // aspect-fit box; NSImageView letterboxes without distortion
            previewView.frame = NSRect(x: SwitcherTileView.labelInset,
                                       y: contentTop - contentHeight,
                                       width: size.width - SwitcherTileView.labelInset * 2,
                                       height: contentHeight)
            // badge the fitted image, not the letterbox frame, so it hugs the
            // visible snapshot even for very tall or very narrow windows
            let fitted = fittedImageRect(in: previewView.frame, imageSize: previewView.image?.size)
            let badge = SwitcherTileView.badgeSize
            badgeIconView.frame = NSRect(x: min(fitted.maxX - badge + 8, bounds.maxX - badge - 4),
                                         y: max(fitted.minY - 8, 2),
                                         width: badge, height: badge)
        } else {
            let iconSize = mode == .appIcons
                ? SwitcherTileView.iconSize
                : SwitcherTileView.previewFallbackIconSize
            iconView.frame = NSRect(x: (size.width - iconSize) / 2,
                                    y: contentTop - contentHeight + (contentHeight - iconSize) / 2,
                                    width: iconSize, height: iconSize)
        }
        iconView.isHidden = hasPreview
        let labelWidth = size.width - SwitcherTileView.labelInset * 2
        titleLabel.frame = NSRect(x: SwitcherTileView.labelInset, y: 24,
                                  width: labelWidth, height: 15)
        tabsLabel.frame = NSRect(x: SwitcherTileView.labelInset, y: 10,
                                 width: labelWidth, height: 13)
        let button = SwitcherTileView.closeButtonSize
        closeButton.frame = NSRect(x: 9, y: size.height - button - 9,
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
            selectionView.layer?.backgroundColor = isSelected
                ? NSColor.labelColor.withAlphaComponent(0.12).cgColor
                : NSColor.clear.cgColor
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
        closeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
    }

    /// Pooled tiles can be hidden/reused while a stale hover state lingers.
    func resetHoverState() {
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
