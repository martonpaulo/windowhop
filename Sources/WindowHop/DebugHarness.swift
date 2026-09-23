import AppKit
import WindowHopCore
import WindowHopKit

/// Development/QA harness, reachable only through explicit flags on the binary.
/// - `--demo-switcher [--dark]`: renders the switcher panel with sample rows,
///   without needing Accessibility permission. Used for screenshots and layout QA.
/// - `--dump-windows`: starts the real engine, waits for discovery, prints the
///   switcher list with timings, and exits. Requires Accessibility permission.
/// - `--dump-permissions`: prints the app identity's effective Accessibility and
///   Screen Recording states without prompting.
/// - `--dump-previews`: prints which window-server window each switcher entry is
///   matched to, without capturing any image. Requires both permissions.
/// - `--demo-settings [pane] [--light | --dark]`: shows the real Settings window
///   (the toolbar only exists on a real window, so it cannot be rasterized
///   offscreen) and prints the `scripts/lib/capture.sh` handshake. The
///   appearance flag pins Light or Dark; without it the window follows the
///   system, so a published capture would depend on the operator's setting.
@MainActor
enum DebugHarness {
    /// The harness's own settings domain, cleared on every run, so a render or a
    /// dump starts from `Preferences.Defaults` and never reads or changes the
    /// person's real preferences.
    private static let preferencesSuiteName = "WindowHop.DebugHarness"

    private static func makePreferences(suite: String = preferencesSuiteName) -> Preferences {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return Preferences(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    /// The Settings content over the harness's own settings, with an updater
    /// that is never started, as in any development build.
    private static func makeSettingsDependencies(_ preferences: Preferences) -> SettingsDependencies {
        SettingsDependencies(
            preferences: preferences,
            restorer: SettingsDefaultsRestorer(
                preferences: preferences,
                applyAutomaticUpdateChecks: { _ in }),
            updateManager: UpdateManager(preferences: preferences),
            setShortcutRecordingActive: { _ in },
            evictPreviews: {})
    }

    /// A `swift build` binary has no bundle, so AppKit would hand Settings the
    /// generic executable icon. Renders and published captures show the real one.
    private static func useRepositoryAppIcon() {
        guard Bundle.main.bundleIdentifier == nil,
            let icon = NSImage(contentsOfFile: "Support/AppIcon.icns")
        else { return }
        NSApplication.shared.applicationIconImage = icon
    }

    static func runIfRequested(_ arguments: [String]) -> Bool {
        if arguments.contains("--demo-switcher") {
            runPanelDemo(dark: arguments.contains("--dark"))
            return true
        }
        if let flagIndex = arguments.firstIndex(of: "--demo-settings") {
            let pane = arguments.count > flagIndex + 1 ? arguments[flagIndex + 1] : nil
            let appearance: NSAppearance.Name? =
                arguments.contains("--light")
                ? .aqua : arguments.contains("--dark") ? .darkAqua : nil
            runSettingsDemo(pane: pane?.hasPrefix("--") == true ? nil : pane, appearance: appearance)
            return true
        }
        if arguments.contains("--dump-previews") {
            runPreviewMatchingDump()
            return true
        }
        if arguments.contains("--dump-windows") {
            runWindowDump()
            return true
        }
        if arguments.contains("--dump-permissions") {
            runPermissionDump()
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
        useRepositoryAppIcon()
        let outputURL = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        // Offscreen panels have no screen, so they would otherwise rasterize at
        // 1x and every published screenshot would be soft. Drawing into an
        // explicitly oversized bitmap whose logical size stays in points makes
        // AppKit render text, icons and strokes at this scale natively.
        let renderScale: CGFloat = 3

        func write(_ view: NSView, _ name: String) {
            let size = view.bounds.size
            guard size.width > 0, size.height > 0,
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int((size.width * renderScale).rounded()),
                    pixelsHigh: Int((size.height * renderScale).rounded()),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: rep)
            else { return }
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: renderScale, y: renderScale)
            view.displayIgnoringOpacity(view.bounds, in: context)
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: outputURL.appendingPathComponent("\(name).png"))
                writeLine(
                    "wrote \(name).png (\(rep.pixelsWide)x\(rep.pixelsHigh) px, "
                        + "\(Int(size.width))x\(Int(size.height)) pt)")
            }
        }

