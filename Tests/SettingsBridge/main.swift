import Foundation
import AppKit

let fresh = UserDefaults(suiteName: "cz.coolajz.ARose.tests.\(UUID().uuidString)")!
fresh.register(defaults: ARoseView.initialSettings)
precondition(fresh.integer(forKey: "appearance") == 1)
precondition(fresh.integer(forKey: "tail") == 16)
precondition(fresh.double(forKey: "glow") == 0.8)
// Existing user choices take precedence over registration defaults.
fresh.setVolatileDomain(["appearance": 0, "tail": 4, "glow": 0.2], forName: UserDefaults.argumentDomain)
fresh.register(defaults: ARoseView.initialSettings)
precondition(fresh.integer(forKey: "appearance") == 0)
precondition(fresh.integer(forKey: "tail") == 4)
precondition(fresh.double(forKey: "glow") == 0.2)

let id = UUID().uuidString
let valid: [String: Double] = ["appearance": 1, "speed": 2, "tail": 16, "palette": 2, "glow": 0.81, "debugCPU": 0, "resumeFigure": 0]
func decode(_ values: [String: Double]?) -> RoseSettingsBridge.Message? {
    RoseSettingsBridge.decode(RoseSettingsBridge.encode(.init(id: id, values: values)))
}
precondition(decode(valid)?.values == valid)
precondition(decode(nil)?.id == id)
for (key, bad) in [("appearance", 2.0), ("speed", 2.5), ("tail", 3.0), ("palette", -1.0), ("glow", 1.01), ("debugCPU", 0.5), ("resumeFigure", 0.5)] {
    var values = valid
    values[key] = bad
    precondition(decode(values) == nil)
}
var missing = valid
missing.removeValue(forKey: "glow")
precondition(decode(missing) == nil)
var extra = valid
extra["unrelated"] = 1
precondition(decode(extra) == nil)
precondition(RoseSettingsBridge.decode("invalid JSON") == nil)
precondition(RoseSettingsBridge.decode(String(repeating: "x", count: 4097)) == nil)
precondition(RoseSettingsBridge.decode("{\"id\":\"invalid\"}") == nil)
print("OK: přenos nastavení přijímá pouze úplné platné volby ARose a platné identifikátory.")

precondition(!fresh.bool(forKey: "debugCPU"))
var debugEnabled = valid
 debugEnabled["debugCPU"] = 1
precondition(decode(debugEnabled)?.values == debugEnabled)
precondition(RoseCPUMeter.percentage(cpuDelta: 0.5, wallDelta: 2, logicalProcessors: 4) == 6.25)
precondition(RoseCPUMeter.percentage(cpuDelta: 3, wallDelta: 1, logicalProcessors: 4) == 75)
precondition(RoseCPUMeter.percentage(cpuDelta: -1, wallDelta: 1) == nil)
precondition(RoseCPUMeter.percentage(cpuDelta: 1, wallDelta: 0) == nil)

precondition(RoseCPUMeter.percentage(cpuDelta: 8, wallDelta: 1, logicalProcessors: 4) == 100)
precondition(RoseCPUMeter.percentage(cpuDelta: 1, wallDelta: 1, logicalProcessors: 0) == nil)

// The same sample must show 300% of one core and 75% of four cores.
precondition(RoseCPUMeter.singleCorePercentage(cpuDelta: 3, wallDelta: 1) == 300)
precondition(RoseCPUMeter.singleCorePercentage(cpuDelta: 0, wallDelta: 1) == 0)
precondition(RoseCPUMeter.singleCorePercentage(cpuDelta: -1, wallDelta: 1) == nil)
precondition(RoseCPUMeter.singleCorePercentage(cpuDelta: 1, wallDelta: 0) == nil)
precondition(RoseCPUMeter.singleCorePercentage(cpuDelta: .infinity, wallDelta: 1) == nil)

precondition(!fresh.bool(forKey: "resumeFigure"))

