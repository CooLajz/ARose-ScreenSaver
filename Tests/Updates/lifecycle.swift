import Foundation

@main enum LifecycleTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let executable = folder.appendingPathComponent("ARoseExtension")
        try Data("original".utf8).write(to: executable)
        let original = try ScreenSaverInstallation.identity(executable: executable)
        let unchanged = try ScreenSaverInstallation.identity(executable: executable)
        precondition(original == unchanged)
        // A drag-and-drop reinstall of identical bytes must count as a new
        // installation even when bundle version/build were not changed.
        try FileManager.default.moveItem(at: executable, to: folder.appendingPathComponent("old"))
        try Data("original".utf8).write(to: executable)
        let replaced = try ScreenSaverInstallation.identity(executable: executable)
        precondition(original != replaced)
        try Data("updated".utf8).write(to: executable)
        let updated = try ScreenSaverInstallation.identity(executable: executable)
        precondition(replaced != updated)
        let path = "/Applications/ARose.app/Contents/PlugIns/ARoseExtension.appex"
        let uuid = "10D677C1-929B-49DE-BFAA-14C5CFE06536"
        let listing = "+    cz.coolajz.ARose.Preview.ScreenSaver(1.0.3)\t\(uuid)\t2026-10-18 11:36:55 +0000\t\(path)\n (1 plug-in)"
        precondition(ScreenSaverInstallation.registration(in: listing, path: path) == uuid)
        precondition(ScreenSaverInstallation.registration(in: listing, path: "/Volumes/ARose" + path) == nil)
        precondition(ScreenSaverInstallation.registration(in: listing.replacingOccurrences(of: uuid, with: "bad"), path: path) == nil)
        precondition(ScreenSaverInstallation.registration(in: "match: Connection invalid", path: path) == nil)
        let ready = original + "|" + uuid
        precondition(!ScreenSaverInstallation.needsRefresh(previous: ready, installation: original, registration: uuid))
        precondition(ScreenSaverInstallation.needsRefresh(previous: ready, installation: replaced, registration: uuid))
        precondition(ScreenSaverInstallation.needsRefresh(previous: ready, installation: original, registration: UUID().uuidString))
        precondition(ScreenSaverInstallation.needsRefresh(previous: nil, installation: original, registration: uuid))
        precondition(ScreenSaverInstallation.isInstalled(URL(fileURLWithPath: "/Applications/ARose.app")))
        precondition(!ScreenSaverInstallation.isInstalled(URL(fileURLWithPath: "/Volumes/ARose/ARose.app")))
        precondition(!ScreenSaverInstallation.isInstalled(URL(fileURLWithPath: "/private/tmp/ARose.app")))
        precondition(ScreenSaverInstallation.canRefresh(onConsole: true, locked: false, hasSheet: false, appActive: true, idle: 600))
        precondition(ScreenSaverInstallation.canRefresh(onConsole: true, locked: false, hasSheet: false, appActive: false, idle: 10))
        precondition(!ScreenSaverInstallation.canRefresh(onConsole: true, locked: true, hasSheet: false, appActive: true, idle: 0))
        precondition(!ScreenSaverInstallation.canRefresh(onConsole: false, locked: false, hasSheet: false, appActive: true, idle: 0))
        precondition(!ScreenSaverInstallation.canRefresh(onConsole: true, locked: false, hasSheet: true, appActive: true, idle: 0))
        precondition(!ScreenSaverInstallation.canRefresh(onConsole: true, locked: false, hasSheet: false, appActive: false, idle: 600))
        print("OK: reinstall, update, registration replacement, unchanged launch and DMG isolation")
    }
}