        // Each panel reads its own settings, so the preview renders and the
        // permission-free App Icons renders never share an appearance mode.
        let preferences = makePreferences()
        let previewSuiteName = preferencesSuiteName + ".Previews"
        let previewPreferences = makePreferences(suite: previewSuiteName)
        previewPreferences.appearanceMode = .windowPreviews
        var pending = 0
        let finishOne = {
            pending -= 1
            if pending == 0 {
                UserDefaults.standard.removePersistentDomain(forName: preferencesSuiteName)
                UserDefaults.standard.removePersistentDomain(forName: previewSuiteName)
                exit(0)
            }
        }

        // overflow check: 120 synthetic windows in a wrapping, vertically scrolling grid
        // synthetic images only: nothing is captured, so the caches stay empty
        let previews = PreviewProvider(preferences: preferences)
        let overflowPanel = SwitcherPanel(
            preferences: preferences, previews: previews,
            rasterizableBackground: true)
        overflowPanel.appearance = NSAppearance(named: .aqua)
        let overflowItems = manyDemoItems()
        let overflowStart = CFAbsoluteTimeGetCurrent()
        overflowPanel.show(
            items: overflowItems,
            selectedIndex: 60,
            presentationMode: .persistent)
        pending += 1
        writeLine(
            "overflow panel: 120 tiles in "
                + "\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - overflowStart) * 1000))ms, "
                + "frame \(overflowPanel.frame)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            overflowPanel.prepareCloseForRendering(at: nil)
            if let contentView = overflowPanel.contentView {
                write(contentView, "switcher-overflow")
            }
            overflowPanel.hide()
            finishOne()
        }

