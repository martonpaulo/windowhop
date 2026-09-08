import AppKit

/// NSView normally ignores a child's descendants outside that child's bounds.
/// Close is intentionally centered on the canvas corner, so the document view
/// explicitly forwards hits within its clip-safe overlay gutter.
private final class SwitcherTilesContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        for case let tile as SwitcherTileView in subviews.reversed() where !tile.isHidden {
            if let hit = tile.closeControlHitTest(convert(point, to: tile)) {
                return hit
            }
        }
        return super.hitTest(point)
    }
}

private final class SwitcherPanelHostView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    private(set) var isPointerInside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setPointerInside(true)
    }

    override func mouseExited(with event: NSEvent) {
        setPointerInside(false)
    }

    func refreshPointerLocation() {
        guard let window else {
            setPointerInside(false)
            return
        }
        setPointerInside(bounds.contains(convert(
            window.mouseLocationOutsideOfEventStream, from: nil)))
    }

    func setPointerInside(_ value: Bool) {
        guard isPointerInside != value else { return }
        isPointerInside = value
        onHoverChanged?(value)
    }
}

public enum SwitcherPresentationMode: Equatable {
    case cycling
    case persistent
}

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
    /// One panel-level action when all preview capture is permission-blocked.
    public var onPreviewPermissionRequested: (() -> Void)?

    /// Transparent overflow host. The visible panel occupies only
    /// `panelBackgroundView`; global controls may extend into the host without
    /// changing the panel's internal layout.
    private let hostView = SwitcherPanelHostView()
    private var panelBackgroundView: NSView!
    /// Everything inside the visible panel background (the preview grid).
    private let chromeView = NSView()
    private let scrollView = NSScrollView()
    private let tilesContainer = SwitcherTilesContainerView()
    private let settingsButton = NSButton()
    private let permissionButton = NSButton()
    private let expandedPreviewView = ExpandedPreviewView()
    /// Pooled tiles, reconfigured in place; index i shows item i.
    private var tilePool: [SwitcherTileView] = []
    private var visibleTileCount = 0
    private var selectedIndex = 0
    private var mode = AppearanceMode.appIcons
    private var items: [SwitcherItem] = []
    private var itemIds: [AnyHashable] = []
    /// The window whose expanded preview is on screen, or nil for the grid.
    public private(set) var expandedPreviewID: AnyHashable?
    private var presentationMode = SwitcherPresentationMode.cycling
    private var accessibilityDisplayObserver: NSObjectProtocol?
    /// Grid geometry of the current layout, for 2D arrow-key navigation.
    public private(set) var columnsPerRow = 1

    /// The display this panel draws on. `SwitcherPanelGroup` sets it for every
    /// session; nil falls back to the first screen, which is what the offscreen
    /// render harness uses and what a single-display Mac resolves to anyway.
    /// `NSScreen.main` is deliberately not the fallback: it is documented to
    /// misreport the active screen (see `DisplayRegistry.pointerDisplayID`).
    public var placementScreen: NSScreen?

    /// Grid limits shared by every mirrored panel, so all of them show an
    /// identical grid and `columnsPerRow` stays one authoritative value for
    /// arrow-key navigation. nil means "use this display's own capacity".
    public var sharedColumnLimit: Int?
    public var sharedRowLimit: Int?

    private var layoutScreen: NSScreen? { placementScreen ?? NSScreen.screens.first }

    /// The preview area a tile offers in Window Previews mode, for capture sizing.
    public static var previewContentSize: NSSize {
        let metrics = SwitcherTileView.Metrics.metrics(
            for: .windowPreviews,
            showTabCounts: Preferences.shared.showTabCounts)
        return NSSize(width: metrics.tileSize.width - DesignTokens.tileLabelInset * 2,
                      height: metrics.contentHeight)
    }

    public static var expandedPreviewContentSize: NSSize {
        NSSize(width: DesignTokens.expandedPreviewMinimumWidth
                        - DesignTokens.expandedPreviewPanelInset * 2,
               height: DesignTokens.expandedPreviewMinimumHeight
                        - DesignTokens.expandedPreviewPanelInset * 2
                        - DesignTokens.expandedPreviewTitleHeight)
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

        expandedPreviewView.isHidden = true
        chromeView.addSubview(expandedPreviewView)

        // Global panel action: contextual during held cycling, persistent for
        // Open WindowHop sessions, and never measured as part of the grid.
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
        settingsButton.alphaValue = 0
        settingsButton.isEnabled = false
        settingsButton.setAccessibilityHidden(true)
        hostView.addSubview(settingsButton)
        hostView.onHoverChanged = { [weak self] _ in
            self?.updateSettingsButtonVisibility(animated: true)
        }

        permissionButton.image = NSImage(
            systemSymbolName: "lock.shield.fill",
            accessibilityDescription: "Screen Recording permission required")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: DesignTokens.permissionGlyphSymbolSize,
                weight: .semibold)
                .applying(.init(paletteColors: [DesignTokens.overlayGlyphColor,
                                                DesignTokens.overlayCircleColor])))
        permissionButton.isBordered = false
        permissionButton.imagePosition = .imageOnly
        permissionButton.target = self
        permissionButton.action = #selector(permissionClicked)
        permissionButton.toolTip = "Screen Recording permission required — Open System Settings"
        permissionButton.setAccessibilityLabel(
            "Screen Recording permission required. Open System Settings")
        permissionButton.isHidden = true
        hostView.addSubview(permissionButton)

        chromeView.setAccessibilityElement(true)
        chromeView.setAccessibilityRole(.list)
        chromeView.setAccessibilityLabel("WindowHop window switcher")

        accessibilityDisplayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                guard let self else { return }
                for tile in self.tilePool.prefix(self.visibleTileCount) {
                    tile.refreshMotionPreference()
                }
                self.updateSettingsButtonVisibility(animated: false)
            }

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

    deinit {
        if let accessibilityDisplayObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityDisplayObserver)
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

    public func show(items: [SwitcherItem],
                     selectedIndex: Int,
                     presentationMode: SwitcherPresentationMode) {
        self.presentationMode = presentationMode
        hostView.setPointerInside(false)
        update(items: items, selectedIndex: selectedIndex)
        orderFrontRegardless()
        hostView.refreshPointerLocation()
        updateSettingsButtonVisibility(animated: false)
        announceSelection()
        DebugLog.log("panel shown: \(items.count) tiles (\(mode.rawValue)), frame \(frame)")
    }

    /// Re-presents the panel after a confirmation dialog hid it.
    public func presentAgain(presentationMode: SwitcherPresentationMode) {
        self.presentationMode = presentationMode
        orderFrontRegardless()
        hostView.refreshPointerLocation()
        updateSettingsButtonVisibility(animated: false)
    }

    public func update(items: [SwitcherItem], selectedIndex index: Int) {
        mode = Preferences.shared.appearanceMode
        // An unrelated metadata or list refresh must not collapse an expanded
        // preview: only losing the window, the selection or the mode does.
        let selectedID = index >= 0 && index < items.count ? items[index].id : nil
        let stillExpanded = expandedPreviewID.flatMap { id -> SwitcherItem? in
            guard mode == .windowPreviews, id == selectedID else { return nil }
            return items.first { $0.id == id }
        }
        self.items = items
        selectedIndex = index
        itemIds = items.map { $0.id }
        rebuildTiles(items: items)
        if let stillExpanded {
            expandedPreviewView.updateMetadata(item: stillExpanded)
            layoutExpandedPreview()
        } else {
            collapseExpandedPreview()
            layoutOnPlacementScreen(tileCount: items.count)
        }
        applySelection()
    }

    public func select(_ index: Int) {
        selectedIndex = index
        applySelection()
        announceSelection()
    }

    /// A capture arrived for a window in the open session: fill in tiles that
    /// had no snapshot, or crossfade a cached snapshot to the fresh one.
    /// Delivery is keyed by the window's stable id — never by tile position —
    /// so a preview can never land on another window's card.
    public func updatePreview(id: AnyHashable, image: NSImage) {
        guard let index = itemIds.firstIndex(of: id), index < visibleTileCount else { return }
        tilePool[index].setPreview(image, fadeIn: true)
    }

    /// A capture could not be produced for this window and no cached image is
    /// available. The tile keeps its fixed geometry and shows a semantic
    /// fallback instead of looking empty or broken.
    public func updatePreviewUnavailable(id: AnyHashable) {
        guard let index = itemIds.firstIndex(of: id), index < visibleTileCount else { return }
        tilePool[index].setPreviewUnavailable()
    }

    /// Applies one permission state to every preview canvas and exposes a
    /// single global action instead of repeating a button on each card.
    public func setPreviewPermissionStatus(_ status: ScreenRecordingPermission.Status) {
        guard mode == .windowPreviews else {
            permissionButton.isHidden = true
            return
        }
        permissionButton.isHidden = status.isAuthorized
        for tile in tilePool.prefix(visibleTileCount) {
            if status.isAuthorized {
                tile.setPreviewLoading()
            } else {
                tile.setPreviewPermissionUnavailable()
            }
        }
    }

    /// Shows the latest available snapshot at a larger size inside WindowHop,
    /// or repaints the one already showing. This method performs no
    /// application/window action.
    public func showExpandedPreview(id: AnyHashable, image: NSImage) {
        guard mode == .windowPreviews,
              let item = items.first(where: { $0.id == id }) else { return }
        let wasShowing = expandedPreviewID == id
        expandedPreviewID = id
        expandedPreviewView.configure(item: item, image: image)
        if !wasShowing {
            expandedPreviewView.isHidden = false
            scrollView.isHidden = true
        }
        // a repaint can bring a differently shaped snapshot, and the canvas
        // takes its shape from the image
        layoutExpandedPreview()
    }

    public func hideExpandedPreview() {
        guard expandedPreviewID != nil else { return }
        collapseExpandedPreview()
        layoutOnPlacementScreen(tileCount: visibleTileCount)
    }

    /// Returns to the grid without re-laying out the window; callers pick the
    /// layout that suits them.
    private func collapseExpandedPreview() {
        expandedPreviewID = nil
        expandedPreviewView.isHidden = true
        scrollView.isHidden = false
    }

    public func hide() {
        hostView.setPointerInside(false)
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
                tile.configure(item: item,
                               mode: mode,
                               showTabCounts: Preferences.shared.showTabCounts,
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

    private func layoutOnPlacementScreen(tileCount: Int) {
        guard let screen = layoutScreen else { return }
        let padding = DesignTokens.panelPadding
        let spacing = DesignTokens.tileSpacing
        let rowSpacing = DesignTokens.tileRowSpacing
        let tileSize = SwitcherTileView.Metrics.metrics(
            for: mode,
            showTabCounts: Preferences.shared.showTabCounts).tileSize
        let visibleFrame = screen.visibleFrame

        // tiles wrap into rows instead of scrolling horizontally (the AltTab
        // layout model); tiles never shrink. Only an extreme window count
        // exceeds the height budget and falls back to vertical scrolling.
        let capacity = SwitcherGridCapacity.columns(
            visibleWidth: visibleFrame.width,
            tileWidth: tileSize.width,
            spacing: spacing,
            padding: padding,
            maxWidthFraction: DesignTokens.panelMaxWidthFraction,
            tileCount: tileCount)
        // a mirrored group imposes the most constrained display's grid on every
        // panel, so the same layout is guaranteed to fit on all of them
        let columns = max(1, min(capacity, sharedColumnLimit ?? capacity))
        let rows = tileCount == 0 ? 1 : Int(ceil(Double(tileCount) / Double(columns)))
        columnsPerRow = columns

        let visibleColumns = min(tileCount, columns)
        let contentGridWidth = CGFloat(visibleColumns) * tileSize.width
            + CGFloat(max(0, visibleColumns - 1)) * spacing
        let contentGridHeight = CGFloat(rows) * tileSize.height
            + CGFloat(max(0, rows - 1)) * rowSpacing
        let leadingOverflow = DesignTokens.closeButtonLeadingOverflow
        let topOverflow = DesignTokens.closeButtonTopOverflow
        let documentWidth = contentGridWidth + leadingOverflow
        let documentHeight = contentGridHeight + topOverflow
        tilesContainer.frame = NSRect(x: 0, y: 0,
                                      width: documentWidth, height: documentHeight)
        for (index, tile) in tilePool.prefix(tileCount).enumerated() {
            let column = index % columns
            let row = index / columns
            // a partial row is centered, like the native switcher — never left-ragged
            let tilesInRow = min(columns, tileCount - row * columns)
            let rowWidth = CGFloat(tilesInRow) * tileSize.width
                + CGFloat(max(0, tilesInRow - 1)) * spacing
            let rowOffset = (contentGridWidth - rowWidth) / 2
            tile.frame = NSRect(x: leadingOverflow + rowOffset
                                    + CGFloat(column) * (tileSize.width + spacing),
                                y: CGFloat(rows - 1 - row) * (tileSize.height + rowSpacing),
                                width: tileSize.width, height: tileSize.height)
        }

        let rowCapacity = SwitcherGridCapacity.maxVisibleRows(
            visibleHeight: visibleFrame.height,
            tileHeight: tileSize.height,
            rowSpacing: rowSpacing,
            padding: padding,
            maxHeightFraction: DesignTokens.panelMaxHeightFraction)
        let maxVisibleRows = max(1, min(rowCapacity, sharedRowLimit ?? rowCapacity))
        let visibleRows = min(rows, maxVisibleRows)
        let visibleGridHeight = CGFloat(visibleRows) * tileSize.height
            + CGFloat(max(0, visibleRows - 1)) * rowSpacing
        scrollView.frame = NSRect(x: padding - leadingOverflow, y: padding,
                                  width: documentWidth,
                                  height: visibleGridHeight + topOverflow)
        // start reading from the first row (top of the grid)
        tilesContainer.scroll(NSPoint(
            x: 0,
            y: max(0, contentGridHeight - visibleGridHeight)))

        let panelSize = NSSize(width: contentGridWidth + padding * 2,
                               height: visibleGridHeight + padding * 2)
        panelBackgroundView.frame = NSRect(origin: .zero, size: panelSize)

        // Keep most of the complete hit target inside the panel with only the
        // named overlap outside. The transparent host preserves that overflow;
        // the panel background and preview layout retain their exact size.
        let controlSize = DesignTokens.chromeButtonHitSize
        let overflow = DesignTokens.chromeButtonOutsideOverlap
        settingsButton.frame = NSRect(x: panelSize.width - controlSize + overflow,
                                      y: panelSize.height - controlSize + overflow,
                                      width: controlSize, height: controlSize)
        permissionButton.frame = NSRect(
            x: panelSize.width - controlSize * 2,
            y: panelSize.height - controlSize,
            width: controlSize, height: controlSize)
        let hostSize = NSSize(width: panelSize.width + overflow,
                              height: panelSize.height + overflow)
        let origin = NSPoint(x: visibleFrame.midX - panelSize.width / 2,
                             y: visibleFrame.midY - panelSize.height / 2)
        setFrame(NSRect(origin: origin, size: hostSize), display: true)
    }

    private func layoutExpandedPreview() {
        guard let screen = layoutScreen else { return }
        let visibleFrame = screen.visibleFrame
        let panelSize = DesignTokens.expandedPreviewPanelSize(
            imageSize: expandedPreviewView.imageSize,
            visibleFrame: visibleFrame.size)
        panelBackgroundView.frame = NSRect(origin: .zero, size: panelSize)
        chromeView.frame = panelBackgroundView.bounds
        expandedPreviewView.frame = panelBackgroundView.bounds.insetBy(
            dx: DesignTokens.expandedPreviewPanelInset,
            dy: DesignTokens.expandedPreviewPanelInset)
        let controlSize = DesignTokens.chromeButtonHitSize
        let overflow = DesignTokens.chromeButtonOutsideOverlap
        settingsButton.frame = NSRect(x: panelSize.width - controlSize + overflow,
                                      y: panelSize.height - controlSize + overflow,
                                      width: controlSize, height: controlSize)
        permissionButton.isHidden = true
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

    func tileForTesting(at index: Int) -> SwitcherTileView? {
        index >= 0 && index < visibleTileCount ? tilePool[index] : nil
    }

    func closeFrameForTesting(at index: Int) -> NSRect? {
        guard let tile = tileForTesting(at: index) else { return nil }
        return tile.convert(tile.closeFrameForTesting, to: hostView)
    }

    /// Explicit offscreen-render hook used by the documentation harness.
    /// Production close visibility remains hover-driven.
    var selectedIndexForTesting: Int { selectedIndex }

    public func prepareCloseForRendering(at index: Int?) {
        for tile in tilePool.prefix(visibleTileCount) {
            tile.prepareCloseControlForRendering(visible: false)
        }
        if let index {
            tileForTesting(at: index)?.prepareCloseControlForRendering(visible: true)
        }
    }

    var settingsButtonFrameForTesting: NSRect { settingsButton.frame }
    var settingsButtonIsVisibleForTesting: Bool {
        settingsButton.isEnabled && settingsButton.alphaValue > 0
    }
    var gridFrameForTesting: NSRect { scrollView.frame }
    var panelBackgroundFrameForTesting: NSRect { panelBackgroundView.frame }

    func setPanelHoverForTesting(_ hovered: Bool) {
        hostView.setPointerInside(hovered)
        updateSettingsButtonVisibility(animated: false)
    }

    private func updateSettingsButtonVisibility(animated: Bool) {
        let visible = presentationMode == .persistent || hostView.isPointerInside
        settingsButton.isEnabled = visible
        settingsButton.setAccessibilityHidden(!visible)
        let target: CGFloat = visible ? 1 : 0
        guard settingsButton.alphaValue != target else { return }
        let shouldAnimate = animated
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard shouldAnimate else {
            settingsButton.alphaValue = target
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.settingsVisibilityFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            settingsButton.animator().alphaValue = target
        }
    }

    @objc private func settingsClicked() {
        onSettingsRequested?()
    }

    @objc private func permissionClicked() {
        onPreviewPermissionRequested?()
    }
}
