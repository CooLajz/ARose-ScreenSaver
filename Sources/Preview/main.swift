import AppKit
import ScreenSaver

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var rose: ARoseView!
    var timer: Timer?
    var updateTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--check-background") {
            guard !NSWorkspace.shared.runningApplications.contains(where: {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }) else { NSApp.terminate(nil); return }
            // Sparkle preserves launch arguments when restarting a background
            // update check. Prepare the new extension before this process exits.
            MacUpdates.shared.registerScreenSaver(headless: true) {
                MacUpdates.shared.check(background: true, headless: true)
            }
            return
        }
        MacUpdates.shared.registerScreenSaver()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "ARose — Amiga 1995"
        let accessory = NSTitlebarAccessoryViewController()
        let updates = NSButton(title: roseText("Check for Updates…"), target: MacUpdates.shared, action: #selector(MacUpdates.manualCheck))
        updates.bezelStyle = .rounded
        let settingsButton = NSButton(title: roseText("Settings…"), target: self, action: #selector(settings))
        settingsButton.bezelStyle = .rounded
        let bar = NSStackView(views: [updates, settingsButton])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.frame = NSRect(x: 0, y: 0, width: bar.fittingSize.width + 24, height: 32)
        accessory.view = bar; accessory.layoutAttribute = .bottom
        window.addTitlebarAccessoryViewController(accessory)
        window.minSize = NSSize(width: 400, height: 320)
        window.collectionBehavior = [.fullScreenPrimary]
        rose = ARoseView(frame: window.contentView!.bounds, isPreview: false,
                         settings: UserDefaults.standard)!
        rose.figureStorageKey = "previewFigureState.v1"
        rose.startAnimation()
        rose.autoresizingMask = [.width, .height]
        window.contentView = rose
        window.center(); window.makeKeyAndOrderFront(nil)
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        for (title, action) in [("Screen Saver Settings…", #selector(MacUpdates.openScreenSaverSettings)),
                                 ("Check for Updates…", #selector(MacUpdates.manualCheck)),
                                 ("Check automatically every week", #selector(MacUpdates.toggleWeekly))] {
            let item = appMenu.addItem(withTitle: roseText(title), action: action, keyEquivalent: "")
            item.target = MacUpdates.shared
        }
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: roseText("Quit ARose"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let viewItem = NSMenuItem(); menu.addItem(viewItem)
        let viewMenu = NSMenu(title: roseText("Pattern")); viewItem.submenu = viewMenu
        for (title, action, key) in [(roseText("Settings…"), #selector(settings), ","),
                                     (roseText("Pause / Resume"), #selector(pause), "p"),
                                     (roseText("Restart"), #selector(restart), "r"),
                                     (roseText("Advance Animation"), #selector(advance), "n"),
                                     (roseText("Full Screen"), #selector(fullScreen), "f")] {
            let item = viewMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
        }
        NSApp.mainMenu = menu
        timer = Timer(timeInterval: 1.0 / 50.0, repeats: true) { [weak self] _ in self?.rose.animateOneFrame() }
        RunLoop.main.add(timer!, forMode: .common)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MacUpdates.shared.check(background: true)
        }
        MacUpdates.shared.check(background: true)
        NSApp.activate(ignoringOtherApps: true)

    }
    @objc func settings() {
        guard window.attachedSheet == nil else { return }
        if let sheet = rose.configureSheet { window.beginSheet(sheet) }
    }
    @objc func pause() { rose.paused.toggle() }
    @objc func restart() { rose.restartAnimation() }
    @objc func advance() { rose.advanceFrames(500) }
    @objc func fullScreen() { window.toggleFullScreen(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); updateTimer?.invalidate(); rose?.stopAnimation() }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(CommandLine.arguments.contains("--check-background") ? .accessory : .regular)
app.run()