        // preview appearance, populated with synthetic window images (real
        // captures need Screen Recording; the layout under test is identical)
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let previewPanel = SwitcherPanel(
                preferences: previewPreferences,
                previews: PreviewProvider(preferences: previewPreferences),
                rasterizableBackground: true)
            previewPanel.appearance = NSAppearance(named: appearanceName)
            // Wrapping otherwise follows whatever display the developer has, so
            // the published preview image would be one long strip on an
            // ultrawide and two rows on a laptop. Fix the grid instead.
            previewPanel.sharedColumnLimit = 4
            let previewItems = demoItems()
            previewPanel.show(
                items: previewItems,
                selectedIndex: 1,
                presentationMode: .persistent)
            pending += 1
            for (index, item) in previewItems.enumerated() where index != 4 && index != 5 {
                // Index 4 is an explicit unavailable fallback; index 5 remains
                // loading. The rest get varied source aspect ratios.
                let wide = index % 3 != 2
                let size = wide ? NSSize(width: 456, height: 286) : NSSize(width: 240, height: 380)
                previewPanel.updatePreview(id: item.id, image: syntheticWindowImage(size: size, seed: index))
            }
            previewPanel.updatePreviewUnavailable(id: previewItems[4].id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                // The documented loaded-preview screenshot also exercises the
                // exact top-left close geometry without private data or annotations.
                previewPanel.prepareCloseForRendering(at: 2)
                if let contentView = previewPanel.contentView {
                    write(contentView, "switcher-previews-\(suffix)")
                }
                let expandedImage = syntheticWindowImage(
                    size: NSSize(width: 760, height: 480), seed: 1)
                previewPanel.showExpandedPreview(
                    id: previewItems[1].id,
                    image: expandedImage)
                if let contentView = previewPanel.contentView {
                    write(contentView, "switcher-expanded-\(suffix)")
                }
                previewPanel.hideExpandedPreview()
                previewPanel.setPreviewPermissionStatus(.denied)
                if let contentView = previewPanel.contentView {
                    write(contentView, "switcher-permission-blocked-\(suffix)")
                }
                previewPanel.hide()
                finishOne()
            }
        }
        // Standard switcher renders always exercise the permission-free default,
        // independent of the developer's persisted local preference.
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let panel = SwitcherPanel(
                preferences: preferences, previews: previews,
                rasterizableBackground: true)
            panel.appearance = NSAppearance(named: appearance)
            // one row, regardless of the developer's display width
            panel.sharedColumnLimit = demoItems().count
            panel.show(
                items: demoItems(),
                selectedIndex: 1,
                presentationMode: .persistent)
            pending += 1
            // give SwiftUI a few runloop turns to lay out before rasterizing
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                panel.prepareCloseForRendering(at: nil)
                if let contentView = panel.contentView {
                    write(contentView, "switcher-\(suffix)")
                }
                panel.hide()
                finishOne()
            }
        }
        // The real multi-pane controller, so every render carries the window's
        // own title bar and pane toolbar rather than a bare content view.
        let settingsDependencies = makeSettingsDependencies(preferences)
        let settingsContent = SettingsWindowController.makeContentViewController(settingsDependencies)
        let paneNames = SettingsWindowController.makePaneViewControllers(settingsDependencies)
            .map { $0.name }
        if let tabs = settingsContent as? NSTabViewController {
            let settingsWindow = NSWindow(contentViewController: tabs)
            settingsWindow.styleMask.insert([.titled, .closable])
            settingsWindow.orderBack(nil)
            pending += 1
            // every pane in Light, then every pane in Dark
            let renders = [("", NSAppearance.Name.aqua), ("-dark", .darkAqua)].flatMap { suffix, appearance in
                paneNames.indices.map { (index: $0, name: paneNames[$0] + suffix, appearance: appearance) }
            }
            var next = 0
            func renderNextPane() {
                guard next < renders.count else {
                    settingsWindow.orderOut(nil)
                    finishOne()
                    return
                }
                let render = renders[next]
                next += 1
                settingsWindow.appearance = NSAppearance(named: render.appearance)
                tabs.selectedTabViewItemIndex = render.index
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    if let frameView = settingsWindow.contentView?.superview {
                        write(frameView, "settings-\(render.name)")
                    }
                    renderNextPane()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: renderNextPane)
        }
        for (name, viewController) in [(String, NSViewController)]() {
            let window = NSWindow(contentViewController: viewController)
            window.appearance = NSAppearance(named: .aqua)
            window.orderBack(nil)
            pending += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let contentView = window.contentView?.superview ?? window.contentView {
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
            NSBezierPath(
                ovalIn: NSRect(
                    x: 8 + CGFloat(offset) * 14, y: size.height - 17,
                    width: 9, height: 9)
            ).fill()
        }
        NSColor.tertiaryLabelColor.withAlphaComponent(0.25).setFill()
        var y = size.height - 48
        var lineSeed = seed
        while y > 12 {
            let width = size.width * (0.35 + CGFloat((lineSeed * 37) % 50) / 100)
            NSBezierPath(
                roundedRect: NSRect(x: 14, y: y, width: min(width, size.width - 28), height: 9),
                xRadius: 4, yRadius: 4
            ).fill()
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

    /// One synthetic switcher row of the demo panel.
    private struct DemoRow {
        let title: String
        let appName: String
        let bundleID: String
        let tabCount: Int?
        let documentPath: String?
        /// WindowHop's own row, whose tile uses the app icon.
        let isOwnSettings: Bool

        init(
            _ title: String, _ appName: String, _ bundleID: String, _ tabCount: Int?,
            _ documentPath: String?, _ isOwnSettings: Bool
        ) {
            self.title = title
            self.appName = appName
            self.bundleID = bundleID
            self.tabCount = tabCount
            self.documentPath = documentPath
            self.isOwnSettings = isOwnSettings
        }
    }

    /// Covers the review checklist: several windows of the same app, duplicate and
    /// long titles, entries with and without tab counts, and the Settings entry.
    /// The duplicate TextEdit pair carries documents in different folders, so the
    /// tiles show the CollisionLabel qualifier the store would produce.
    private static func demoItems() -> [SwitcherItem] {
        let rows = [
            DemoRow("Project Plan", "Notes", "com.apple.Notes", nil, nil, false),
            DemoRow("Apple Design Resources", "Safari", "com.apple.Safari", 7, nil, false),
            DemoRow("Window Management Guide", "Safari", "com.apple.Safari", 12, nil, false),
            DemoRow("Downloads", "Finder", "com.apple.finder", 3, nil, false),
            DemoRow("Notes.txt", "TextEdit", "com.apple.TextEdit", nil, "file:///Users/demo/Work/Notes.txt", false),
            DemoRow("Notes.txt", "TextEdit", "com.apple.TextEdit", nil, "file:///Users/demo/Personal/Notes.txt", false),
            DemoRow("Terminal", "Terminal", "com.apple.Terminal", 2, nil, false),
            DemoRow("WindowHop Settings", "WindowHop", "WindowHop", nil, nil, true),
        ]
        let labels = CollisionLabel.labels(
            for: rows.map {
                CollisionLabel.Entry(appId: $0.bundleID, title: $0.title, documentPath: $0.documentPath)
            })
        return rows.enumerated().map { index, row in
            let tileIcon =
                row.isOwnSettings
                ? (NSImage(contentsOfFile: "Support/AppIcon.icns")
                    ?? Bundle.main.image(forResource: "AppIcon") ?? icon(row.bundleID))
                : icon(row.bundleID)
            return SwitcherItem(
                id: index, window: nil, title: row.title, displayTitle: labels[index],
                appName: row.appName, icon: tileIcon, tabCount: row.tabCount)
        }
    }

    /// Synthetic 120-window list for overflow and responsiveness checks.
    private static func manyDemoItems() -> [SwitcherItem] {
        let apps = [
            ("Safari", "com.apple.Safari"), ("Finder", "com.apple.finder"),
            ("Terminal", "com.apple.Terminal"), ("Notes", "com.apple.Notes"),
            ("TextEdit", "com.apple.TextEdit"), ("Mail", "com.apple.mail"),
        ]
        return (0..<120).map { index in
            let app = apps[index % apps.count]
            return SwitcherItem(
                id: index, window: nil,
                title: "Window \(index + 1) — \(app.0)",
                appName: app.0, icon: icon(app.1),
                tabCount: index % 7 == 0 ? (index % 9) + 2 : nil)
        }
    }

    /// Shows the real switcher panel on screen and keeps it up.
    /// `--previews` uses the Window Previews appearance with synthetic snapshots,
    /// `--expanded` adds the dwell presentation, and `--columns N` pins the grid.
    /// `scripts/capture-screenshots.sh` drives this for the published images.
    private static func runPanelDemo(dark: Bool) {
        let arguments = CommandLine.arguments
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let previews = arguments.contains("--previews")
        let expanded = arguments.contains("--expanded")
        let preferences = makePreferences()
        preferences.appearanceMode = previews ? .windowPreviews : .appIcons
        let panel = SwitcherPanel(
            preferences: preferences,
            previews: PreviewProvider(preferences: preferences))
        panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if let index = arguments.firstIndex(of: "--columns"), arguments.count > index + 1,
            let columns = Int(arguments[index + 1])
        {
            panel.sharedColumnLimit = columns
        }
        DispatchQueue.main.async {
            let items = arguments.contains("--many") ? manyDemoItems() : demoItems()
            let showStart = CFAbsoluteTimeGetCurrent()
            panel.show(
                items: items,
                selectedIndex: 1,
                presentationMode: .cycling)
            let showMs = (CFAbsoluteTimeGetCurrent() - showStart) * 1000
            writeLine("demo panel: \(items.count) tiles in \(String(format: "%.1f", showMs))ms, frame \(panel.frame)")
            if previews {
                for (index, item) in items.enumerated() where index != 4 && index != 5 {
                    let wide = index % 3 != 2
                    let size =
                        wide
                        ? NSSize(width: 456, height: 286)
                        : NSSize(width: 240, height: 380)
                    panel.updatePreview(
                        id: item.id,
                        image: syntheticWindowImage(size: size, seed: index))
                }
                panel.updatePreviewUnavailable(id: items[4].id)
                if expanded {
                    panel.showExpandedPreview(
                        id: items[1].id,
                        image: syntheticWindowImage(size: NSSize(width: 760, height: 480), seed: 1))
                } else {
                    panel.prepareCloseForRendering(at: 2)
                }
            }
            // let the panel finish its fade and layout before announcing it
            DispatchQueue.main.asyncAfter(deadline: .now() + captureSettleDelay) {
                announceCaptureReady(panel, reportsKey: false)
            }
        }
        app.run()
    }

    /// Time a demo window gets to finish fading in and laying out before it announces
    /// itself as ready to capture.
    private static let captureSettleDelay: TimeInterval = 1.2

    /// Prints the handshake `scripts/lib/capture.sh` waits for (skill-deck's canonical
    /// capture protocol): the backing scale, which must be Retina, the window number for
    /// `screencapture -l`, optionally whether the window is key, then `READY`. The process
    /// stays alive for the capture, so stdout is flushed rather than left in its buffer.
    private static func announceCaptureReady(_ window: NSWindow, reportsKey: Bool) {
        writeLine("SCALE \(window.backingScaleFactor)")
        writeLine("WINDOW_ID \(window.windowNumber)")
        if reportsKey { writeLine("KEY \(window.isKeyWindow)") }
        writeLine("READY")
    }

    private static func runWindowDump() {
        guard AccessibilityPermission.isGranted else {
            writeLine("dump-windows: Accessibility permission not granted for this process")
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        BackgroundWork.start()
        let started = Date()
        let preferences = makePreferences()
        let store = WindowStore(
            preferences: preferences,
            previews: PreviewProvider(preferences: preferences))
        store.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let snapshotStart = Date()
            let items = store.snapshot()
            let snapshotMs = Date().timeIntervalSince(snapshotStart) * 1000
            let totalMs = Date().timeIntervalSince(started) * 1000
            writeLine(
                "discovered \(store.windows.count) windows "
                    + "(\(items.count) eligible) within \(String(format: "%.0f", totalMs))ms of engine start; "
                    + "snapshot took \(String(format: "%.3f", snapshotMs))ms")
            for (index, item) in items.enumerated() {
                let tabs = item.tabCount.map { " [\($0) tabs]" } ?? ""
                writeLine("\(index): \(item.appName) — \(item.title)\(tabs)")
            }
            exit(0)
        }
        app.run()
    }

    /// Shows the real Settings window and keeps it up. Used for documentation
    /// captures, which need the window's toolbar and title bar.
    private static func runSettingsDemo(pane: String?, appearance: NSAppearance.Name?) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        useRepositoryAppIcon()
        if let appearance { app.appearance = NSAppearance(named: appearance) }
        let controller = SettingsWindowController.makeContentViewController(
            makeSettingsDependencies(makePreferences()), selecting: pane)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        // Published captures keep the traffic lights and drop the words: the product's name
        // is already beside every image, and the pane is named by its selected toolbar item.
        window.titleVisibility = .hidden
        window.center()
        app.activate()
        window.makeKeyAndOrderFront(nil)
        // A capture taken while the window is not key documents a greyed-out
        // title bar and inactive controls, so claim focus once more after the
        // first run-loop turns and only then announce readiness. The handshake
        // reports KEY, so the capture refuses a window that never became key.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            writeLine("settings window \(Int(window.frame.width))x\(Int(window.frame.height))")
            DispatchQueue.main.asyncAfter(deadline: .now() + captureSettleDelay) {
                announceCaptureReady(window, reportsKey: true)
            }
        }
        app.run()
    }

    /// Prints the real AX-entry → window-server-window pairing `PreviewProvider`
    /// would capture from. No image is captured, kept, or written.
    private static func runPreviewMatchingDump() {
        guard AccessibilityPermission.isGranted else {
            writeLine("dump-previews: Accessibility permission not granted for this process")
            exit(1)
        }
        guard ScreenRecordingPermission.status.isAuthorized else {
            writeLine("dump-previews: Screen Recording permission not granted for this process")
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        BackgroundWork.start()
        let preferences = makePreferences()
        let previews = PreviewProvider(preferences: preferences)
        let store = WindowStore(preferences: preferences, previews: previews)
        store.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let items = store.snapshot()
            previews.dumpMatching(items: items) { lines in
                for line in lines { writeLine(line) }
                exit(0)
            }
        }
        app.run()
    }

    private static func runPermissionDump() {
        let screenRecording: String
        switch ScreenRecordingPermission.status {
        case .authorized: screenRecording = "authorized"
        case .notDetermined: screenRecording = "not-determined"
        case .denied: screenRecording = "denied"
        case .restricted: screenRecording = "restricted"
        }
        writeLine("accessibility=\(AccessibilityPermission.isGranted ? "authorized" : "unavailable")")
        writeLine("screen-recording=\(screenRecording)")
    }
}
