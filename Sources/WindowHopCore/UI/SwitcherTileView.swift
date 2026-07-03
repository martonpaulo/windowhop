import AppKit

/// One switcher entry: a large application icon with a compact window title
/// beneath it and an understated tab-count line. Every tile shows its title —
/// entries are identifiable without navigating to them first.
final class SwitcherTileView: NSView {
    static let tileSize = NSSize(width: 108, height: 122)
    private static let iconSize: CGFloat = 76
    private static let selectionInset: CGFloat = 5
    private static let labelInset: CGFloat = 10

    var onClick: (() -> Void)?
    private(set) var accessibilityText = ""

    private let selectionView = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let tabsLabel = NSTextField(labelWithString: "")

    var isSelected = false {
        didSet { applySelectionStyle() }
    }

    /// Tiles are pooled and reconfigured (never recreated per session) so the
    /// panel opens fast even with 100+ windows.
    init() {
        super.init(frame: NSRect(origin: .zero, size: SwitcherTileView.tileSize))

        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 14
        selectionView.layer?.cornerCurve = .continuous
        addSubview(selectionView)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

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

        setAccessibilityElement(true)
        setAccessibilityRole(.button)

        applySelectionStyle()
    }

    func configure(item: SwitcherItem) {
        let tabsText = item.tabCount.map { "\($0) tabs" } ?? ""
        var accessibilityParts = [item.title, item.appName]
        if !tabsText.isEmpty { accessibilityParts.append(tabsText) }
        accessibilityText = accessibilityParts.joined(separator: ", ")
        iconView.image = item.icon
        titleLabel.stringValue = item.title
        tabsLabel.stringValue = tabsText
        setAccessibilityLabel(accessibilityText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let size = SwitcherTileView.tileSize
        let iconSize = SwitcherTileView.iconSize
        selectionView.frame = bounds.insetBy(dx: SwitcherTileView.selectionInset,
                                             dy: SwitcherTileView.selectionInset)
        iconView.frame = NSRect(x: (size.width - iconSize) / 2,
                                y: size.height - 10 - iconSize,
                                width: iconSize, height: iconSize)
        let labelWidth = size.width - SwitcherTileView.labelInset * 2
        titleLabel.frame = NSRect(x: SwitcherTileView.labelInset, y: 24,
                                  width: labelWidth, height: 15)
        tabsLabel.frame = NSRect(x: SwitcherTileView.labelInset, y: 10,
                                 width: labelWidth, height: 13)
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
