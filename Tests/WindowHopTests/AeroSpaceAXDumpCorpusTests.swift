import CoreGraphics
import XCTest
@testable import WindowHopCore

/// Runs WindowHop's eligibility rules over AeroSpace's corpus of real AX
/// attribute dumps (`Fixtures/AeroSpaceAXDumps`, MIT, pinned in UPSTREAM.md).
/// Only the dump data is imported; no AeroSpace code is used. Each dump carries
/// AeroSpace's label: `window` and `dialog` are windows a user switches to, so
/// WindowHop should list them; `popup` is transient UI, so WindowHop should not.
///
/// The labels are AeroSpace's tiling decisions, not ground truth for a switcher,
/// and a few are marked "todo fix" by AeroSpace itself. Every disagreement is
/// therefore recorded below with WindowHop's decision and the reason, and the
/// test fails when the rules drift from a recorded decision in either direction.
final class AeroSpaceAXDumpCorpusTests: XCTestCase {
    enum Decision: Equatable {
        /// shown under the default inclusion policy
        case listed
        /// an actual window, hidden as Picture in Picture unless the user opts in
        case pictureInPicture
        /// rejected by `WindowEligibility.isActualWindow`
        case notAWindow
    }

    /// Dumps where WindowHop deliberately or knowingly differs from the label.
    static let disagreements: [String: (decision: Decision, reason: String)] = [
        // labeled window or dialog, not listed
        "finder_quick_look": (.notAWindow,
            "Quick Look reports the nonstandard subrole \"Quick Look\"; a transient preview panel"),
        "transmission_torrent_inspector": (.notAWindow,
            "an NSPanel utility (AXFloatingWindow); panels are never entries"),
        "microsoft_edge_pip": (.pictureInPicture,
            "it is Edge's Picture in Picture; AeroSpace floats it as a dialog, WindowHop hides it by default"),
        "spotify_miniplayer": (.pictureInPicture,
            "floats at layer 3 with every title-bar button disabled, the Chromium PiP signature"),
        // labeled popup, listed
        "outlook_reminder": (.listed,
            "an always-on-top window with enabled close and minimize buttons: ordinary by the #90 rule"),
        "slack_huddle_share_screen_floating_popup": (.listed,
            "floats with an enabled close button: ordinary by the #90 rule"),
        "slack_huddle_share_screen_draw_on_screen_fake_window": (.listed,
            "covers the whole display with an enabled close button; fullscreen floating surfaces stay listed"),
        "cleanshotx_monitor_1": (.listed,
            "a capture overlay covering the whole display; fullscreen floating surfaces stay listed"),
        "firefox_extensions_popup": (.listed,
            "AltTab's Firefox rule keeps AXUnknown Firefox windows taller than 400 pt for fullscreen video"),
        "vlc_fullscreen": (.listed,
            "VLC's fullscreen video is a window users return to (AltTab rule); AeroSpace marks its label todo fix"),
        "iterm2_hotkey_window": (.listed,
            "a titled standard window at the normal layer; no public fact separates it from a terminal window"),
        "choose_1_5_0": (.listed,
            "an untitled standard window at the normal layer; public facts match a real untitled window"),
        "nomachine_session_1": (.listed,
            "the session window before it gets its title (nomachine_session_2 is the same window, a dialog)"),
        "nomachine_welcome_window_1": (.listed,
            "the welcome window before it gets its title (nomachine_welcome_window_2 is the same window)"),
        "zebar": (.listed,
            "a status bar drawn as a standard window at the normal layer; nothing public marks it as a bar"),
    ]

    /// The corpus does not record display geometry. These are the full-display
    /// frames that appear in it (a 1800×1169 laptop, a 2304×1296 and a
    /// 3840×2160 external display), used for the fullscreen-coverage exception.
    static let corpusDisplays = [
        CGRect(x: 0, y: 0, width: 1800, height: 1169),
        CGRect(x: 0, y: 0, width: 2304, height: 1296),
        CGRect(x: 0, y: 0, width: 3840, height: 2160),
    ]

    struct Dump {
        let name: String
        let label: String
        let facts: WindowFacts
        let frame: CGRect?
        let layer: Int?
        let buttons: PictureInPictureDetector.TitleBarButtons
        let isMinimized: Bool
    }

    // MARK: - Tests

    func testCorpusLoadsEveryLabeledDump() throws {
        let dumps = try Self.loadCorpus()
        XCTAssertEqual(dumps.count, 125, "the pinned corpus has 118 dumps plus a 7-dump scenario")
        XCTAssertEqual(Set(dumps.map(\.label)), ["window", "dialog", "popup"])
    }

    func testDecisionsMatchLabelsOrRecordedDisagreements() throws {
        for dump in try Self.loadCorpus() {
            let decision = Self.decide(dump)
            if let recorded = Self.disagreements[dump.name] {
                XCTAssertEqual(decision, recorded.decision, "\(dump.name): \(recorded.reason)")
            } else {
                XCTAssertEqual(decision == .listed, dump.label != "popup",
                               "\(dump.name) is labeled \(dump.label) but WindowHop decides \(decision)")
            }
        }
    }

