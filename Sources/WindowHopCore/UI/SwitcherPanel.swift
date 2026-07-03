import AppKit

/// The switcher: a compact, non-activating panel centered on the active display.
/// One row per window — application icon, window title, optional tab count.
/// No previews, no animation, no search. System materials and semantic colors keep
/// it correct in Light/Dark Mode, Increase Contrast, and Reduce Transparency.
public final class SwitcherPanel: NSPanel {
    public var onItemClicked: ((Int) -> Void)?

    private let effectView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let rowsContainer = FlippedView()
    private var rowViews: [SwitcherRowView] = []
    private var selectedIndex = 0

    private static let rowHeight: CGFloat = 34
    private static let contentPadding: CGFloat = 8
    private static let minWidth: CGFloat = 360
    private static let maxWidth: CGFloat = 640
    private static let maxVisibleRows = 12

    public init() {
        super.init(contentRect: .zero,
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false

        effectView.material = .menu
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        contentView = effectView

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = rowsContainer
        effectView.addSubview(scrollView)

        effectView.setAccessibilityElement(true)
        effectView.setAccessibilityRole(.list)
        effectView.setAccessibilityLabel("WindowHop window switcher")
    }

    public func show(items: [SwitcherItem], selectedIndex: Int) {
        update(items: items, selectedIndex: selectedIndex)
        orderFrontRegardless()
        announceSelection()
        DebugLog.log("panel shown: \(items.count) rows, frame \(frame)")
    }

    public func update(items: [SwitcherItem], selectedIndex index: Int) {
        selectedIndex = index
        rebuildRows(items: items)
        layoutOnActiveScreen(rowCount: items.count)
        applySelection()
    }

    public func select(_ index: Int) {
        selectedIndex = index
        applySelection()
        announceSelection()
    }

    public func hide() {
        orderOut(nil)
    }

    // MARK: - Layout

    private func rebuildRows(items: [SwitcherItem]) {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = items.enumerated().map { index, item in
            let row = SwitcherRowView(item: item)
            row.onClick = { [weak self] in self?.onItemClicked?(index) }
            rowsContainer.addSubview(row)
            return row
        }
    }

    private func layoutOnActiveScreen(rowCount: Int) {
        // the active display is the one with keyboard focus
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let padding = SwitcherPanel.contentPadding
        let widestTitle = rowViews.map { $0.desiredWidth }.max() ?? SwitcherPanel.minWidth
        let rowWidth = min(max(widestTitle, SwitcherPanel.minWidth), SwitcherPanel.maxWidth)
        let visibleRows = min(rowCount, SwitcherPanel.maxVisibleRows)
        let contentHeight = CGFloat(visibleRows) * SwitcherPanel.rowHeight
        let panelSize = NSSize(width: rowWidth + padding * 2, height: contentHeight + padding * 2)

        rowsContainer.frame = NSRect(x: 0, y: 0, width: rowWidth,
                                     height: CGFloat(rowCount) * SwitcherPanel.rowHeight)
        for (index, row) in rowViews.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(index) * SwitcherPanel.rowHeight,
                               width: rowWidth, height: SwitcherPanel.rowHeight)
        }
        scrollView.frame = NSRect(x: padding, y: padding,
                                  width: rowWidth, height: contentHeight)

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(x: visibleFrame.midX - panelSize.width / 2,
                             y: visibleFrame.midY - panelSize.height / 2)
        setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    private func applySelection() {
        for (index, row) in rowViews.enumerated() {
            row.isSelected = index == selectedIndex
        }
        if selectedIndex >= 0, selectedIndex < rowViews.count {
            rowViews[selectedIndex].scrollToVisible(rowViews[selectedIndex].bounds)
        }
    }

    private func announceSelection() {
        guard selectedIndex >= 0, selectedIndex < rowViews.count else { return }
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: rowViews[selectedIndex].accessibilityText,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// NSScrollView document views lay out top-to-bottom when flipped.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
