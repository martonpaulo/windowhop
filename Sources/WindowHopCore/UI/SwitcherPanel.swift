import AppKit

/// The switcher: a compact, non-activating panel centered on the active display.
/// A single horizontal strip of tiles — one per window — in either App Icons or
/// Window Previews appearance. No animation, no search, no theme options. System
/// materials and semantic colors keep it correct in Light/Dark Mode, Increase
/// Contrast, and Reduce Transparency.
public final class SwitcherPanel: NSPanel {
    public var onItemClicked: ((Int) -> Void)?
    /// Hover close control on a tile; routes through the same confirmation as Delete.
    public var onItemCloseRequested: ((Int) -> Void)?
    /// The panel-chrome gear control (and ⌘, while a session is open).
    public var onSettingsRequested: (() -> Void)?

    private let effectView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let tilesContainer = NSView()
    private let settingsButton = NSButton()
    private var panelTrackingArea: NSTrackingArea?
    /// Pooled tiles, reconfigured in place; index i shows item i.
    private var tilePool: [SwitcherTileView] = []
    private var visibleTileCount = 0
    private var selectedIndex = 0
    private var mode = AppearanceMode.appIcons
    private var itemIds: [AnyHashable] = []
    /// Grid geometry of the current layout, for 2D arrow-key navigation.
    public private(set) var columnsPerRow = 1

    private static let contentPadding: CGFloat = 12

    /// The preview area a tile offers in Window Previews mode, for capture sizing.
    public static var previewContentSize: NSSize {
        let metrics = SwitcherTileView.Metrics.windowPreviews
        return NSSize(width: metrics.tileSize.width - 20, height: metrics.contentHeight)
    }

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
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = tilesContainer
        effectView.addSubview(scrollView)

        // panel-chrome settings control: revealed while the pointer is inside the
        // panel; always present for accessibility, and ⌘, works without a pointer
        settingsButton.image = NSImage(systemSymbolName: "gearshape.fill",
                                       accessibilityDescription: "WindowHop Settings")?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
        settingsButton.isBordered = false
        settingsButton.imagePosition = .imageOnly
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.target = self
        settingsButton.action = #selector(settingsClicked)
        settingsButton.toolTip = "WindowHop Settings (⌘,)"
        settingsButton.setAccessibilityLabel("WindowHop Settings")
        settingsButton.alphaValue = 0
        effectView.addSubview(settingsButton)

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
        DebugLog.log("panel shown: \(items.count) tiles (\(mode.rawValue)), frame \(frame)")
    }

    /// Re-presents the panel after a confirmation dialog hid it.
    public func presentAgain() {
        orderFrontRegardless()
    }

    public func update(items: [SwitcherItem], selectedIndex index: Int) {
        mode = Preferences.shared.appearanceMode
        selectedIndex = index
        itemIds = items.map { $0.id }
        rebuildTiles(items: items)
        layoutOnActiveScreen(tileCount: items.count)
        applySelection()
    }

    public func select(_ index: Int) {
        selectedIndex = index
        applySelection()
        announceSelection()
    }

    /// A fresh preview arrived for a window in the current session; the tile
    /// crossfades to it (imperceptible when the content is unchanged).
    public func updatePreview(id: AnyHashable, image: NSImage) {
        guard let index = itemIds.firstIndex(of: id), index < visibleTileCount else { return }
        tilePool[index].setPreview(image, animated: true)
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
                let item = items[index]
                tile.configure(item: item, mode: mode,
                               preview: PreviewProvider.shared.cachedPreview(for: item.id))
                tile.onClick = { [weak self] in self?.onItemClicked?(index) }
                tile.onCloseRequest = { [weak self] in self?.onItemCloseRequested?(index) }
                tile.resetHoverState()
                tile.isHidden = false
            } else {
                tile.resetHoverState()
                tile.isHidden = true
            }
        }
        visibleTileCount = items.count
    }

    private func layoutOnActiveScreen(tileCount: Int) {
        // the active display is the one with keyboard focus
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let padding = SwitcherPanel.contentPadding
        let tileSize = SwitcherTileView.Metrics.metrics(for: mode).tileSize
        let visibleFrame = screen.visibleFrame

        // tiles wrap into rows instead of scrolling horizontally (the AltTab
        // layout model); tiles never shrink. Only an extreme window count
        // exceeds the height budget and falls back to vertical scrolling.
        let maxGridWidth = visibleFrame.width * 0.88 - padding * 2
        let columns = max(1, min(tileCount, Int(maxGridWidth / tileSize.width)))
        let rows = tileCount == 0 ? 1 : Int(ceil(Double(tileCount) / Double(columns)))
        columnsPerRow = columns

        let gridWidth = CGFloat(min(tileCount, columns)) * tileSize.width
        let gridHeight = CGFloat(rows) * tileSize.height
        tilesContainer.frame = NSRect(x: 0, y: 0, width: gridWidth, height: gridHeight)
        for (index, tile) in tilePool.prefix(tileCount).enumerated() {
            let column = index % columns
            let row = index / columns
            tile.frame = NSRect(x: CGFloat(column) * tileSize.width,
                                y: CGFloat(rows - 1 - row) * tileSize.height,
                                width: tileSize.width, height: tileSize.height)
        }

        let maxVisibleRows = max(1, Int((visibleFrame.height * 0.85 - padding * 2) / tileSize.height))
        let visibleRows = min(rows, maxVisibleRows)
        scrollView.frame = NSRect(x: padding, y: padding,
                                  width: gridWidth,
                                  height: CGFloat(visibleRows) * tileSize.height)
        // start reading from the first row (top of the grid)
        tilesContainer.scroll(NSPoint(x: 0, y: max(0, gridHeight - scrollView.frame.height)))

        let panelSize = NSSize(width: gridWidth + padding * 2,
                               height: scrollView.frame.height + padding * 2)
        settingsButton.frame = NSRect(x: panelSize.width - 32, y: panelSize.height - 32,
                                      width: 24, height: 24)
        let origin = NSPoint(x: visibleFrame.midX - panelSize.width / 2,
                             y: visibleFrame.midY - panelSize.height / 2)
        setFrame(NSRect(origin: origin, size: panelSize), display: true)
        refreshPanelTrackingArea()
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

    // MARK: - Panel hover (settings control visibility)

    private func refreshPanelTrackingArea() {
        if let panelTrackingArea {
            effectView.removeTrackingArea(panelTrackingArea)
        }
        let area = NSTrackingArea(rect: effectView.bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        effectView.addTrackingArea(area)
        panelTrackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) {
        settingsButton.alphaValue = 1
    }

    override public func mouseExited(with event: NSEvent) {
        settingsButton.alphaValue = 0
    }

    @objc private func settingsClicked() {
        onSettingsRequested?()
    }
}