    func testEveryRecordedDisagreementStillDisagrees() throws {
        let dumps = Dictionary(uniqueKeysWithValues: try Self.loadCorpus().map { ($0.name, $0) })
        for (name, recorded) in Self.disagreements {
            guard let dump = dumps[name] else { XCTFail("\(name) is not in the corpus"); continue }
            XCTAssertNotEqual(recorded.decision == .listed, dump.label != "popup",
                              "\(name) now agrees with its label; drop it from the list")
        }
    }

    func testBrowserPictureInPictureWindows() throws {
        let dumps = Dictionary(uniqueKeysWithValues: try Self.loadCorpus().map { ($0.name, $0) })
        // Chromium PiP: buttonless (Chrome) or all buttons disabled (Brave, Edge);
        // Firefox PiP (and Zen): close and zoom enabled, minimize disabled (#117)
        for name in ["chrome_pip", "brave_pip", "microsoft_edge_pip", "firefox_pip", "zen_browser_pip"] {
            XCTAssertEqual(dumps[name].map(Self.decide), .pictureInPicture, name)
        }
        // app-modal alerts and open panels at the modal-panel layer are windows,
        // and so are #90's closable-only dialogs and floating documents
        for name in ["ghostty_check_for_updates_2_alert", "intellij_native_open_window",
                     "macos_join_network", "1password_mini_window", "ghostty_config_error"] {
            XCTAssertEqual(dumps[name].map(Self.decide), .listed, name)
        }
    }

    // MARK: - Mapping a dump to WindowHop's facts

    static func decide(_ dump: Dump) -> Decision {
        guard WindowEligibility.isActualWindow(dump.facts) else { return .notAWindow }
        let pid: pid_t = 1
        let onScreen = dump.layer.flatMap { layer in
            dump.frame.map { [PictureInPictureDetector.OnScreenWindow(pid: pid, frame: $0, layer: layer)] }
        } ?? []
        let isPiP = PictureInPictureDetector.isPictureInPicture(
            pid: pid, frame: dump.frame, buttons: dump.buttons,
            onScreenWindows: onScreen, screenFrames: corpusDisplays)
        let state = WindowDisplayState(isMinimized: dump.isMinimized, isAppHidden: false,
                                       isOwnWindow: false, isPictureInPicture: isPiP,
                                       isOnCurrentSpace: true, isOnActiveDisplay: true)
        if WindowEligibility.shouldDisplay(state, policy: WindowInclusionPolicy()) { return .listed }
        return isPiP ? .pictureInPicture : .notAWindow
    }

    static func loadCorpus() throws -> [Dump] {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "AeroSpaceAXDumps", withExtension: nil))
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "json5" }
        return try files.map(dump(from:)).sorted { $0.name < $1.name }
    }

    private static func dump(from file: URL) throws -> Dump {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file), options: [.json5Allowed])
        let json = try XCTUnwrap(object as? [String: Any], file.lastPathComponent)
        let app = json["Aero.AXApp"] as? [String: Any]
        let frame = (json["AXFrame"] as? String).flatMap(rect)
        let size = (json["AXSize"] as? String).flatMap(rect)?.size
        func enabled(_ button: String) -> Bool? {
            (json[button] as? [String: Any])?["AXEnabled"] as? Bool
        }
        let name = file.deletingPathExtension().lastPathComponent
        return Dump(
            name: file.deletingLastPathComponent().lastPathComponent == "AeroSpaceAXDumps"
                ? name : "\(file.deletingLastPathComponent().lastPathComponent)/\(name)",
            label: try XCTUnwrap(json["Aero.AxUiElementWindowType"] as? String, name),
            facts: WindowFacts(role: json["AXRole"] as? String,
                               subrole: json["AXSubrole"] as? String,
                               size: size,
                               title: json["AXTitle"] as? String,
                               bundleIdentifier: json["Aero.App.appBundleId"] as? String,
                               localizedAppName: app?["AXTitle"] as? String,
                               executablePath: (json["Aero.App.nsApp.execPath"] as? String)
                                   .flatMap(URL.init(string:))?.path),
            frame: frame,
            layer: layer(json["Aero.windowLevel"]),
            buttons: .init(close: enabled("AXCloseButton"), minimize: enabled("AXMinimizeButton"),
                           zoom: enabled("AXZoomButton")),
            isMinimized: json["AXMinimized"] as? Bool ?? false)
    }

    /// AeroSpace names layers 0 and 3 and stores any other `kCGWindowLayer` as a number.
    private static func layer(_ value: Any?) -> Int? {
        switch value {
        case let name as String where name == "normalWindow": 0
        case let name as String where name == "alwaysOnTopWindow": 3
        case let number as Int: number
        default: nil
        }
    }

    /// Parses the `{value = x:… y:… w:… h:…}` or `{value = w:… h:…}` text of a dumped AXValue.
    private static func rect(_ text: String) -> CGRect? {
        func number(_ key: String) -> CGFloat? {
            guard let range = text.range(of: "\(key):"),
                  let end = text[range.upperBound...].firstIndex(of: " ") else { return nil }
            return Double(text[range.upperBound..<end]).map { CGFloat($0) }
        }
        guard let width = number("w"), let height = number("h") else { return nil }
        return CGRect(x: number("x") ?? 0, y: number("y") ?? 0, width: width, height: height)
    }
}
