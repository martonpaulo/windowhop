import AppKit

/// Every size, inset, radius, and font size the switcher UI uses, in one place.
/// Tuned against the native macOS ⌘⇥ switcher's proportions. Views never hardcode
/// dimensions — change a token here and every surface follows.
enum DesignTokens {
    // MARK: Panel chrome
    static let panelPadding: CGFloat = 14
    static let panelCornerRadius: CGFloat = 22
    /// The grid may use up to this fraction of the screen's width/height.
    static let panelMaxWidthFraction: CGFloat = 0.88
    static let panelMaxHeightFraction: CGFloat = 0.85
    /// The panel Settings control (top-right corner), matched to the tile close
    /// control so the two overlay buttons read as one family, on one inset grid.
    static let chromeButtonSize: CGFloat = 26
    static let chromeButtonSymbolSize: CGFloat = 19
    static let overlayInset: CGFloat = 8

    // MARK: Tiles (both appearances)
    static let tileSelectionCornerRadius: CGFloat = 16
    static let tileSelectionInset: CGFloat = 5
    static let tileLabelInset: CGFloat = 10
    static let titleFontSize: CGFloat = 13
    static let tabsFontSize: CGFloat = 11
    static let titleHeight: CGFloat = 18
    static let tabsHeight: CGFloat = 16
    static let titleY: CGFloat = 25
    static let tabsY: CGFloat = 7
    static let contentTopInset: CGFloat = 10

    // MARK: App Icons appearance
    static let appIconsTileSize = NSSize(width: 136, height: 176)
    static let appIconsContentHeight: CGFloat = 104
    static let largeIconSize: CGFloat = 96

    // MARK: Window Previews appearance
    static let previewsTileSize = NSSize(width: 220, height: 186)
    static let previewsContentHeight: CGFloat = 114
    static let previewFallbackIconSize: CGFloat = 72
    static let previewCornerRadius: CGFloat = 8
    /// The app icon badged onto a snapshot — large enough to identify at a glance.
    static let previewBadgeSize: CGFloat = 40
    static let previewBadgeOutset: CGFloat = 8

    // MARK: Overlay close control
    static let closeButtonSize: CGFloat = 26
    static let closeButtonSymbolSize: CGFloat = 20
}
