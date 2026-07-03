import AppKit
import WindowHopCore

/// Development/QA harness, reachable only through explicit flags on the binary.
/// - `--demo-switcher [--dark]`: renders the switcher panel with sample rows,
///   without needing Accessibility permission. Used for screenshots and layout QA.
/// - `--dump-windows`: starts the real engine, waits for discovery, prints the
///   switcher list with timings, and exits. Requires Accessibility permission.
enum DebugHarness {
    static func runIfRequested(_ arguments: [String]) -> Bool {
        if arguments.contains("--demo-switcher") {
            runPanelDemo(dark: arguments.contains("--dark"))
            return true
        }
        if arguments.contains("--dump-windows") {
            runWindowDump()
            return true
        }
        if let flagIndex = arguments.firstIndex(of: "--render-ui"), arguments.count > flagIndex + 1 {
            renderUI(to: arguments[flagIndex + 1])
            return true
        }
        return false
    }

    /// Renders the real switcher panel and Settings window to PNGs, in Light and
    /// Dark appearance, using in-process view rendering (no capture permission).
    private static func renderUI(to directory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let outputURL = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        func write(_ view: NSView, _ name: String) {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: outputURL.appendingPathComponent("\(name).png"))
                print("wrote \(name).png (\(Int(view.bounds.width))x\(Int(view.bounds.height)))")
            }
        }

        var pending = 0
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let panel = SwitcherPanel()
            panel.appearance = NSAppearance(named: appearance)
            panel.show(items: demoItems(), selectedIndex: 1)
            let settings = NSWindow(contentViewController: SettingsWindowController.makeContentViewController())
            settings.appearance = NSAppearance(named: appearance)
            settings.title = "WindowHop Settings"
            settings.orderBack(nil)
            pending += 1
            // give SwiftUI a few runloop turns to lay out before rasterizing
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let contentView = panel.contentView {
                    write(contentView, "switcher-\(suffix)")
                }
                if let contentView = settings.contentView {
                    write(contentView, "settings-\(suffix)")
                }
                panel.hide()
                settings.orderOut(nil)
                pending -= 1
                if pending == 0 {
                    exit(0)
                }
            }
        }
        app.run()
    }

    private static func demoItems() -> [SwitcherItem] {
        let icon = { (bundleID: String) -> NSImage? in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
        let rows: [(String, String, String, Int?)] = [
            ("UserResourceMapper.java — windowhop", "IntelliJ IDEA", "com.jetbrains.intellij", nil),
            ("Apple Human Interface Guidelines", "Safari", "com.apple.Safari", 7),
            ("release-notes.md — Notes", "Notes", "com.apple.Notes", nil),
            ("Downloads", "Finder", "com.apple.finder", 3),
            ("weekly-sync — 12 members", "Messages", "com.apple.MobileSMS", nil),
            ("main.swift — windowhop — zsh — 118×34", "Terminal", "com.apple.Terminal", 2),
        ]
        return rows.enumerated().map { index, row in
            SwitcherItem(id: index, window: nil, title: row.0, appName: row.1,
                         icon: icon(row.2) ?? NSWorkspace.shared.icon(for: .applicationBundle),
                         tabCount: row.3)
        }
    }

    private static func runPanelDemo(dark: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let panel = SwitcherPanel()
        DispatchQueue.main.async {
            panel.show(items: demoItems(), selectedIndex: 1)
            print("demo panel visible at \(panel.frame)")
        }
        app.run()
    }

    private static func runWindowDump() {
        guard AccessibilityPermission.isGranted else {
            print("dump-windows: Accessibility permission not granted for this process")
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        BackgroundWork.start()
        let started = Date()
        WindowStore.shared.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let snapshotStart = Date()
            let items = WindowStore.shared.snapshot()
            let snapshotMs = Date().timeIntervalSince(snapshotStart) * 1000
            let totalMs = Date().timeIntervalSince(started) * 1000
            print("discovered \(WindowStore.shared.windows.count) windows "
                + "(\(items.count) eligible) within \(String(format: "%.0f", totalMs))ms of engine start; "
                + "snapshot took \(String(format: "%.3f", snapshotMs))ms")
            for (index, item) in items.enumerated() {
                let tabs = item.tabCount.map { " [\($0) tabs]" } ?? ""
                print("\(index): \(item.appName) — \(item.title)\(tabs)")
            }
            exit(0)
        }
        app.run()
    }
}