// Exercise the actual saver lifecycle with an isolated preference domain.
do {
    let name = "cz.coolajz.ARose.resume-tests.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    defer { prefs.removePersistentDomain(forName: name) }
    prefs.register(defaults: ARoseView.initialSettings)
    prefs.set(true, forKey: "resumeFigure")
    let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    let first = ARoseView(frame: frame, isPreview: false, settings: prefs)!
    first.startAnimation()
    for _ in 0..<600 { first.engine.step() }
    let expected = first.engine.savedFigure()
    let secondary = ARoseView(frame: frame, isPreview: false, settings: prefs)!
    secondary.startAnimation(); secondary.engine.step(); secondary.stopAnimation()
    precondition(prefs.array(forKey: "figureState.v1") == nil)
    first.stopAnimation()
    precondition(prefs.array(forKey: "figureState.v1") as? [Int] == expected)
    let thumbnail = ARoseView(frame: frame, isPreview: true, settings: prefs)!
    thumbnail.startAnimation(); thumbnail.engine.step(); thumbnail.stopAnimation()
    precondition(prefs.array(forKey: "figureState.v1") as? [Int] == expected)
    let second = ARoseView(frame: frame, isPreview: false, settings: prefs)!
    second.startAnimation()
    precondition(second.engine.savedFigure() == expected)
    second.stopAnimation()
    let standalone = ARoseView(frame: frame, isPreview: false, settings: prefs)!
    standalone.figureStorageKey = "previewFigureState.v1"
    standalone.startAnimation(); standalone.engine.step(); standalone.stopAnimation()
    precondition(prefs.array(forKey: "figureState.v1") as? [Int] == expected)
    precondition(prefs.array(forKey: "previewFigureState.v1") != nil)
    prefs.set(false, forKey: "resumeFigure")
    second.startAnimation()
    precondition(second.engine.frame == 0)
    second.engine.step(); second.stopAnimation()
    precondition(prefs.array(forKey: "figureState.v1") as? [Int] == expected)
}
print("OK: saver lifecycle restores bookmarks; thumbnails, other monitors and standalone preview do not overwrite them.")

// Regression: the legacy host can discard a short-running saver without stopAnimation.
do {
    let name = "cz.coolajz.ARose.abrupt-tests.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    defer { prefs.removePersistentDomain(forName: name) }
    prefs.set(true, forKey: "resumeFigure")
    var view: ARoseView? = ARoseView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), isPreview: false, settings: prefs)!
    view!.startAnimation(); view!.engine.step(); view!.checkpointFigureIfNeeded()
    precondition((prefs.array(forKey: "figureState.v1") as? [Int])?[1] == 1)
    for _ in 0..<50 { view!.engine.step() }
    view!.checkpointFigureIfNeeded()
    let expected = view!.engine.savedFigure()
    view = nil // Deliberately omit stopAnimation.
    let newPreferences = UserDefaults(suiteName: name)!
    let next = ARoseView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), isPreview: false, settings: newPreferences)!
    next.startAnimation()
    precondition(next.engine.savedFigure() == expected)
    next.stopAnimation()
}
print("OK: first-frame and one-second checkpoints survive missing stopAnimation.")

// Regression: the host retains the old view, but stops delivering frames without
// calling stopAnimation. The next active view must acquire the expired lease.
do {
    let name = "cz.coolajz.ARose.writer-tests.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    defer { prefs.removePersistentDomain(forName: name) }
    prefs.set(true, forKey: "resumeFigure")
    let rect = NSRect(x: 0, y: 0, width: 800, height: 600)
    let stale = ARoseView(frame: rect, isPreview: false, settings: prefs)!
    stale.startAnimation(); stale.engine.step(); stale.checkpointFigureIfNeeded()
    let active = ARoseView(frame: rect, isPreview: false, settings: prefs)!
    active.startAnimation()
    for _ in 0..<100 { active.engine.step() }
    active.checkpointFigureIfNeeded(at: ProcessInfo.processInfo.systemUptime + 2)
    let expected = active.engine.savedFigure()
    precondition(prefs.array(forKey: "figureState.v1") as? [Int] == expected)
    stale.stopAnimation() // A late stop must not overwrite the newer bookmark.
    precondition(prefs.array(forKey: "figureState.v1") as? [Int] == expected)
    active.stopAnimation()
    let next = ARoseView(frame: rect, isPreview: false, settings: prefs)!
    next.startAnimation()
    precondition(next.engine.savedFigure() == expected)
    next.stopAnimation()
}
print("OK: retained inactive writers relinquish their lease; late stops cannot roll back the bookmark.")
