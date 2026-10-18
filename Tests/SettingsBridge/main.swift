import Foundation
import AppKit

// Saving companion options must leave the saver configuration untouched.
do {
    _ = NSApplication.shared
    let appName = "cz.coolajz.ARose.tests.app.\(UUID().uuidString)"
    let saverName = "cz.coolajz.ARose.tests.saver.\(UUID().uuidString)"
    let app = UserDefaults(suiteName: appName)!
    let saver = UserDefaults(suiteName: saverName)!
    defer {
        app.removePersistentDomain(forName: appName)
        saver.removePersistentDomain(forName: saverName)
    }
    app.register(defaults: ARoseView.initialSettings)
    saver.register(defaults: ARoseView.initialSettings)
    app.set(0.25, forKey: "glow")
    saver.set(0.9, forKey: "glow")
    let options = RoseOptions(defaults: app) {}
    options.reload()
    options.perform(NSSelectorFromString("saveAction"))
    precondition(abs(app.double(forKey: "glow") - 0.25) < 0.000001, "App glow: \(app.double(forKey: "glow"))")
    precondition(saver.double(forKey: "glow") == 0.9)
}
print("OK: companion settings save independently from screen saver settings.")

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
fresh.removeVolatileDomain(forName: UserDefaults.argumentDomain)

precondition(!fresh.bool(forKey: "debugCPU"))
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

// A reset generation clears both bookmarks and prevents a retained view from
// resurrecting its old state during a late stop/checkpoint.
do {
    let name = "cz.coolajz.ARose.reset-tests.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    defer { prefs.removePersistentDomain(forName: name) }
    prefs.set(true, forKey: "resumeFigure")
    let rect = NSRect(x: 0, y: 0, width: 800, height: 600)
    let old = ARoseView(frame: rect, isPreview: false, settings: prefs)!
    old.startAnimation()
    for _ in 0..<100 { old.engine.step() }
    old.saveFigure()
    prefs.set(old.engine.savedFigure(), forKey: "previewFigureState.v1")
    prefs.set(1, forKey: "figureReset")
    prefs.removeObject(forKey: "figureState.v1")
    prefs.removeObject(forKey: "previewFigureState.v1")
    old.saveFigure()
    precondition(old.engine.frame == 0)
    precondition(prefs.array(forKey: "figureState.v1") == nil)
    precondition(prefs.array(forKey: "previewFigureState.v1") == nil)
    old.stopAnimation()
    let next = ARoseView(frame: rect, isPreview: false, settings: prefs)!
    next.startAnimation(); precondition(next.engine.frame == 0)
    next.engine.step(); next.saveFigure(); next.stopAnimation()
    precondition((prefs.array(forKey: "figureState.v1") as? [Int])?[1] == 1)
}
print("OK: reset clears bookmarks and stale writers cannot restore old progress.")

// The reset button is Save-gated: Cancel must preserve both bookmarks.
do {
    _ = NSApplication.shared
    let name = "cz.coolajz.ARose.reset-ui-tests.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    defer { prefs.removePersistentDomain(forName: name) }
    prefs.register(defaults: ARoseView.initialSettings)
    prefs.set(true, forKey: "resumeFigure")
    let old = RoseEngine(); for _ in 0..<80 { old.step() }
    prefs.set(old.savedFigure(), forKey: "figureState.v1")
    prefs.set(old.savedFigure(), forKey: "previewFigureState.v1")
    var applied=false
    let options = RoseOptions(defaults: prefs) { applied=true }
    options.reload()
    options.perform(NSSelectorFromString("forgetAction"))
    precondition(prefs.array(forKey: "figureState.v1") != nil)
    options.perform(NSSelectorFromString("cancelAction"))
    precondition(!applied && prefs.double(forKey: "figureReset") == 0)
    options.reload()
    options.perform(NSSelectorFromString("forgetAction"))
    options.perform(NSSelectorFromString("saveAction"))
    precondition(applied && prefs.double(forKey: "figureReset") > 0)
    precondition(prefs.array(forKey: "figureState.v1") == nil)
    precondition(prefs.array(forKey: "previewFigureState.v1") == nil)
    precondition(prefs.bool(forKey: "resumeFigure"))
}
print("OK: reset requires Save, Cancel preserves progress, resume preference stays enabled.")

// Display cadence must not alter the PAL simulation or its saved state.
for hz in [60, 120, 144] {
    let prefs = UserDefaults(suiteName: "cz.coolajz.ARose.timing.\(UUID().uuidString)")!
    prefs.setVolatileDomain(["appearance": 1, "resumeFigure": false], forName: UserDefaults.argumentDomain)
    let view = ARoseView(frame: .zero, isPreview: true, settings: prefs)!
    let reference = RoseEngine(); reference.modern = true; reference.speed = 3; reference.tail = 16; reference.paletteMode = 2
    view.advanceAnimation(at: 100, interpolate: true)
    for i in 1...(hz * 10) { view.advanceAnimation(at: 100 + Double(i) / Double(hz), interpolate: true) }
    for _ in 0..<501 { reference.step() }
    precondition(view.engine.savedFigure() == reference.savedFigure(), "Display cadence changed simulation at \(hz) Hz")
    let beforePause = view.engine.frame
    view.paused = true
    view.advanceAnimation(at: 111, interpolate: true)
    precondition(view.engine.frame == beforePause)
    view.paused = false
    view.advanceAnimation(at: 111.02, interpolate: true)
    precondition(view.engine.frame == beforePause + 1)
    view.advanceAnimation(at: 200, interpolate: true)
    precondition(view.engine.frame == beforePause + 6, "Sleep must not cause unbounded catch-up")
}
let a = RoseEngine.ModernPoint(x: 0, y: 10, hue: 0.99)
let b = RoseEngine.ModernPoint(x: 10, y: 0, hue: 0.01)
let midpoint = RoseInterpolation.history(previous: [[a]], current: [[b]], alpha: 0.5)[0][0]
precondition(midpoint.x == 5 && midpoint.y == 5 && abs(midpoint.hue) < 1e-12)
precondition(RoseInterpolation.history(previous: [], current: [[b]], alpha: 0.5)[0][0].x == b.x)
print("OK: 60/120/144 Hz preserve exact PAL state; pause, sleep, trail warm-up and hue-wrap interpolation.")
