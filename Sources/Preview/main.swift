import AppKit
import ScreenSaver
import ServiceManagement

// This window is a passive surface; Finder keeps keyboard and mouse ownership.
final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    var window: NSWindow!
    var rose: ARoseView!
    var timer: Timer?
    var updateTimer: Timer?
    private var desktopWindow: DesktopWindow?
    private var statusItem: NSStatusItem?
    private var wallpaperSettings: NSWindow?
    private var menuOutsideClickMonitor: Any?
    private var workspaceObservers = [NSObjectProtocol]()
    private var screenObserver: NSObjectProtocol?
    private var presentationObserver: NSKeyValueObservation?
    private var occlusionObserver: NSObjectProtocol?
    private var visibilityTimer: Timer?
    private var displaysAsleep = false
    private var sessionInactive = false
    private var screenLocked = false
    private var screenSaverRunning = false
    private var wallpaperActive: Bool { desktopWindow != nil }
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
        UserDefaults.standard.register(defaults: ["pauseForFullScreen": true])
        MacUpdates.shared.registerScreenSaver()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "ARose — Amiga 1995"
        window.isReleasedWhenClosed = false
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
        window.center()
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
                                     (roseText("Full Screen"), #selector(fullScreen), "f"),
                                     (roseText("Live Wallpaper (Experimental)"), #selector(toggleWallpaper), "")] {
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
        observeWorkspace()
        if UserDefaults.standard.bool(forKey: "liveWallpaper") {
            enableWallpaper()
        } else {
            showWindow()
        }

    }
    @objc func settings() {
        if wallpaperActive {
            guard let options = rose.configureSheet else { return }
            wallpaperSettings = options
            options.center()
            options.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard window.attachedSheet == nil else { return }
        if let sheet = rose.configureSheet { window.beginSheet(sheet) }
    }
    @objc func pause() { rose.paused.toggle(); updateSuspension() }
    @objc func restart() { rose.restartAnimation() }
    @objc func advance() { rose.advanceFrames(500) }
    @objc func fullScreen() { window.toggleFullScreen(nil) }
    @objc func toggleWallpaper() {
        if wallpaperActive { showWindow() } else { enableWallpaper() }
    }
    private func enableWallpaper() {
        guard !wallpaperActive, let screen = NSScreen.screens.first else { return }
        // Wait for native full screen / settings to close before reparenting.
        guard !window.styleMask.contains(.fullScreen), window.attachedSheet == nil else { return }
        let desktop = DesktopWindow(contentRect: screen.frame, styleMask: .borderless,
                                    backing: .buffered, defer: false)
        desktop.isReleasedWhenClosed = false
        desktop.backgroundColor = .black
        desktop.hasShadow = false
        desktop.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        desktop.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        desktop.ignoresMouseEvents = true
        desktop.isExcludedFromWindowsMenu = true
        desktopWindow = desktop
        rose.pauseTransitionDuration = 2
        window.orderOut(nil)
        rose.removeFromSuperview()
        desktop.contentView = rose
        rose.frame = NSRect(origin: .zero, size: screen.frame.size)
        rose.maximumPresentationFramesPerSecond = 30
        installStatusItem()
        NSApp.setActivationPolicy(.accessory)
        desktop.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: "liveWallpaper")
        updateVisibilityMonitor()
        updateSuspension()
    }
    @objc func showWindow() {
        // Close a standalone settings panel before changing its hosting mode.
        wallpaperSettings?.close()
        wallpaperSettings = nil
        rose.removeFromSuperview()
        window.contentView = rose
        rose.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
        desktopWindow?.close()
        desktopWindow = nil
        rose.pauseTransitionDuration = 0
        updateVisibilityMonitor()
        rose.maximumPresentationFramesPerSecond = nil
        updateSuspension()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        UserDefaults.standard.set(false, forKey: "liveWallpaper")
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "fanblades", accessibilityDescription: "ARose")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "ARose"
        let menu = NSMenu()
        let title = menu.addItem(withTitle: roseText("ARose · Live Wallpaper"), action: nil, keyEquivalent: "")
        title.isEnabled = false
        for (title, action) in [("Settings…", #selector(settings)),
                                ("Pause / Resume", #selector(pause)),
                                ("Pause for Full Screen Apps", #selector(togglePauseForFullScreen)),
                                ("Restart", #selector(restart)),
                                ("Return to Window", #selector(showWindow)),
                                ("Launch at Login", #selector(toggleLaunchAtLogin))] {
            let entry = menu.addItem(withTitle: roseText(title), action: action, keyEquivalent: "")
            entry.target = self
        }
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: roseText("Quit ARose"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }
    func menuWillOpen(_ menu: NSMenu) {
        removeMenuOutsideClickMonitor()
        // The passive desktop never takes focus. Explicitly end tracking for
        // clicks in other apps, including Finder's desktop without activation.
        menuOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak menu] _ in
            DispatchQueue.main.async { menu?.cancelTracking() }
        }
    }
    func menuDidClose(_ menu: NSMenu) { removeMenuOutsideClickMonitor() }
    private func removeMenuOutsideClickMonitor() {
        if let menuOutsideClickMonitor { NSEvent.removeMonitor(menuOutsideClickMonitor) }
        menuOutsideClickMonitor = nil
    }
    @objc func togglePauseForFullScreen() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "pauseForFullScreen"), forKey: "pauseForFullScreen")
        updateVisibilityMonitor()
        updateSuspension()
    }
    private func updateVisibilityMonitor() {
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        guard wallpaperActive else { return }
        // Also detect an already-running saver/lock, even with fullscreen pause
        // disabled. A retained saver process alone does not mean it is active.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refreshSessionState() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        visibilityTimer = timer
    }
    private func desktopCoverage() -> (screenSaver: Bool, fullScreenApp: Bool) {
        guard let screen = desktopWindow?.screen ?? NSScreen.screens.first,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return (false, false) }
        // Window-server coordinates use a top-left origin, unlike NSScreen.
        let displayBounds = CGDisplayBounds(screenNumber.uint32Value)
        guard !displayBounds.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return (false, false) }
        var fullScreenApp = false
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? NSNumber,
                  pid.int32Value != ProcessInfo.processInfo.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary),
                  bounds.insetBy(dx: -1, dy: -1).contains(displayBounds),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            // System saver/lock surfaces are not regular applications.
            if layer >= CGWindowLevelForKey(.screenSaverWindow) { return (true, fullScreenApp) }
            if UserDefaults.standard.bool(forKey: "pauseForFullScreen"),
               let owner = NSRunningApplication(processIdentifier: pid.int32Value),
               owner.activationPolicy == .regular { fullScreenApp = true }
        }
        return (false, fullScreenApp)
    }
    @objc func toggleLaunchAtLogin() {
        do {
            let service = SMAppService.mainApp
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            } else {
                guard MacUpdates.shared.installed else {
                    showLoginError("Move ARose to Applications, then quit and reopen the app.")
                    return
                }
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch { showLoginError(error.localizedDescription) }
    }
    private func showLoginError(_ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = roseText("Unable to change launch at login.")
        alert.informativeText = roseText(detail)
        alert.addButton(withTitle: roseText("OK"))
        alert.runModal()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleWallpaper):
            menuItem.state = wallpaperActive ? .on : .off
            return !window.styleMask.contains(.fullScreen) && window.attachedSheet == nil
        case #selector(pause): menuItem.state = rose.paused ? .on : .off
        case #selector(togglePauseForFullScreen):
            menuItem.state = UserDefaults.standard.bool(forKey: "pauseForFullScreen") ? .on : .off
        case #selector(toggleLaunchAtLogin):
            switch SMAppService.mainApp.status {
            case .enabled: menuItem.state = .on
            case .requiresApproval: menuItem.state = .mixed
            default: menuItem.state = .off
            }
        case #selector(fullScreen): return !wallpaperActive
        default: break
        }
        return true
    }
    private func observeWorkspace() {
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screensaver.didstart", "com.apple.screensaver.didstop",
                     "com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            distributed.addObserver(self, selector: #selector(systemIdleStateChanged(_:)),
                name: Notification.Name(name), object: nil, suspensionBehavior: .deliverImmediately)
        }
        refreshSessionState()
        // Presentation/Space notifications provide immediate updates; the
        // low-frequency window-bounds check also covers video players.
        presentationObserver = NSApp.observe(\.currentSystemPresentationOptions, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateSuspension() }
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.updateSuspension() })
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil, queue: .main) { [weak self] _ in self?.updateSuspension() }
        for (name, asleep, inactive) in [
            (NSWorkspace.screensDidSleepNotification, true, nil as Bool?),
            (NSWorkspace.screensDidWakeNotification, false, nil),
            (NSWorkspace.sessionDidResignActiveNotification, nil, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, nil, false)
        ] as [(Notification.Name, Bool?, Bool?)] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if let asleep { self.displaysAsleep = asleep }
                if let inactive { self.sessionInactive = inactive }
                self.updateSuspension()
            })
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self, let desktop = self.desktopWindow, let screen = NSScreen.screens.first else { return }
                desktop.setFrame(screen.frame, display: true)
            }
    }
    @objc func systemIdleStateChanged(_ notification: Notification) {
        switch notification.name.rawValue {
        case "com.apple.screensaver.didstart": screenSaverRunning = true
        case "com.apple.screensaver.didstop": screenSaverRunning = false
        case "com.apple.screenIsLocked": screenLocked = true
        case "com.apple.screenIsUnlocked": screenLocked = false; screenSaverRunning = false
        default: return
        }
        updateSuspension()
    }
    private func refreshSessionState() {
        // Same session-state fallback used by the update/saver lifecycle code.
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            screenLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        }
        updateSuspension()
    }
    private func updateSuspension() {
        // The desktop joins every regular Space, but cannot join native
        // fullscreen Spaces. This also works when AppKit omits .fullScreen.
        let fullScreenVisible = desktopWindow.map { !$0.isOnActiveSpace } ?? false
        let inactive = displaysAsleep || sessionInactive || screenLocked
        let coverage = wallpaperActive && !inactive ? desktopCoverage() : (screenSaver: false, fullScreenApp: false)
        let saverPause = screenSaverRunning || coverage.screenSaver
        let fullScreenPause = wallpaperActive && !inactive && !saverPause
            && UserDefaults.standard.bool(forKey: "pauseForFullScreen")
            && (fullScreenVisible || NSApp.currentSystemPresentationOptions.contains(.fullScreen) || coverage.fullScreenApp)
        rose.setPlaybackPaused(inactive || saverPause || rose.paused || fullScreenPause)
        let title = screenLocked ? "ARose · Paused While Locked" : saverPause ? "ARose · Paused for Screen Saver"
            : fullScreenPause ? "ARose · Paused for Full Screen" : "ARose · Live Wallpaper"
        statusItem?.menu?.items.first?.title = roseText(title)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if rose != nil && !wallpaperActive { showWindow() }
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !wallpaperActive }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); updateTimer?.invalidate(); rose?.stopAnimation()
        removeMenuOutsideClickMonitor()
        presentationObserver = nil
        visibilityTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(CommandLine.arguments.contains("--check-background") || UserDefaults.standard.bool(forKey: "liveWallpaper") ? .accessory : .regular)
app.run()
