import AppKit

/// The switcher: a compact, non-activating panel centered on the active display.
/// A fixed-size grid of tiles — one per window — in either App Icons or Window
/// Previews appearance. No search or theme options. System
/// materials and semantic colors keep it correct in Light/Dark Mode, Increase
/// Contrast, and Reduce Transparency.
public final class SwitcherPanel: NSPanel {
    public var onItemClicked: ((Int) -> Void)?
    /// Hover close control on a tile; routes through the same confirmation as Delete.
    public var onItemCloseRequested: ((Int) -> Void)?
    /// The panel-chrome gear control (and ⌘, while a session is open).
    public var onSettingsRequested: (() -> Void)?

    /// Transparent overflow host. The visible panel occupies only
    /// `panelBackgroundView`; global controls may extend into the host without
    /// changing the panel's internal layout.
    private let hostView = NSView()
    private var panelBackgroundView: NSView!
    /// Everything inside the visible panel background (the preview grid).
    private let chromeView = NSView()
    private let scrollView = NSScrollView()
    private let tilesContainer = NSView()
    private let settingsButton = NSButton()
    /// Pooled tiles, reconfigured in place; index i shows item i.
    private var tilePool: [SwitcherTileView] = []
    private var visibleTileCount = 0
    private var selectedIndex = 0
    private var mode = AppearanceMode.appIcons
    private var itemIds: [AnyHashable] = []
    private var temporarilyActiveID: AnyHashable?
    /// Grid geometry of the current layout, for 2D arrow-key navigation.
    public private(set) var columnsPerRow = 1

    /// The preview area a tile offers in Window Previews mode, for capture sizing.
    public static var previewContentSize: NSSize {
        let metrics = SwitcherTileView.Metrics.metrics(for: .windowPreviews)
        return NSSize(width: metrics.tileSize.width - DesignTokens.tileLabelInset * 2,
                      height: metrics.contentHeight)
    }

