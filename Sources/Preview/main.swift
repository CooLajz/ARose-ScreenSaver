import AppKit
import ScreenSaver

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var rose: ARoseView!
    var timer: Timer?
    var updateTimer: Timer?
    private var settingsObserver: NSObjectProtocol?
    private var pendingSettingsID: String?
    func applicationDidFinishLaunching(_ notification: Notification) {
        MacUpdates.shared.synchronizeSaver()
        if CommandLine.arguments.contains("--check-background") {
            MacUpdates.shared.check(background: true, headless: true)
            return
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "ARose — Amiga 1995"
        let accessory = NSTitlebarAccessoryViewController()
        let updates = NSButton(title: roseText("Check for Updates…"), target: MacUpdates.shared, action: #selector(MacUpdates.manualCheck))
        updates.bezelStyle = .rounded
        let bar = NSStackView(views: [updates])
        bar.frame = NSRect(x: 0, y: 0, width: 260, height: 32)
        accessory.view = bar; accessory.layoutAttribute = .bottom
        window.addTitlebarAccessoryViewController(accessory)
        window.minSize = NSSize(width: 400, height: 320)
        window.collectionBehavior = [.fullScreenPrimary]
        rose = ARoseView(frame: window.contentView!.bounds, isPreview: false)!
        rose.figureStorageKey = "previewFigureState.v1"
        rose.startAnimation()
        rose.configurationSaved = { [weak self] in
            // Let the local sheet finish before showing the transfer result.
            DispatchQueue.main.async { self?.sendSettings() }
        }
        rose.autoresizingMask = [.width, .height]
        window.contentView = rose
        window.center(); window.makeKeyAndOrderFront(nil)
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        for (title, action) in [("Install ARose…", #selector(MacUpdates.install)),
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
        if CommandLine.arguments.contains("--install-saver") { MacUpdates.shared.install() }
        else if !MacUpdates.shared.installed,
                FileManager.default.fileExists(atPath: Bundle.main.resourceURL!.appendingPathComponent("ARose.saver").path) {
            let alert = NSAlert(); alert.messageText = roseText("Install ARose for your user account?")
            alert.informativeText = roseText("The app and screen saver will be installed without changing your settings. Automatic update checks remain optional.")
            alert.addButton(withTitle: roseText("Install ARose…")); alert.addButton(withTitle: roseText("Not Now"))
            if alert.runModal() == .alertFirstButtonReturn { MacUpdates.shared.install() }
        }
    }
    @objc func settings() {
        guard pendingSettingsID == nil, window.attachedSheet == nil else { return }
        let id = UUID().uuidString
        pendingSettingsID = id
        settingsObserver = DistributedNotificationCenter.default().addObserver(forName: RoseSettingsBridge.response, object: nil, queue: .main) { [weak self] notification in
            guard let self, self.pendingSettingsID == id,
                  let reply = RoseSettingsBridge.decode(notification.object), reply.id == id,
                  let values = reply.values,
                  let defaults = ScreenSaverDefaults(forModuleWithName: "cz.coolajz.ARose") else { return }
            for (key, value) in values { defaults.set(value, forKey: key) }
            defaults.synchronize()
            self.rose.applyConfiguration()
            self.showSettings()
        }
        if let payload = RoseSettingsBridge.encode(.init(id: id, values: nil)) {
            DistributedNotificationCenter.default().postNotificationName(RoseSettingsBridge.request, object: payload, userInfo: nil, deliverImmediately: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard self?.pendingSettingsID == id else { return }
            self?.showSettings()
        }
    }
    private func showSettings() {
        pendingSettingsID = nil
        if let settingsObserver { DistributedNotificationCenter.default().removeObserver(settingsObserver) }
        settingsObserver = nil
        if let sheet = rose.configureSheet { window.beginSheet(sheet) }
    }
    private func sendSettings() {
        guard let defaults = ScreenSaverDefaults(forModuleWithName: "cz.coolajz.ARose") else { return }
        let values = RoseSettingsBridge.snapshot(defaults)
        let id = UUID().uuidString
        pendingSettingsID = id
        if let settingsObserver { DistributedNotificationCenter.default().removeObserver(settingsObserver) }
        settingsObserver = DistributedNotificationCenter.default().addObserver(forName: RoseSettingsBridge.response, object: nil, queue: .main) { [weak self] notification in
            guard let self, self.pendingSettingsID == id,
                  let reply = RoseSettingsBridge.decode(notification.object), reply.id == id,
                  reply.values == values else { return }
            self.finishSettingsTransfer(success: true)
        }
        if let payload = RoseSettingsBridge.encode(.init(id: id, values: values)) {
            DistributedNotificationCenter.default().postNotificationName(RoseSettingsBridge.request, object: payload, userInfo: nil, deliverImmediately: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard self?.pendingSettingsID == id else { return }
            self?.finishSettingsTransfer(success: false)
        }
    }
    private func finishSettingsTransfer(success: Bool) {
        pendingSettingsID = nil
        if let settingsObserver { DistributedNotificationCenter.default().removeObserver(settingsObserver) }
        settingsObserver = nil
        let alert = NSAlert()
        alert.messageText = success ? roseText("Settings received by the system screen saver") : roseText("Settings saved only in the preview")
        alert.informativeText = success
            ? roseText("The running ARose host confirmed that it received and saved the settings.")
            : roseText("The system screen saver did not confirm receipt. Open System Settings → Wallpaper → Screen Saver, select ARose, and leave the preview running. Then save the settings here again.")
        alert.addButton(withTitle: roseText("OK"))
        alert.beginSheetModal(for: window)
    }
    @objc func pause() { rose.paused.toggle() }
    @objc func restart() { rose.reset() }
    @objc func advance() { for _ in 0..<500 { rose.engine.step() }; rose.needsDisplay = true }
    @objc func fullScreen() { window.toggleFullScreen(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); updateTimer?.invalidate(); rose?.stopAnimation() }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(CommandLine.arguments.contains("--check-background") ? .accessory : .regular)
app.run()
