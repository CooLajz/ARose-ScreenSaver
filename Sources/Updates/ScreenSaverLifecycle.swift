import AppKit
import CryptoKit
import OSLog

// Installation identity includes the executable's file identity as well as its
// bytes: removing/reinstalling the very same build also replaces the PK UUID.
enum ScreenSaverInstallation {
    static func isInstalled(_ app: URL) -> Bool {
        let parent = app.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL
        return [URL(fileURLWithPath: "/Applications", isDirectory: true),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
            .contains { $0.standardizedFileURL == parent }
    }

    static func identity(executable: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: executable.path)
        let digest = SHA256.hash(data: try Data(contentsOf: executable)).map { String(format: "%02x", $0) }.joined()
        return "\(executable.path)|\(attributes[.systemNumber]!)|\(attributes[.systemFileNumber]!)|\(digest)"
    }

    static func registration(in listing: String, path: String) -> String? {
        for line in listing.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            if fields.count >= 4, fields.last == Substring(path), UUID(uuidString: String(fields[1])) != nil {
                return String(fields[1])
            }
        }
        return nil
    }

    static func needsRefresh(previous: String?, installation: String, registration: String) -> Bool {
        previous != installation + "|" + registration
    }

    static func canRefresh(onConsole: Bool, locked: Bool, hasSheet: Bool, appActive: Bool, idle: TimeInterval) -> Bool {
        onConsole && !locked && !hasSheet && (appActive || idle < 60)
    }
}

final class ScreenSaverLifecycle {
    static let shared = ScreenSaverLifecycle()
    static let generationKey = "screenSaverHostGeneration.v1"
    static let updatePendingKey = "screenSaverUpdatePending.v1"
    private let log = Logger(subsystem: "cz.coolajz.ARose", category: "Installation")
    private var preparing = false
    private var deferred: Timer?
    private var completions: [(Result<Void, Error>) -> Void] = []

    // Called at every installed-app launch, including Sparkle's background
    // relaunch. No agent, privilege escalation or always-running app is needed.
    func prepare(canWait: Bool = true, completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
        completions.append(completion)
        guard !preparing else { return }
        preparing = true
        guard ScreenSaverInstallation.isInstalled(Bundle.main.bundleURL), #available(macOS 14.0, *),
              let plugin = Bundle.main.builtInPlugInsURL?.appendingPathComponent("ARoseExtension.appex"),
              let bundle = Bundle(url: plugin), let identifier = bundle.bundleIdentifier,
              let executable = bundle.executableURL else { finish(.success(())); return }
        // Never interrupt an idle/locked session or close the app's options.
        // Interactive launches retry when the user returns; background launches
        // leave the generation pending for the next launch/check.
        guard Self.canRefresh else {
            if canWait {
                deferred = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [self] _ in
                    let pending = completions
                    completions = []; preparing = false; deferred = nil
                    prepare(canWait: canWait) { result in pending.forEach { $0(result) } }
                }
            } else { finish(.success(())) }
            return
        }
        let previous = UserDefaults.standard.string(forKey: Self.generationKey)
        DispatchQueue.global(qos: .utility).async { [self] in
            do {
                let installation = try ScreenSaverInstallation.identity(executable: executable)
                var registration = try registeredUUID(identifier: identifier, plugin: plugin)
                if registration == nil {
                    _ = try run("/usr/bin/pluginkit", ["-a", plugin.path])
                    registration = try registeredUUID(identifier: identifier, plugin: plugin)
                }
                guard let registration else { throw Failure("The installed screen saver could not be registered.") }
                guard ScreenSaverInstallation.needsRefresh(previous: previous, installation: installation,
                                                            registration: registration) else {
                    log.notice("Installed extension unchanged; host refresh skipped")
                    DispatchQueue.main.async {
                        UserDefaults.standard.removeObject(forKey: Self.updatePendingKey)
                        self.finish(.success(()))
                    }; return
                }
                // Recheck immediately before signalling. Registration queries
                // can take time and the session may have locked in the meantime.
                DispatchQueue.main.async {
                    guard Self.canRefresh else {
                        let pending = self.completions
                        self.completions = []; self.preparing = false
                        self.prepare(canWait: canWait) { result in pending.forEach { $0(result) } }
                        return
                    }
                    self.refresh(installation: installation, registration: registration)
                }
            } catch {
                log.error("Screen saver preparation failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { self.finish(.failure(error)) }
            }
        }
    }