    /// `rasterizableBackground` is for the offscreen render harness only: the
    /// macOS 26 glass background cannot be rasterized with cacheDisplay (it
    /// draws empty), so layout renders use the visual-effect fallback instead.
    public init(rasterizableBackground: Bool = false) {
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

        // The native switcher's background. On macOS 26+ that is the system
        // glass material (NSGlassEffectView — blur, vibrancy, and edge
        // treatment come from AppKit, never a hardcoded color); older systems
        // fall back to the closest visual-effect material. Both respect
        // Reduce Transparency and Increase Contrast automatically.
        chromeView.autoresizingMask = [.width, .height]
        panelBackgroundView = Self.makeBackgroundView(wrapping: chromeView,
                                                      rasterizable: rasterizableBackground)
        hostView.addSubview(panelBackgroundView)
        contentView = hostView

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = tilesContainer
        chromeView.addSubview(scrollView)

        // Global panel action: always visible, overlaid in the top-right, and
        // never measured as part of the preview grid.
        settingsButton.image = NSImage(systemSymbolName: "gearshape.circle.fill",
                                       accessibilityDescription: "WindowHop Settings")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: DesignTokens.chromeButtonSymbolSize,
                                                                  weight: .semibold)
                .applying(.init(paletteColors: [DesignTokens.overlayGlyphColor,
                                                DesignTokens.overlayCircleColor])))
        settingsButton.isBordered = false
        settingsButton.imagePosition = .imageOnly
        settingsButton.target = self
        settingsButton.action = #selector(settingsClicked)
        settingsButton.toolTip = "WindowHop Settings (⌘,)"
        settingsButton.setAccessibilityLabel("WindowHop Settings")
        settingsButton.alphaValue = 1
        hostView.addSubview(settingsButton)

        chromeView.setAccessibilityElement(true)
        chromeView.setAccessibilityRole(.list)
        chromeView.setAccessibilityLabel("WindowHop window switcher")

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

    /// The panel background: system glass on macOS 26+, the closest
    /// visual-effect material before that.
    private static func makeBackgroundView(wrapping content: NSView,
                                           rasterizable: Bool) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !rasterizable {
            let glass = NSGlassEffectView()
            glass.cornerRadius = DesignTokens.panelCornerRadius
            glass.contentView = content
            return glass
        }
        #endif
        let effectView = NSVisualEffectView()
        effectView.material = DesignTokens.panelMaterial
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = DesignTokens.panelCornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        content.frame = effectView.bounds
        effectView.addSubview(content)
        return effectView
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

    /// The window currently shown behind the switcher may differ briefly from
    /// the highlighted target while rapid navigation is settling.
    public func setTemporarilyActive(id: AnyHashable?) {
        temporarilyActiveID = id
        for (index, tile) in tilePool.prefix(visibleTileCount).enumerated() {
            tile.isTemporarilyActive = itemIds[index] == id
        }
    }

    /// A capture arrived for a window in the open session: fill in tiles that
    /// had no snapshot, or crossfade a cached snapshot to the fresh one.
    /// Delivery is keyed by the window's stable id — never by tile position —
    /// so a preview can never land on another window's card.
    public func updatePreview(id: AnyHashable, image: NSImage) {
        guard let index = itemIds.firstIndex(of: id), index < visibleTileCount else { return }
        tilePool[index].setPreview(image, fadeIn: true)
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
                tile.isTemporarilyActive = item.id == temporarilyActiveID
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
        let padding = DesignTokens.panelPadding
        let spacing = DesignTokens.tileSpacing
        let tileSize = SwitcherTileView.Metrics.metrics(for: mode).tileSize
        let visibleFrame = screen.visibleFrame

        // tiles wrap into rows instead of scrolling horizontally (the AltTab
        // layout model); tiles never shrink. Only an extreme window count
        // exceeds the height budget and falls back to vertical scrolling.
        let maxGridWidth = visibleFrame.width * DesignTokens.panelMaxWidthFraction - padding * 2
        let columns = max(1, min(tileCount,
            Int((maxGridWidth + spacing) / (tileSize.width + spacing))))
        let rows = tileCount == 0 ? 1 : Int(ceil(Double(tileCount) / Double(columns)))
        columnsPerRow = columns

        let visibleColumns = min(tileCount, columns)
        let gridWidth = CGFloat(visibleColumns) * tileSize.width
            + CGFloat(max(0, visibleColumns - 1)) * spacing
        let gridHeight = CGFloat(rows) * tileSize.height
        tilesContainer.frame = NSRect(x: 0, y: 0, width: gridWidth, height: gridHeight)
        for (index, tile) in tilePool.prefix(tileCount).enumerated() {
            let column = index % columns
            let row = index / columns
            // a partial row is centered, like the native switcher — never left-ragged
            let tilesInRow = min(columns, tileCount - row * columns)
            let rowWidth = CGFloat(tilesInRow) * tileSize.width
                + CGFloat(max(0, tilesInRow - 1)) * spacing
            let rowOffset = (gridWidth - rowWidth) / 2
            tile.frame = NSRect(x: rowOffset + CGFloat(column) * (tileSize.width + spacing),
                                y: CGFloat(rows - 1 - row) * tileSize.height,
                                width: tileSize.width, height: tileSize.height)
        }

        let maxVisibleRows = max(1, Int((visibleFrame.height * DesignTokens.panelMaxHeightFraction
            - padding * 2) / tileSize.height))
        let visibleRows = min(rows, maxVisibleRows)
        scrollView.frame = NSRect(x: padding, y: padding,
                                  width: gridWidth,
                                  height: CGFloat(visibleRows) * tileSize.height)
        // start reading from the first row (top of the grid)
        tilesContainer.scroll(NSPoint(x: 0, y: max(0, gridHeight - scrollView.frame.height)))

        let panelSize = NSSize(width: gridWidth + padding * 2,
                               height: scrollView.frame.height + padding * 2)
        panelBackgroundView.frame = NSRect(origin: .zero, size: panelSize)

        // Center the complete hit target on the visible panel's outer corner.
        // The transparent host is larger only to keep that outside half visible;
        // the panel background and its preview layout retain their exact size.
        let controlSize = DesignTokens.chromeButtonHitSize
        let overflow = controlSize / 2
        settingsButton.frame = NSRect(x: panelSize.width - overflow,
                                      y: panelSize.height - overflow,
                                      width: controlSize, height: controlSize)
        let hostSize = NSSize(width: panelSize.width + overflow,
                              height: panelSize.height + overflow)
        let origin = NSPoint(x: visibleFrame.midX - panelSize.width / 2,
                             y: visibleFrame.midY - panelSize.height / 2)
        setFrame(NSRect(origin: origin, size: hostSize), display: true)
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

    /// Test hook: whether the tile at `index` currently shows a snapshot image
    /// (regression coverage for preview/window association).
    func tileShowsPreviewForTesting(at index: Int) -> Bool {
        index >= 0 && index < visibleTileCount && tilePool[index].showsPreviewImage
    }

    func tileFrameForTesting(at index: Int) -> NSRect? {
        index >= 0 && index < visibleTileCount ? tilePool[index].frame : nil
    }

    var settingsButtonFrameForTesting: NSRect { settingsButton.frame }
    var gridFrameForTesting: NSRect { scrollView.frame }
    var panelBackgroundFrameForTesting: NSRect { panelBackgroundView.frame }

    @objc private func settingsClicked() {
        onSettingsRequested?()
    }
}
