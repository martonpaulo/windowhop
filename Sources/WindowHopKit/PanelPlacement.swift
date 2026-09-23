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
public enum SwitcherDisplayPlacement: String, CaseIterable, Identifiable, Sendable {
    case allDisplays
    case pointerDisplay
    case specificDisplay

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .allDisplays: return String(localized: "All displays")
        case .pointerDisplay: return String(localized: "The display with the pointer")
        case .specificDisplay: return String(localized: "A specific display")
        }
    }
}

/// A display reduced to the facts placement needs.
///
/// Keeping this a value type is what lets `PanelDisplayResolver` stay pure and
/// unit-tested with no window server, no AppKit, and no connected hardware.
public struct DisplayDescriptor: Equatable, Identifiable, Sendable {
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
    public static func targets(
        placement: SwitcherDisplayPlacement,
        chosenDisplayID: String?,
        available: [DisplayDescriptor],
        pointerDisplayID: String?
    ) -> [DisplayDescriptor] {
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
                let chosen = available.first(where: { $0.id == chosenDisplayID })
            {
                return [chosen]
            }
            return [pointerTarget(available: available, pointerDisplayID: pointerDisplayID)]
        }
    }

    /// `available` must not be empty; callers guarantee it.
    private static func pointerTarget(
        available: [DisplayDescriptor],
        pointerDisplayID: String?
    ) -> DisplayDescriptor {
        if let pointerDisplayID,
            let pointer = available.first(where: { $0.id == pointerDisplayID })
        {
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
    public static func columns(
        visibleWidth: CGFloat,
        tileWidth: CGFloat,
        spacing: CGFloat,
        padding: CGFloat,
        maxWidthFraction: CGFloat,
        tileCount: Int
    ) -> Int {
        let maxGridWidth = visibleWidth * maxWidthFraction - padding * 2
        return max(1, min(tileCount, Int((maxGridWidth + spacing) / (tileWidth + spacing))))
    }

    /// Rows that fit down one display before the grid has to scroll.
    public static func maxVisibleRows(
        visibleHeight: CGFloat,
        tileHeight: CGFloat,
        rowSpacing: CGFloat,
        padding: CGFloat,
        maxHeightFraction: CGFloat
    ) -> Int {
        let availableHeight = visibleHeight * maxHeightFraction - padding * 2
        return max(1, Int((availableHeight + rowSpacing) / (tileHeight + rowSpacing)))
    }

    /// The narrowest and shortest visible frames among the targets.
    ///
    /// Deriving the shared grid from the most constrained display is what makes
    /// the identical grid guaranteed to fit everywhere. The cost is real and
    /// accepted: a 5K display beside a 1080p one uses the 1080p capacity.
    public static func mostConstrainedExtent(
        _ displays: [DisplayDescriptor]
    ) -> (width: CGFloat, height: CGFloat)? {
        guard let first = displays.first else { return nil }
        return displays.dropFirst().reduce(
            (width: first.visibleFrame.width, height: first.visibleFrame.height)
        ) { limit, display in
            (
                width: min(limit.width, display.visibleFrame.width),
                height: min(limit.height, display.visibleFrame.height)
            )
        }
    }

    /// The sharpest scale among the targets.
    ///
    /// One capture feeds every mirrored panel, so it must satisfy the most
    /// demanding display: scaling a Retina-resolution image down for a
    /// non-Retina panel is free, while the reverse is visibly soft.
    public static func captureScale(
        _ displays: [DisplayDescriptor],
        fallback: CGFloat
    ) -> CGFloat {
        displays.map(\.backingScale).max() ?? fallback
    }
}

/// The one "Show the switcher on" choice Settings offers: the two display-free
/// placements, or a display by its stable identifier. It is a view of the two
/// stored preferences, not a third one, so it needs no migration: a specific
/// display is `specificDisplay` plus `switcherDisplayID`.
public enum SwitcherPlacementChoice: Hashable, Sendable {
    case allDisplays
    case pointerDisplay
    case display(id: String)

    /// The choice the stored preferences describe. A specific placement with no
    /// display stored has no display to name, so it reads as the pointer
    /// display, which is where `PanelDisplayResolver` draws it.
    public init(placement: SwitcherDisplayPlacement, displayID: String?) {
        switch placement {
        case .allDisplays: self = .allDisplays
        case .pointerDisplay: self = .pointerDisplay
        case .specificDisplay:
            if let displayID, !displayID.isEmpty {
                self = .display(id: displayID)
            } else {
                self = .pointerDisplay
            }
        }
    }

    public var placement: SwitcherDisplayPlacement {
        switch self {
        case .allDisplays: .allDisplays
        case .pointerDisplay: .pointerDisplay
        case .display: .specificDisplay
        }
    }

    /// The display identifier to store. Choosing a display-free placement keeps
    /// the last chosen display, so choosing a display again later is one step.
    public func displayID(keeping current: String?) -> String? {
        switch self {
        case .allDisplays, .pointerDisplay: current
        case .display(let id): id
        }
    }

    /// One display in the menu.
    public struct DisplayEntry: Hashable, Identifiable, Sendable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// The menu's display entries: every connected display, then a chosen
    /// display that is disconnected, kept so that unplugging a monitor never
    /// destroys the choice.
    public static func displayEntries(
        connected: [DisplayEntry],
        chosenDisplayID: String?,
        disconnectedLabel: String
    ) -> [DisplayEntry] {
        guard let chosenDisplayID, !chosenDisplayID.isEmpty,
            !connected.contains(where: { $0.id == chosenDisplayID })
        else { return connected }
        return connected + [DisplayEntry(id: chosenDisplayID, name: disconnectedLabel)]
    }
}
