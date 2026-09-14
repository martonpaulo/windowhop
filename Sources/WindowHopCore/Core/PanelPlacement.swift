import CoreGraphics
import Foundation

/// Which displays the switcher panel is drawn on.
///
/// Placement is display *behavior*, not appearance: what the panel looks like is
/// governed by `AppearanceMode`, and the two must not be conflated.
///
/// `pointerDisplay` deliberately means the display containing the pointer, not
/// the one holding keyboard focus. The hand follows the eye, and the panel
/// opening away from where the user is looking is the complaint this setting
/// exists to answer. The keyboard-focus display (`NSScreen.main`) keeps its own
/// separate role in `WindowInclusionPolicy.includeOtherDisplays`, which decides
/// which *windows* are listed and is unaffected by this setting.
public enum SwitcherDisplayPlacement: String, CaseIterable, Identifiable {
    case allDisplays
    case pointerDisplay
    case specificDisplay

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .allDisplays: return "All displays"
        case .pointerDisplay: return "The display with the pointer"
        case .specificDisplay: return "A specific display"
        }
    }
}

/// A display reduced to the facts placement needs.
///
/// Keeping this a value type is what lets `PanelDisplayResolver` stay pure and
/// unit-tested with no window server, no AppKit, and no connected hardware.
public struct DisplayDescriptor: Equatable, Identifiable {
    /// Stable across reconnect and reboot, unlike a `CGDirectDisplayID`.
    public let id: String
    public let name: String
    public let visibleFrame: CGRect
    public let backingScale: CGFloat

    public init(id: String, name: String, visibleFrame: CGRect, backingScale: CGFloat) {
        self.id = id
        self.name = name
        self.visibleFrame = visibleFrame
        self.backingScale = backingScale
    }
}

/// Resolves the ordered set of displays a session draws its panel on.
///
/// Every fallback lives here rather than in the UI, so the rule is testable and
/// has one owner. The one invariant that matters: while any display exists, the
/// result is never empty. A switcher that opens on no display at all is worse
/// than one that opens on the wrong display.
public enum PanelDisplayResolver {
    public static func targets(placement: SwitcherDisplayPlacement,
                               chosenDisplayID: String?,
                               available: [DisplayDescriptor],
                               pointerDisplayID: String?) -> [DisplayDescriptor] {
        guard !available.isEmpty else { return [] }
        switch placement {
        case .allDisplays:
            return available
        case .pointerDisplay:
            return [pointerTarget(available: available, pointerDisplayID: pointerDisplayID)]
        case .specificDisplay:
            // A chosen display that is currently disconnected falls back to the
            // pointer display. The stored id is deliberately not cleared, so the
            // choice returns by itself when the display is plugged back in.
            if let chosenDisplayID,
               let chosen = available.first(where: { $0.id == chosenDisplayID }) {
                return [chosen]
            }
            return [pointerTarget(available: available, pointerDisplayID: pointerDisplayID)]
        }
    }

    /// `available` must not be empty; callers guarantee it.
    private static func pointerTarget(available: [DisplayDescriptor],
                                      pointerDisplayID: String?) -> DisplayDescriptor {
        if let pointerDisplayID,
           let pointer = available.first(where: { $0.id == pointerDisplayID }) {
            return pointer
        }
        return available[0]
    }
}

/// The tile-grid capacity of one display.
///
/// Extracted from `SwitcherPanel` so that a group of mirrored panels can agree
/// on one grid before any of them lays out. Mirrored panels must show an
/// identical grid: `SwitcherState` tracks a single column count for arrow
/// navigation, so per-display column counts would make the arrow keys mean
/// different things depending on which display the user happens to look at.
public enum SwitcherGridCapacity {
    /// Columns that fit across one display, capped at the number of tiles.
    public static func columns(visibleWidth: CGFloat,
                               tileWidth: CGFloat,
                               spacing: CGFloat,
                               padding: CGFloat,
                               maxWidthFraction: CGFloat,
                               tileCount: Int) -> Int {
        let maxGridWidth = visibleWidth * maxWidthFraction - padding * 2
        return max(1, min(tileCount, Int((maxGridWidth + spacing) / (tileWidth + spacing))))
    }

    /// Rows that fit down one display before the grid has to scroll.
    public static func maxVisibleRows(visibleHeight: CGFloat,
                                      tileHeight: CGFloat,
                                      rowSpacing: CGFloat,
                                      padding: CGFloat,
                                      maxHeightFraction: CGFloat) -> Int {
        let availableHeight = visibleHeight * maxHeightFraction - padding * 2
        return max(1, Int((availableHeight + rowSpacing) / (tileHeight + rowSpacing)))
    }

