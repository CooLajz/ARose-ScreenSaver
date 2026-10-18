import AppKit
import ServiceManagement
import Sparkle

final class MacUpdates: NSObject, SPUUpdaterDelegate, NSMenuItemValidation {
    static let shared = MacUpdates()
    private let defaults = UserDefaults.standard
    private let service = SMAppService.agent(plistName: "cz.coolajz.ARose.UpdateCheck.plist")
    private var headless = false
    private var updaterStarted = false
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    var installed: Bool {
        Self.isInstalledApplication(Bundle.main.bundleURL)
    }
    static func isInstalledApplication(_ url: URL) -> Bool {
        ScreenSaverInstallation.isInstalled(url)
    }
    @objc func openScreenSaverSettings() {
        if #available(macOS 14.0, *) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!)
        } else {
            alert("Use the standalone screen saver on macOS 13.",
                  "Download ARose.saver from GitHub Releases and open it in Finder.")
        }
    }
    func registerScreenSaver(headless: Bool = false, completion: @escaping () -> Void = {}) {
        // A Sparkle relaunch must finish recovery even if installation outlasted
        // user activity. Keep this temporary background process until unlock.
        let pendingUpdate = defaults.bool(forKey: ScreenSaverLifecycle.updatePendingKey)
        ScreenSaverLifecycle.shared.prepare(canWait: !headless || pendingUpdate) { result in
            if case .failure(let error) = result, !headless {
                self.alert("Unable to refresh the screen saver.", error.localizedDescription)
            }
            completion()
        }
    }
    private func alert(_ message: String, _ detail: String = "") {
        let alert = NSAlert(); alert.messageText = roseText(message); alert.informativeText = roseText(detail)
        alert.addButton(withTitle: roseText("OK")); alert.runModal()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleWeekly) { menuItem.state = defaults.bool(forKey: "weeklyUpdates") ? .on : .off }
        return true
    }
    @objc func manualCheck() { check(background: false) }
    @objc func toggleWeekly() {
        do {
            if defaults.bool(forKey: "weeklyUpdates") {
                try service.unregister(); defaults.set(false, forKey: "weeklyUpdates")
            } else {
                guard installed else { alert("Install ARose first.", "Move ARose to Applications, then quit and reopen the app."); return }
                try service.register()
                defaults.set(true, forKey: "weeklyUpdates")
                if service.status == .requiresApproval {
                    alert("Allow ARose background activity in System Settings.")
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch { alert("Unable to change automatic update checks.", error.localizedDescription) }
    }
    func check(background: Bool, headless: Bool = false) {
        self.headless = headless
        if headless, NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }) { NSApp.terminate(nil); return }
        if background {
            let session = CGSessionCopyCurrentDictionary() as? [String: Any]
            let locked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
            // Defer to an active, unlocked session. Never wake the display or
            // interrupt a screen saver. The hourly agent retries locally.
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
            guard defaults.bool(forKey: "weeklyUpdates"), !locked, idle < 60,
                  ARoseUpdatePolicy.due(last: defaults.double(forKey: "lastUpdateAttempt"), now: Date().timeIntervalSince1970) else {
                if headless { NSApp.terminate(nil) }; return
            }
        }
        guard installed else {
            if headless { NSApp.terminate(nil) }
            else if !background { alert("Install ARose first.", "Move ARose to Applications, then quit and reopen the app.") }
            return
        }
        if updaterStarted && controller.updater.sessionInProgress { return }
        defaults.set(Date().timeIntervalSince1970, forKey: "lastUpdateAttempt")
        if !updaterStarted { controller.startUpdater(); updaterStarted = true }
        if background { controller.updater.checkForUpdatesInBackground() }
        else { controller.checkForUpdates(nil) }
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if headless { NSApp.terminate(nil) }
    }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        defaults.set(true, forKey: ScreenSaverLifecycle.updatePendingKey)
        defaults.synchronize()
    }
}
