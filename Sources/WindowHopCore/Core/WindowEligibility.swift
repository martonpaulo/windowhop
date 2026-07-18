import CoreGraphics
import Foundation

/// Everything eligibility needs to know about a window, as plain values.
public struct WindowFacts {
    public var role: String?
    public var subrole: String?
    public var size: CGSize?
    public var title: String?
    public var bundleIdentifier: String?
    public var localizedAppName: String?
    public var executablePath: String?

    public init(role: String? = nil, subrole: String? = nil, size: CGSize? = nil,
                title: String? = nil, bundleIdentifier: String? = nil,
                localizedAppName: String? = nil, executablePath: String? = nil) {
        self.role = role
        self.subrole = subrole
        self.size = size
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.localizedAppName = localizedAppName
        self.executablePath = executablePath
    }
}

/// Per-window display state evaluated at snapshot time, as plain values.
public struct WindowDisplayState {
    public var isMinimized: Bool
    public var isAppHidden: Bool
    public var isOwnWindow: Bool
    /// The single sanctioned own-window exception: WindowHop's Settings window.
    public var isOwnSettingsWindow: Bool
    /// An inactive tab of a native tab group (see TabGroupResolver): never an entry.
    public var isTabbed: Bool
    /// A floating Picture-in-Picture panel (see PictureInPictureDetector): never an entry.
    public var isPictureInPicture: Bool
    public var isOnCurrentSpace: Bool
    public var isOnActiveDisplay: Bool

    public init(isMinimized: Bool, isAppHidden: Bool, isOwnWindow: Bool,
                isOwnSettingsWindow: Bool = false,
                isTabbed: Bool = false,
                isPictureInPicture: Bool = false,
                isOnCurrentSpace: Bool, isOnActiveDisplay: Bool) {
        self.isMinimized = isMinimized
        self.isAppHidden = isAppHidden
        self.isOwnWindow = isOwnWindow
        self.isOwnSettingsWindow = isOwnSettingsWindow
        self.isTabbed = isTabbed
        self.isPictureInPicture = isPictureInPicture
        self.isOnCurrentSpace = isOnCurrentSpace
        self.isOnActiveDisplay = isOnActiveDisplay
    }
}

/// Window eligibility rules, ported from AltTab v10.12.0's WindowDiscriminator.
/// `isActualWindow` decides whether an AX element is a real user-facing window at all;
/// `shouldDisplay` decides whether an actual window appears in the switcher right now.
/// Rules that depended on CGWindowID or window level (private-API data) were dropped.
public enum WindowEligibility {
    static let standardSubroles = ["AXStandardWindow", "AXDialog"]

    public static func isActualWindow(_ facts: WindowFacts) -> Bool {
        // Some non-windows have title nil (OS elements) or subrole nil/"AXUnknown" (Bartender)
        // or "AXSystemDialog" (IntelliJ tooltips). Minimized windows and windows of hidden apps
        // report subrole "AXDialog"; they stay "actual" and are filtered by shouldDisplay instead.
        guard let size = facts.size, size.width > 100, size.height > 50 else { return false }
        let specialApp = books(facts) || keynote(facts) || preview(facts) || iina(facts)
            || openFlStudio(facts) || crossoverWindow(facts)
        let standardSubrole = facts.subrole.map { standardSubroles.contains($0) } ?? false
        let appSpecificSubrole = openBoard(facts) || adobeFloatingWindow(facts) || steam(facts)
            || worldOfWarcraft(facts) || battleNetBootstrapper(facts) || firefox(facts)
            || vlcFullscreenVideo(facts) || androidEmulator(facts) || autocad(facts)
        guard specialApp || standardSubrole || appSpecificSubrole else { return false }
        if !specialApp {
            guard mustHaveIfJetbrainsApp(facts) && mustHaveIfSteam(facts)
                && mustHaveIfFusion360(facts) && mustHaveIfColorSlurp(facts) else { return false }
        }
        return true
    }

    public static func shouldDisplay(_ state: WindowDisplayState,
                                     includeOtherSpaces: Bool,
                                     includeOtherDisplays: Bool) -> Bool {
        if state.isOwnWindow && !state.isOwnSettingsWindow { return false }
        if state.isMinimized || state.isAppHidden || state.isTabbed { return false }
        if state.isPictureInPicture { return false }
        if !includeOtherSpaces && !state.isOnCurrentSpace { return false }
        if !includeOtherDisplays && !state.isOnActiveDisplay { return false }
        return true
    }

    private static func hasTitle(_ facts: WindowFacts) -> Bool {
        facts.title.map { !$0.isEmpty } ?? false
    }

