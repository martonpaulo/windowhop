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
        if let flagIndex = arguments.firstIndex(of: "--updater-e2e"), arguments.count > flagIndex + 1 {
            UpdaterE2EHarness.run(feedURL: arguments[flagIndex + 1])
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

        // overflow check: 120 synthetic windows in a horizontally scrolling strip
        let overflowPanel = SwitcherPanel()
        overflowPanel.appearance = NSAppearance(named: .aqua)
        let overflowItems = manyDemoItems()
        let overflowStart = CFAbsoluteTimeGetCurrent()
        overflowPanel.show(items: overflowItems, selectedIndex: 60)
        print("overflow panel: 120 tiles in "
            + "\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - overflowStart) * 1000))ms, "
            + "frame \(overflowPanel.frame)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let contentView = overflowPanel.contentView {
                write(contentView, "switcher-overflow")
            }
            overflowPanel.hide()
        }

        // preview appearance, populated with synthetic window images (real
        // captures need Screen Recording; the layout under test is identical)
        let savedMode = Preferences.shared.appearanceMode
        Preferences.shared.appearanceMode = .windowPreviews
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let previewPanel = SwitcherPanel()
            previewPanel.appearance = NSAppearance(named: appearanceName)
            let previewItems = demoItems()
            previewPanel.show(items: previewItems, selectedIndex: 1)
            for (index, item) in previewItems.enumerated() where index != 4 {
                // one tile (index 4) is deliberately left without a preview to show
                // the placeholder fallback; the rest get varied aspect ratios
                let wide = index % 3 != 2
                let size = wide ? NSSize(width: 456, height: 286) : NSSize(width: 240, height: 380)
                previewPanel.updatePreview(id: item.id, image: syntheticWindowImage(size: size, seed: index))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if let contentView = previewPanel.contentView {
                    write(contentView, "switcher-previews-\(suffix)")
                }
                previewPanel.hide()
            }
        }
        Preferences.shared.appearanceMode = savedMode

        var pending = 0
        let finishOne = {
            pending -= 1
            if pending == 0 {
                exit(0)
            }
        }
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let panel = SwitcherPanel()
            panel.appearance = NSAppearance(named: appearance)
            panel.show(items: demoItems(), selectedIndex: 1)
            pending += 1
            // give SwiftUI a few runloop turns to lay out before rasterizing
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let contentView = panel.contentView {
                    write(contentView, "switcher-\(suffix)")
                }
                panel.hide()
                finishOne()
            }
        }
        for (name, viewController) in SettingsWindowController.makePaneViewControllers() {
            let window = NSWindow(contentViewController: viewController)
            window.appearance = NSAppearance(named: .aqua)
            window.orderBack(nil)
            pending += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let contentView = window.contentView {
                    write(contentView, "settings-\(name)")
                }
                window.orderOut(nil)
                finishOne()
            }
        }
        app.run()
    }

    /// A plausible fake window (title bar + content blocks) for layout renders.
    private static func syntheticWindowImage(size: NSSize, seed: Int) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.quaternaryLabelColor.setFill()
        NSRect(x: 0, y: size.height - 24, width: size.width, height: 24).fill()
        for (offset, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 8 + CGFloat(offset) * 14, y: size.height - 17,
                                        width: 9, height: 9)).fill()
        }
        NSColor.tertiaryLabelColor.withAlphaComponent(0.25).setFill()
        var y = size.height - 48
        var lineSeed = seed
        while y > 12 {
            let width = size.width * (0.35 + CGFloat((lineSeed * 37) % 50) / 100)
            NSBezierPath(roundedRect: NSRect(x: 14, y: y, width: min(width, size.width - 28), height: 9),
                         xRadius: 4, yRadius: 4).fill()
            y -= 18
            lineSeed += 1
        }
        image.unlockFocus()
        return image
    }

    private static func icon(_ bundleID: String) -> NSImage {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }

    /// Covers the review checklist: several windows of the same app, duplicate and
    /// long titles, entries with and without tab counts, and the Settings entry.
    private static func demoItems() -> [SwitcherItem] {
        let rows: [(String, String, String, Int?)] = [
            ("UserResourceMapper.java", "IntelliJ IDEA", "com.jetbrains.intellij", nil),
            ("Apple Human Interface Guidelines — Materials and Vibrancy", "Safari", "com.apple.Safari", 7),
            ("GitHub — Safari", "Safari", "com.apple.Safari", 12),
            ("Downloads", "Finder", "com.apple.finder", 3),
            ("untitled", "TextEdit", "com.apple.TextEdit", nil),
            ("untitled", "TextEdit", "com.apple.TextEdit", nil),
            ("main.swift — windowhop — zsh — 118×34", "Terminal", "com.apple.Terminal", 2),
            ("WindowHop Settings", "WindowHop", "com.perso.windowhop", nil),
        ]
        return rows.enumerated().map { index, row in
            let tileIcon = row.2 == "com.perso.windowhop"
                ? (NSImage(contentsOfFile: "Support/AppIcon.icns")
                    ?? Bundle.main.image(forResource: "AppIcon") ?? icon(row.2))
                : icon(row.2)
            return SwitcherItem(id: index, window: nil, title: row.0, appName: row.1,
                                icon: tileIcon, tabCount: row.3)
        }
    }

    /// Synthetic 120-window list for overflow and responsiveness checks.
    private static func manyDemoItems() -> [SwitcherItem] {
        let apps = [("Safari", "com.apple.Safari"), ("Finder", "com.apple.finder"),
                    ("Terminal", "com.apple.Terminal"), ("Notes", "com.apple.Notes"),
                    ("TextEdit", "com.apple.TextEdit"), ("Mail", "com.apple.mail")]
        return (0..<120).map { index in
            let app = apps[index % apps.count]
            return SwitcherItem(id: index, window: nil,
                                title: "Window \(index + 1) — \(app.0)",
                                appName: app.0, icon: icon(app.1),
                                tabCount: index % 7 == 0 ? (index % 9) + 2 : nil)
        }
    }

    private static func runPanelDemo(dark: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let panel = SwitcherPanel()
        DispatchQueue.main.async {
            let items = CommandLine.arguments.contains("--many") ? manyDemoItems() : demoItems()
            let showStart = CFAbsoluteTimeGetCurrent()
            panel.show(items: items, selectedIndex: 1)
            let showMs = (CFAbsoluteTimeGetCurrent() - showStart) * 1000
            print("demo panel: \(items.count) tiles in \(String(format: "%.1f", showMs))ms, frame \(panel.frame)")
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
