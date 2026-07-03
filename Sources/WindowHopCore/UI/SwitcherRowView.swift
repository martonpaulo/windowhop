import AppKit

/// One switcher entry: app icon, window title, optional "N tabs" hint.
/// The title is always visible, not only for the selected row.
final class SwitcherRowView: NSView {
    var onClick: (() -> Void)?
    let accessibilityText: String

    private let selectionView = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let tabsLabel = NSTextField(labelWithString: "")

    private static let iconSize: CGFloat = 22
    private static let horizontalInset: CGFloat = 6
    private static let innerPadding: CGFloat = 8

    var isSelected = false {
        didSet { applySelectionStyle() }
    }

    /// Width the row wants so the title is not truncated, panel limits permitting.
    let desiredWidth: CGFloat

    init(item: SwitcherItem) {
        let tabsText = item.tabCount.map { "\($0) tabs" } ?? ""
        var accessibilityParts = [item.title, item.appName]
        if !tabsText.isEmpty { accessibilityParts.append(tabsText) }
        accessibilityText = accessibilityParts.joined(separator: ", ")

        titleLabel.stringValue = item.title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.allowsDefaultTighteningForTruncation = false
        tabsLabel.stringValue = tabsText
        tabsLabel.font = .systemFont(ofSize: 11)

        let titleWidth = ceil(titleLabel.intrinsicContentSize.width)
        let tabsWidth = tabsText.isEmpty ? 0 : ceil(tabsLabel.intrinsicContentSize.width) + SwitcherRowView.innerPadding
        desiredWidth = SwitcherRowView.horizontalInset * 2 + SwitcherRowView.innerPadding * 3
            + SwitcherRowView.iconSize + titleWidth + tabsWidth

        super.init(frame: .zero)

        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 8
        selectionView.layer?.cornerCurve = .continuous
        addSubview(selectionView)

        iconView.image = item.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(tabsLabel)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityText)

        applySelectionStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let inset = SwitcherRowView.horizontalInset
        let padding = SwitcherRowView.innerPadding
        let iconSize = SwitcherRowView.iconSize
        selectionView.frame = bounds.insetBy(dx: inset, dy: 2)
        iconView.frame = NSRect(x: inset + padding,
                                y: (bounds.height - iconSize) / 2,
                                width: iconSize, height: iconSize)
        // +3: intrinsicContentSize slightly undermeasures at small sizes, clipping the last glyph
        let tabsWidth = tabsLabel.stringValue.isEmpty ? 0 : ceil(tabsLabel.intrinsicContentSize.width) + 3
        let tabsX = bounds.width - inset - padding - tabsWidth
        tabsLabel.frame = NSRect(x: tabsX,
                                 y: (bounds.height - tabsLabel.intrinsicContentSize.height) / 2,
                                 width: tabsWidth, height: tabsLabel.intrinsicContentSize.height)
        let titleX = iconView.frame.maxX + padding
        let titleMaxX = tabsWidth > 0 ? tabsX - padding : bounds.width - inset - padding
        titleLabel.frame = NSRect(x: titleX,
                                  y: (bounds.height - titleLabel.intrinsicContentSize.height) / 2,
                                  width: max(0, titleMaxX - titleX),
                                  height: titleLabel.intrinsicContentSize.height)
    }

    private func applySelectionStyle() {
        selectionView.layer?.backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.cgColor
            : NSColor.clear.cgColor
        titleLabel.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
        tabsLabel.textColor = isSelected
            ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.75)
            : .secondaryLabelColor
        needsLayout = true
    }

    /// Selection colors are CGColor-backed; refresh them when the appearance flips.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applySelectionStyle()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