    private static func mustHaveIfFusion360(_ facts: WindowFacts) -> Bool {
        // Autodesk Fusion side panels "Browser" and "Comments" have subrole AXDialog but no title
        facts.bundleIdentifier != "com.autodesk.fusion360" || hasTitle(facts)
    }

    private static func mustHaveIfJetbrainsApp(_ facts: WindowFacts) -> Bool {
        // JetBrains apps generate non-windows that pass the standard checks; they have no title
        guard let bundleIdentifier = facts.bundleIdentifier,
              bundleIdentifier.range(of: "^com\\.(jetbrains\\.|google\\.android\\.studio).*?$",
                                     options: .regularExpression) != nil else { return true }
        return (facts.subrole == "AXStandardWindow" || hasTitle(facts))
            && (facts.size.map { $0.width > 100 && $0.height > 100 } ?? false)
    }

    private static func mustHaveIfColorSlurp(_ facts: WindowFacts) -> Bool {
        facts.bundleIdentifier != "com.IdeaPunch.ColorSlurp" || facts.subrole == "AXStandardWindow"
    }

    private static func mustHaveIfSteam(_ facts: WindowFacts) -> Bool {
        // Steam windows have subrole AXUnknown; dropdown menus have empty title or nil role
        facts.bundleIdentifier != "com.valvesoftware.steam" || (hasTitle(facts) && facts.role != nil)
    }

    private static func iina(_ facts: WindowFacts) -> Bool {
        // IINA can float videos and animates window creation
        facts.bundleIdentifier == "com.colliderli.iina"
    }

    private static func keynote(_ facts: WindowFacts) -> Bool {
        // Keynote presentation mode covers the screen with an AXUnknown window
        facts.bundleIdentifier == "com.apple.iWork.Keynote"
    }

    private static func preview(_ facts: WindowFacts) -> Bool {
        facts.bundleIdentifier == "com.apple.Preview"
            && (facts.subrole.map { standardSubroles.contains($0) } ?? false)
    }

    private static func openFlStudio(_ facts: WindowFacts) -> Bool {
        facts.bundleIdentifier == "com.image-line.flstudio" && hasTitle(facts)
    }

    private static func openBoard(_ facts: WindowFacts) -> Bool {
        // OpenBoard is a ported app which doesn't use standard macOS windows
        facts.bundleIdentifier == "org.oe-f.OpenBoard"
    }

    private static func adobeFloatingWindow(_ facts: WindowFacts) -> Bool {
        (facts.bundleIdentifier == "com.adobe.Audition" || facts.bundleIdentifier == "com.adobe.AfterEffects")
            && facts.subrole == "AXFloatingWindow"
    }

    private static func books(_ facts: WindowFacts) -> Bool {
        // Books animates window creation; windows are born with subrole AXUnknown
        facts.bundleIdentifier == "com.apple.iBooksX"
    }

    private static func worldOfWarcraft(_ facts: WindowFacts) -> Bool {
        facts.bundleIdentifier == "com.blizzard.worldofwarcraft" && facts.role == "AXWindow"
    }

    private static func battleNetBootstrapper(_ facts: WindowFacts) -> Bool {
        facts.bundleIdentifier == "net.battle.bootstrapper" && facts.role == "AXWindow"
    }

    private static func steam(_ facts: WindowFacts) -> Bool {
        facts.bundleIdentifier == "com.valvesoftware.steam" && hasTitle(facts) && facts.role != nil
    }

    private static func firefox(_ facts: WindowFacts) -> Bool {
        // Firefox fullscreen videos and tooltips have subrole AXUnknown; keep only tall windows
        (facts.bundleIdentifier?.hasPrefix("org.mozilla.firefox") ?? false)
            && facts.role == "AXWindow" && (facts.size.map { $0.height > 400 } ?? false)
    }

    private static func vlcFullscreenVideo(_ facts: WindowFacts) -> Bool {
        (facts.bundleIdentifier?.hasPrefix("org.videolan.vlc") ?? false) && facts.role == "AXWindow"
    }

    private static func androidEmulator(_ facts: WindowFacts) -> Bool {
        // the emulator's small vertical menu is a "window" with an empty title
        hasTitle(facts) && (facts.executablePath?.contains("qemu-system") ?? false)
    }

    private static func crossoverWindow(_ facts: WindowFacts) -> Bool {
        facts.bundleIdentifier == nil && facts.role == "AXWindow" && facts.subrole == "AXUnknown"
            && (facts.localizedAppName == "wine64-preloader"
                || (facts.executablePath?.contains("/winetemp-") ?? false))
    }

    private static func autocad(_ facts: WindowFacts) -> Bool {
        // AutoCAD uses the undocumented "AXDocumentWindow" subrole
        (facts.bundleIdentifier?.hasPrefix("com.autodesk.AutoCAD") ?? false)
            && facts.subrole == "AXDocumentWindow"
    }
}
