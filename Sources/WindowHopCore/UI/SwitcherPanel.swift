import AppKit

/// The switcher: a compact, non-activating panel centered on the active display.
/// A single horizontal strip of large application icons — one tile per window,
/// each with its title. No previews, no animation, no search. System materials
/// and semantic colors keep it correct in Light/Dark Mode, Increase Contrast,
/// and Reduce Transparency; there is no theme or icon-size setting.
public final class SwitcherPanel: NSPanel {
    public var onItemClicked: ((Int) -> Void)?

    private let effectView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let tilesContainer = NSView()
    /// Pooled tiles, reconfigured in place; index i shows item i.
    private var tilePool: [SwitcherTileView] = []
    private var visibleTileCount = 0
    private var selectedIndex = 0

    private static let contentPadding: CGFloat = 12

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
        effectView.layer?.cornerRadius = 20
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        contentView = effectView

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = tilesContainer
        effectView.addSubview(scrollView)

        effectView.setAccessibilityElement(true)
        effectView.setAccessibilityRole(.list)
        effectView.setAccessibilityLabel("WindowHop window switcher")

        // pre-warm the tile pool off the first-trigger latency path; tiles beyond
        // this grow the pool once and are then reused forever
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            while self.tilePool.count < 24 {
                let tile = SwitcherTileView()
                tile.isHidden = true
                self.tilesContainer.addSubview(tile)
                self.tilePool.append(tile)
            }
        }
    }

    public func show(items: [SwitcherItem], selectedIndex: Int) {
        update(items: items, selectedIndex: selectedIndex)
        orderFrontRegardless()
        announceSelection()
        DebugLog.log("panel shown: \(items.count) tiles, frame \(frame)")
    }

    public func update(items: [SwitcherItem], selectedIndex index: Int) {
        selectedIndex = index
        let rebuildStart = CFAbsoluteTimeGetCurrent()
        rebuildTiles(items: items)
        let layoutStart = CFAbsoluteTimeGetCurrent()
        layoutOnActiveScreen(tileCount: items.count)
        let selectStart = CFAbsoluteTimeGetCurrent()
        applySelection()
        DebugLog.log("panel update: rebuild \(String(format: "%.1f", (layoutStart - rebuildStart) * 1000))ms, "
            + "layout \(String(format: "%.1f", (selectStart - layoutStart) * 1000))ms, "
            + "select \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - selectStart) * 1000))ms")
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

    private func rebuildTiles(items: [SwitcherItem]) {
        while tilePool.count < items.count {
            let tile = SwitcherTileView()
            tilesContainer.addSubview(tile)
            tilePool.append(tile)
        }
        for (index, tile) in tilePool.enumerated() {
            if index < items.count {
                tile.configure(item: items[index])
                tile.onClick = { [weak self] in self?.onItemClicked?(index) }
                tile.isHidden = false
            } else {
                tile.isHidden = true
            }
        }
        visibleTileCount = items.count
    }

    private func layoutOnActiveScreen(tileCount: Int) {
        // the active display is the one with keyboard focus
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let padding = SwitcherPanel.contentPadding
        let tileSize = SwitcherTileView.tileSize

        tilesContainer.frame = NSRect(x: 0, y: 0,
                                      width: CGFloat(tileCount) * tileSize.width,
                                      height: tileSize.height)
        for (index, tile) in tilePool.prefix(tileCount).enumerated() {
            tile.frame = NSRect(x: CGFloat(index) * tileSize.width, y: 0,
                                width: tileSize.width, height: tileSize.height)
        }

        // the strip stays a single row; when it can't fit, it scrolls horizontally
        // and tiles keep their large size (never shrunk into thumbnails)
        let visibleFrame = screen.visibleFrame
        let maxStripWidth = visibleFrame.width * 0.88 - padding * 2
        let stripWidth = min(CGFloat(tileCount) * tileSize.width, maxStripWidth)
        scrollView.frame = NSRect(x: padding, y: padding,
                                  width: stripWidth, height: tileSize.height)

        let panelSize = NSSize(width: stripWidth + padding * 2,
                               height: tileSize.height + padding * 2)
        let origin = NSPoint(x: visibleFrame.midX - panelSize.width / 2,
                             y: visibleFrame.midY - panelSize.height / 2)
        setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    private func applySelection() {
        for (index, tile) in tilePool.prefix(visibleTileCount).enumerated() {
            tile.isSelected = index == selectedIndex
        }
        if selectedIndex >= 0, selectedIndex < visibleTileCount {
            tilePool[selectedIndex].scrollToVisible(tilePool[selectedIndex].bounds)
        }
    }

    private func announceSelection() {
        guard selectedIndex >= 0, selectedIndex < visibleTileCount else { return }
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: tilePool[selectedIndex].accessibilityText,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
