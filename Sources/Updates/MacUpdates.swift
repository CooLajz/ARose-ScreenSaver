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
    var installed: Bool { Bundle.main.bundleURL.standardizedFileURL == Self.applicationURL.standardizedFileURL }
    static var applicationURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/ARose Preview.app")
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
                guard installed else { alert("Install ARose first.", "Use Install ARose… before enabling weekly checks."); return }
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
            else if !background { alert("Install ARose first.", "Use Install ARose… before checking for updates.") }
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
    func synchronizeSaver() {
        guard installed, defaults.bool(forKey: "managedSaver") else { return }
        let source = Bundle.main.resourceURL!.appendingPathComponent("ARose.saver")
        let destination = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/ARose.saver")
        let newVersion = Bundle(url: source)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let oldVersion = Bundle(url: destination)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard ARoseUpdatePolicy.shouldInstallSaver(embeddedBuild: newVersion, installedBuild: oldVersion) else { return }
        do { try replace(source: source, destination: destination) }
        catch { alert("Installation failed.", error.localizedDescription) }
    }
    @objc func install() {
        let fm = FileManager.default
        let source = Bundle.main.resourceURL!.appendingPathComponent("ARose.saver")
        guard fm.fileExists(atPath: source.path) else {
            alert("This copy does not include the installer.", "Download the installation package from GitHub Releases."); return
        }
        do {
            if !installed {
                if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL == Self.applicationURL.standardizedFileURL }) {
                    alert("Quit the installed ARose app before installing this version."); return
                }
                try replace(source: Bundle.main.bundleURL, destination: Self.applicationURL)
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.arguments = ["--install-saver"]
                NSWorkspace.shared.openApplication(at: Self.applicationURL, configuration: configuration) { _, error in
                    DispatchQueue.main.async {
                        if let error { self.alert("Installation failed.", error.localizedDescription) }
                        else { NSApp.terminate(nil) }
                    }
                }
                return
            }
            let destination = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/ARose.saver")
            try replace(source: source, destination: destination)
            defaults.set(true, forKey: "managedSaver")
            alert("ARose was installed for your user account.", "Select ARose in System Settings → Screen Saver. If System Settings was already open, quit and reopen it to load the new version.")
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!)
        } catch { alert("Installation failed.", error.localizedDescription) }
    }
    // Stage on the destination volume; retain the previous bundle until commit.
    private func replace(source: URL, destination: URL) throws {
        let fm = FileManager.default, parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".ARose-stage-" + UUID().uuidString)
        let backup = parent.appendingPathComponent(".ARose-backup-" + UUID().uuidString)
        try fm.copyItem(at: source, to: stage)
        defer { try? fm.removeItem(at: stage) }
        let existing = fm.fileExists(atPath: destination.path)
        if existing { try fm.moveItem(at: destination, to: backup) }
        do { try fm.moveItem(at: stage, to: destination) }
        catch { if existing { try? fm.moveItem(at: backup, to: destination) }; throw error }
        if existing { try? fm.removeItem(at: backup) }
    }
}
