import AppKit

/// One session's panels: exactly one per target display, presenting the command
/// surface `SwitcherController` already used against a single panel.
///
/// Mirrored panels are identical by construction. They share one grid (derived
/// from the most constrained display) and one selection, because `SwitcherState`
/// tracks a single column count for arrow navigation — per-display grids would
/// make the arrow keys mean different things depending on which display the user
/// is looking at.
///
/// Callbacks are index-based, so which panel a click came from is irrelevant to
/// the controller and is deliberately not reported.
public final class SwitcherPanelGroup {
    public var onItemClicked: ((Int) -> Void)?
    public var onItemCloseRequested: ((Int) -> Void)?
    public var onSettingsRequested: (() -> Void)?
    public var onPreviewPermissionRequested: (() -> Void)?

    private var panels: [SwitcherPanel] = []

    /// Grid geometry of the current layout, for 2D arrow-key navigation. Every
    /// panel reports the same value; the first one is authoritative.
    public var columnsPerRow: Int { panels.first?.columnsPerRow ?? 1 }

    /// The scale a capture must satisfy to look sharp on every target display.
    public private(set) var captureScale: CGFloat = 2

    public init() {}

    /// Rebuilds the panel set for the displays this session targets.
    ///
    /// Called at session start, before `show`. Panels are recreated only when the
    /// target set changes, so a repeated session on the same displays reuses its
    /// panels and their warm tile pools.
    public func prepare(for targets: [(descriptor: DisplayDescriptor, screen: NSScreen)],
                        tileCount: Int,
                        tileSize: NSSize) {
        let descriptors = targets.map(\.descriptor)
        captureScale = SwitcherGridCapacity.captureScale(descriptors, fallback: 2)

        let limits = sharedLimits(for: descriptors, tileCount: tileCount, tileSize: tileSize)
        resizePool(to: targets.count)
        for (panel, target) in zip(panels, targets) {
            panel.placementScreen = target.screen
            panel.sharedColumnLimit = limits.columns
            panel.sharedRowLimit = limits.rows
        }
    }

    /// The grid every mirrored panel must use, taken from the narrowest and
    /// shortest target so the identical layout fits on all of them.
    private func sharedLimits(for descriptors: [DisplayDescriptor],
                              tileCount: Int,
                              tileSize: NSSize) -> (columns: Int?, rows: Int?) {
        guard descriptors.count > 1,
              let extent = SwitcherGridCapacity.mostConstrainedExtent(descriptors) else {
            // a single panel has nothing to agree with and keeps its own capacity
            return (nil, nil)
        }
        let columns = SwitcherGridCapacity.columns(
            visibleWidth: extent.width,
            tileWidth: tileSize.width,
            spacing: DesignTokens.tileSpacing,
            padding: DesignTokens.panelPadding,
            maxWidthFraction: DesignTokens.panelMaxWidthFraction,
            tileCount: tileCount)
        let rows = SwitcherGridCapacity.maxVisibleRows(
            visibleHeight: extent.height,
            tileHeight: tileSize.height,
            rowSpacing: DesignTokens.tileRowSpacing,
            padding: DesignTokens.panelPadding,
            maxHeightFraction: DesignTokens.panelMaxHeightFraction)
        return (columns, rows)
    }

    private func resizePool(to count: Int) {
        while panels.count > count {
            let panel = panels.removeLast()
            panel.hide()
        }
        while panels.count < count {
            panels.append(makePanel())
        }
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel()
        panel.onItemClicked = { [weak self] index in self?.onItemClicked?(index) }
        panel.onItemCloseRequested = { [weak self] index in self?.onItemCloseRequested?(index) }
        panel.onSettingsRequested = { [weak self] in self?.onSettingsRequested?() }
        panel.onPreviewPermissionRequested = { [weak self] in
            self?.onPreviewPermissionRequested?()
        }
        return panel
    }

    // MARK: - Fanned-out commands

    public func show(items: [SwitcherItem],
                     selectedIndex: Int,
                     presentationMode: SwitcherPresentationMode) {
        panels.forEach {
            $0.show(items: items, selectedIndex: selectedIndex, presentationMode: presentationMode)
        }
    }

    public func presentAgain(presentationMode: SwitcherPresentationMode) {
        panels.forEach { $0.presentAgain(presentationMode: presentationMode) }
    }

    public func update(items: [SwitcherItem], selectedIndex: Int) {
        panels.forEach { $0.update(items: items, selectedIndex: selectedIndex) }
    }

    public func select(_ index: Int) {
        panels.forEach { $0.select(index) }
    }

    public func updatePreview(id: AnyHashable, image: NSImage) {
        panels.forEach { $0.updatePreview(id: id, image: image) }
    }

    public func updatePreviewUnavailable(id: AnyHashable) {
        panels.forEach { $0.updatePreviewUnavailable(id: id) }
    }

    public func setPreviewPermissionStatus(_ status: ScreenRecordingPermission.Status) {
        panels.forEach { $0.setPreviewPermissionStatus(status) }
    }

    public func showExpandedPreview(id: AnyHashable, image: NSImage) {
        panels.forEach { $0.showExpandedPreview(id: id, image: image) }
    }

    /// The window expanded on the panels, or nil while they show the grid.
    /// Mirrored panels stay identical, so the first panel answers for all.
    public var expandedPreviewID: AnyHashable? { panels.first?.expandedPreviewID }

    public func hideExpandedPreview() {
        panels.forEach { $0.hideExpandedPreview() }
    }

    /// Hides every panel. Ending a session must leave nothing on any display.
    public func hide() {
        panels.forEach { $0.hide() }
    }

    // MARK: - Testing

    var panelCountForTesting: Int { panels.count }
    func panelForTesting(at index: Int) -> SwitcherPanel? {
        index < panels.count ? panels[index] : nil
    }
}