    /// The narrowest and shortest visible frames among the targets.
    ///
    /// Deriving the shared grid from the most constrained display is what makes
    /// the identical grid guaranteed to fit everywhere. The cost is real and
    /// accepted: a 5K display beside a 1080p one uses the 1080p capacity.
    public static func mostConstrainedExtent(
        _ displays: [DisplayDescriptor]) -> (width: CGFloat, height: CGFloat)? {
        guard let first = displays.first else { return nil }
        return displays.dropFirst().reduce(
            (width: first.visibleFrame.width, height: first.visibleFrame.height)) { limit, display in
                (width: min(limit.width, display.visibleFrame.width),
                 height: min(limit.height, display.visibleFrame.height))
            }
    }

    /// The sharpest scale among the targets.
    ///
    /// One capture feeds every mirrored panel, so it must satisfy the most
    /// demanding display: scaling a Retina-resolution image down for a
    /// non-Retina panel is free, while the reverse is visibly soft.
    public static func captureScale(_ displays: [DisplayDescriptor],
                                    fallback: CGFloat) -> CGFloat {
        displays.map(\.backingScale).max() ?? fallback
    }
}

/// The size of one Window Previews card on a display (issue #33).
///
/// Cards scale with the display like AltTab's thumbnails
/// (`317a485b:src/logic/Appearance.swift`, `rowsCount`): the canvas grows
/// until `rows` full cards fill the panel's height budget, but never so wide
/// that fewer than `minimumColumns` fit across, and never below the minimum.
/// Only the size follows the display; the canvas shape stays fixed (issue #13).
public enum PreviewCardSizing {
    public struct Layout: Equatable {
        public let rows: Int
        public let minimumColumns: Int
        public let minimumCanvasWidth: CGFloat
        /// Canvas width divided by canvas height.
        public let canvasAspect: CGFloat
        /// Card height outside the canvas: insets, title zone, and metadata.
        public let cardChromeHeight: CGFloat
        /// Card width outside the canvas.
        public let cardChromeWidth: CGFloat
        public let spacing: CGFloat
        public let rowSpacing: CGFloat
        public let padding: CGFloat
        public let maxWidthFraction: CGFloat
        public let maxHeightFraction: CGFloat

        public init(rows: Int, minimumColumns: Int, minimumCanvasWidth: CGFloat,
                    canvasAspect: CGFloat, cardChromeHeight: CGFloat, cardChromeWidth: CGFloat,
                    spacing: CGFloat, rowSpacing: CGFloat, padding: CGFloat,
                    maxWidthFraction: CGFloat, maxHeightFraction: CGFloat) {
            self.rows = rows
            self.minimumColumns = minimumColumns
            self.minimumCanvasWidth = minimumCanvasWidth
            self.canvasAspect = canvasAspect
            self.cardChromeHeight = cardChromeHeight
            self.cardChromeWidth = cardChromeWidth
            self.spacing = spacing
            self.rowSpacing = rowSpacing
            self.padding = padding
            self.maxWidthFraction = maxWidthFraction
            self.maxHeightFraction = maxHeightFraction
        }
    }

    /// Canvas width in whole points; the height follows from `canvasAspect`.
    public static func canvasWidth(visibleExtent: CGSize, layout: Layout) -> CGFloat {
        let rows = CGFloat(max(1, layout.rows))
        let columns = CGFloat(max(1, layout.minimumColumns))
        let heightBudget = visibleExtent.height * layout.maxHeightFraction - layout.padding * 2
        let cardHeight = (heightBudget - layout.rowSpacing * (rows - 1)) / rows
        // flooring the height first keeps the rounded canvas height inside the budget
        let canvasHeight = (cardHeight - layout.cardChromeHeight).rounded(.down)
        let widthFromRows = (canvasHeight * layout.canvasAspect).rounded(.down)
        let widthBudget = visibleExtent.width * layout.maxWidthFraction - layout.padding * 2
        let cardWidth = (widthBudget - layout.spacing * (columns - 1)) / columns
        let widthFromColumns = (cardWidth - layout.cardChromeWidth).rounded(.down)
        return max(layout.minimumCanvasWidth, min(widthFromRows, widthFromColumns))
    }
}
