import AppKit

/// The dwell result shown entirely inside WindowHop. It presents the latest
/// snapshot at a larger size without touching application focus or window order.
final class ExpandedPreviewView: NSView {
    private let selectionPlate = NSView()
    private let surfaceView = NSView()
    private let imageView = NSImageView()
    private let badgeView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        selectionPlate.wantsLayer = true
        selectionPlate.layer?.cornerCurve = .continuous
        addSubview(selectionPlate)

        surfaceView.wantsLayer = true
        surfaceView.layer?.cornerCurve = .continuous
        addSubview(surfaceView)

        imageView.imageScaling = .scaleProportionallyDown
        imageView.wantsLayer = true
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        addSubview(imageView)

        badgeView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(badgeView)

        titleLabel.font = .systemFont(ofSize: DesignTokens.titleFontSize,
                                      weight: DesignTokens.titleFontWeight)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Expanded window preview")
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The snapshot's own size, which the panel's canvas takes its shape from.
    var imageSize: CGSize? { imageView.image?.size }

    func configure(item: SwitcherItem, image: NSImage) {
        imageView.image = image
        updateMetadata(item: item)
    }

    /// Refreshes everything but the snapshot, so a metadata-only store refresh
    /// keeps the image that is already on screen.
    func updateMetadata(item: SwitcherItem) {
        badgeView.image = item.icon
        titleLabel.stringValue = item.title
        setAccessibilityValue("Expanded preview of \(item.title), \(item.appName)")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let titleHeight = DesignTokens.expandedPreviewTitleHeight
        let canvas = NSRect(x: DesignTokens.previewSelectionPadding,
                            y: titleHeight + DesignTokens.previewSelectionPadding,
                            width: bounds.width - DesignTokens.previewSelectionPadding * 2,
                            height: bounds.height - titleHeight
                                - DesignTokens.previewSelectionPadding * 2)
        selectionPlate.frame = canvas.insetBy(
            dx: -DesignTokens.previewSelectionPadding,
            dy: -DesignTokens.previewSelectionPadding)
        selectionPlate.layer?.cornerRadius = DesignTokens.expandedPreviewCornerRadius
            + DesignTokens.previewSelectionPadding
        surfaceView.frame = canvas
        surfaceView.layer?.cornerRadius = DesignTokens.expandedPreviewCornerRadius

        if let imageSize = imageView.image?.size,
           imageSize.width > 0, imageSize.height > 0 {
            let scale = min(canvas.width / imageSize.width,
                            canvas.height / imageSize.height)
            let fitted = NSSize(width: imageSize.width * scale,
                                height: imageSize.height * scale)
            imageView.frame = NSRect(x: canvas.midX - fitted.width / 2,
                                     y: canvas.midY - fitted.height / 2,
                                     width: fitted.width, height: fitted.height)
        } else {
            imageView.frame = canvas
        }
        imageView.layer?.cornerRadius = DesignTokens.expandedPreviewCornerRadius

        let badge = DesignTokens.expandedPreviewBadgeSize
        badgeView.frame = NSRect(
            x: canvas.maxX - badge + DesignTokens.expandedPreviewBadgeInset,
            y: canvas.minY - DesignTokens.expandedPreviewBadgeInset,
            width: badge, height: badge)
        titleLabel.frame = NSRect(x: 0, y: 0,
                                  width: bounds.width,
                                  height: titleHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            selectionPlate.layer?.backgroundColor = DesignTokens.previewSelectionFill.cgColor
            surfaceView.layer?.backgroundColor = DesignTokens.previewSurfaceFill.cgColor
        }
    }
}