    private static var canRefresh: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                       eventType: CGEventType(rawValue: UInt32.max)!)
        return ScreenSaverInstallation.canRefresh(
            onConsole: session?[kCGSessionOnConsoleKey as String] as? Bool == true,
            locked: session?["CGSSessionScreenIsLocked"] as? Bool == true,
            hasSheet: NSApp.windows.contains(where: { $0.attachedSheet != nil }),
            appActive: NSApp.isActive, idle: idle)
    }

    private func registeredUUID(identifier: String, plugin: URL) throws -> String? {
        let listing = try run("/usr/bin/pluginkit", ["-m", "-v", "-i", identifier], accepting: [0, 1])
        return ScreenSaverInstallation.registration(in: listing, path: plugin.path)
    }

    private func refresh(installation: String, registration: String) {
        // Settings caches a separate configuration-service UUID. Refreshing
        // only WallpaperAgent repairs animation but leaves its Options blank.
        let settings = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
        let settingsURL = settings?.bundleURL
        DispatchQueue.global(qos: .utility).async { [self] in
            do {
                if let settings, !settings.isTerminated {
                    log.notice("Refreshing open System Settings after extension installation changed")
                    _ = try run("/bin/kill", ["-TERM", String(settings.processIdentifier)])
                    var exited = false
                    for _ in 0..<30 {
                        let current = try run("/usr/bin/pgrep", ["-u", String(getuid()), "-x", "System Settings"], accepting: [0, 1])
                        if !current.split(separator: "\n").contains(Substring(String(settings.processIdentifier))) { exited = true; break }
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                    guard exited else { throw Failure("System Settings did not finish refreshing.") }
                }
                let arguments = ["-u", String(getuid()), "-x", "WallpaperAgent"]
                let oldPIDs = Set(try run("/usr/bin/pgrep", arguments, accepting: [0, 1]).split(separator: "\n"))
                if !oldPIDs.isEmpty {
                    log.notice("Refreshing WallpaperAgent after extension installation changed")
                    // TERM only, current user only. launchd restarts its agent.
                    // Do not touch Dock, pkd or other savers.
                    _ = try run("/usr/bin/killall", ["-u", NSUserName(), "-TERM", "WallpaperAgent"])
                    var exited = false
                    for _ in 0..<30 {
                        let current = Set(try run("/usr/bin/pgrep", arguments, accepting: [0, 1]).split(separator: "\n"))
                        if oldPIDs.isDisjoint(with: current) { exited = true; break }
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                    guard exited else { throw Failure("The screen saver host did not finish refreshing.") }
                }
                DispatchQueue.main.async {
                    if let appURL = settingsURL {
                        self.reopenSettings(at: appURL, installation: installation, registration: registration)
                    } else { self.record(installation: installation, registration: registration) }
                }
            } catch {
                log.error("Screen saver refresh failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { self.finish(.failure(error)) }
            }
        }
    }

    private func reopenSettings(at appURL: URL, installation: String, registration: String, attempt: Int = 0) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        // Launch first, then send the preferences URL through its URL handler.
        // Passing that URL as a document can fail with kLSUnknownErr. LS may
        // also briefly consider the terminated instance to still be exiting.
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    self.log.error("Reopening System Settings attempt \(attempt + 1) failed: \(String(describing: error), privacy: .public)")
                    if attempt < 3 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            self.reopenSettings(at: appURL, installation: installation, registration: registration, attempt: attempt + 1)
                        }
                    } else { self.finish(.failure(error)) }
                    return
                }
                let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!
                if NSWorkspace.shared.open(url) {
                    self.record(installation: installation, registration: registration)
                } else { self.finish(.failure(Failure("System Settings could not reopen the screen saver page."))) }
            }
        }
    }

    private func record(installation: String, registration: String) {
        UserDefaults.standard.set(installation + "|" + registration, forKey: Self.generationKey)
        UserDefaults.standard.removeObject(forKey: Self.updatePendingKey)
        UserDefaults.standard.synchronize()
        log.notice("Screen saver installation ready; host generation saved")
        finish(.success(()))
    }

    private func finish(_ result: Result<Void, Error>) {
        let pending = completions
        completions = []; preparing = false
        pending.forEach { $0(result) }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ description: String) { errorDescription = description }
    }

    private func run(_ executable: String, _ arguments: [String], accepting: Set<Int32> = [0]) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        // All commands are bounded; a stalled registration must not hang launch.
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); timeout.cancel()
        guard accepting.contains(process.terminationStatus) else {
            throw Failure("\(URL(fileURLWithPath: executable).lastPathComponent) failed (\(process.terminationStatus)).")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
