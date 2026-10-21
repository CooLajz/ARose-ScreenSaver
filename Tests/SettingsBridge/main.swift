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
    app.set(1.65, forKey: "pointScale"); app.set(56, forKey: "luminousIntensity")
    saver.set(0.85, forKey: "pointScale"); saver.set(23, forKey: "luminousIntensity")
    let options = RoseOptions(defaults: app) {}
    options.reload()
    options.contentViewController.view.layoutSubtreeIfNeeded()
    let stack = options.contentViewController.view.subviews.first as! NSStackView
    precondition(stack.fittingSize.height + 48 <= options.contentViewController.preferredContentSize.height,
                 "Settings controls exceed content height: \(stack.fittingSize.height)")
    options.perform(NSSelectorFromString("saveAction"))
    precondition(abs(app.double(forKey: "glow") - 0.25) < 0.000001, "App glow: \(app.double(forKey: "glow"))")
    precondition(saver.double(forKey: "glow") == 0.9)
    precondition(app.double(forKey: "pointScale") == 1.65 && app.integer(forKey: "luminousIntensity") == 56)
    precondition(saver.double(forKey: "pointScale") == 0.85 && saver.integer(forKey: "luminousIntensity") == 23)
    let view = ARoseView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), isPreview: true, settings: app)!
    precondition(view.pointScale == 1.65 && abs(view.luminousIntensity - 5.6) < 0.000001,
                 "The 0–100 scale must preserve the former 0–10 rendering")
}
print("OK: companion settings save independently from screen saver settings.")

let fresh = UserDefaults(suiteName: "cz.coolajz.ARose.tests.\(UUID().uuidString)")!
fresh.register(defaults: ARoseView.initialSettings)
precondition(fresh.integer(forKey: "appearance") == 1)
precondition(fresh.integer(forKey: "tail") == 16)
precondition(fresh.double(forKey: "glow") == 0.8)
precondition(fresh.double(forKey: "luminousIntensity") == 0)
precondition(fresh.double(forKey: "pointScale") == 1)
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

// Reused full-screen views are new sessions after stop, but duplicate active
// starts and temporary thumbnail stops must retain their current presentation.
for appearance in [0, 1] {
    for resume in [false, true] {
        let name = "cz.coolajz.ARose.reused-session.\(UUID().uuidString)"
        let prefs = UserDefaults(suiteName: name)!
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set(appearance, forKey: "appearance")
        prefs.set(resume, forKey: "resumeFigure")
        let view = ARoseView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), isPreview: false, settings: prefs)!
        let initial = view.engine.savedFigure()
        let seed = RoseEngine()
        for _ in 0..<180 { seed.step() }
        let bookmark = seed.savedFigure()
        prefs.set(bookmark, forKey: "figureState.v1")
        view.startAnimation()
        precondition(view.engine.savedFigure() == (resume ? bookmark : initial))
        for _ in 0..<3 {
            for _ in 0..<50 { view.engine.step() }
            let running = view.engine.savedFigure()
            view.startAnimation()
            precondition(view.engine.savedFigure() == running, "Duplicate start reset an active session")
            view.stopAnimation()
            let saved = prefs.array(forKey: "figureState.v1") as? [Int]
            view.startAnimation()
            precondition(view.engine.savedFigure() == (resume ? running : initial),
                         "A reused full-screen view ignored the resume preference")
            precondition(prefs.array(forKey: "figureState.v1") as? [Int] == saved,
                         "Starting a new session changed its saved bookmark")
        }
        view.stopAnimation()
        if !resume { precondition(prefs.array(forKey: "figureState.v1") as? [Int] == bookmark) }
    }
    let name = "cz.coolajz.ARose.reused-thumbnail.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    defer { prefs.removePersistentDomain(forName: name) }
    prefs.set(appearance, forKey: "appearance")
    let thumbnail = ARoseView(frame: NSRect(x: 0, y: 0, width: 200, height: 125), isPreview: true, settings: prefs)!
    for _ in 0..<20 { thumbnail.engine.step() }
    let warmup = thumbnail.engine.savedFigure()
    thumbnail.startAnimation()
    precondition(thumbnail.engine.savedFigure() == warmup, "First start discarded prepared geometry")
    thumbnail.stopAnimation(); thumbnail.startAnimation()
    precondition(thumbnail.engine.savedFigure() == warmup, "Temporary thumbnail stop reset its animation")
    thumbnail.stopAnimation()
}
print("OK: reused live views restart or restore as configured; active starts and thumbnail stop/start retain their figure.")

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
for hz in [30, 60, 120, 144] {
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
print("OK: 30/60/120/144 Hz preserve exact PAL state; pause, sleep, trail warm-up and hue-wrap interpolation.")

// Suspending the desktop must freeze the actual host callback without ending
// its figure session. Resuming continues instead of resetting the figure.
for appearance in [0, 1] {
    let name = "cz.coolajz.ARose.desktop-suspension.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    defer { prefs.removePersistentDomain(forName: name) }
    prefs.set(appearance, forKey: "appearance")
    let view = ARoseView(frame: .zero, isPreview: false, settings: prefs)!
    view.startAnimation()
    view.advanceFrames(500)
    let before = view.engine.savedFigure()
    view.renderingSuspended = true
    for _ in 0..<10 { view.animateOneFrame() }
    precondition(view.engine.savedFigure() == before, "Suspended desktop advanced")
    view.maximumPresentationFramesPerSecond = 30
    precondition(view.engine.savedFigure() == before, "Frame cap reset the figure")
    let frame = view.engine.frame
    view.renderingSuspended = false
    view.animateOneFrame()
    precondition(view.engine.frame == frame + 1, "Desktop resume reset or caught up")
    view.stopAnimation()
}
print("OK: retro and modern desktop suspension preserve the figure and resume without catch-up.")

// Only wallpaper opts into easing. The 2-second smoothstep ramp integrates
// to exactly one second of simulation at every supported display cadence.
for appearance in [0, 1] {
    for hz in [30, 60, 120, 144] {
        let name = "cz.coolajz.ARose.playback-easing.\(UUID().uuidString)"
        let prefs = UserDefaults(suiteName: name)!
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set(appearance, forKey: "appearance")
        let view = ARoseView(frame: .zero, isPreview: false, settings: prefs)!
        precondition(view.pauseTransitionDuration == 0, "Saver hosts must keep immediate pause")
        view.pauseTransitionDuration = 2
        view.startAnimation()
        view.advanceAnimation(at: 100, interpolate: true, playbackTime: 100)
        for tick in 1...hz {
            let time = 100 + Double(tick) / Double(hz)
            view.advanceAnimation(at: time, interpolate: true, playbackTime: time)
        }
        precondition(view.engine.frame == 51, "Initial launch must run at full speed")
        view.paused = true
        view.setPlaybackPaused(true, at: 101)
        for tick in 1...(2 * hz) {
            let time = 101 + Double(tick) / Double(hz)
            // Workspace polling must not restart the ramp every second.
            view.setPlaybackPaused(true, at: time)
            view.advanceAnimation(at: time, interpolate: true, playbackTime: time)
        }
        precondition(view.renderingSuspended && view.engine.frame == 101, "Braking changed with \(hz) Hz")
        let frozen = view.engine.savedFigure()
        view.advanceAnimation(at: 200, interpolate: true, playbackTime: 200)
        precondition(view.engine.savedFigure() == frozen)
        view.paused = false
        view.setPlaybackPaused(false, at: 200)
        view.advanceAnimation(at: 200, interpolate: true, playbackTime: 200)
        precondition(view.engine.savedFigure() == frozen, "Resume must not jump one simulation step")
        for tick in 1...(2 * hz) {
            let time = 200 + Double(tick) / Double(hz)
            view.advanceAnimation(at: time, interpolate: true, playbackTime: time)
        }
        precondition(!view.renderingSuspended && view.engine.frame == 151, "Run-up changed with \(hz) Hz")
        view.stopAnimation()
    }
}
var envelope = RosePlaybackEnvelope()
envelope.setPaused(true, duration: 2, at: 10)
let beforeReverse = envelope.rate(at: 10.7)
envelope.setPaused(false, duration: 2, at: 10.7)
precondition(abs(envelope.rate(at: 10.7) - beforeReverse) < 1e-12, "Reversing must preserve speed")
precondition(envelope.rate(at: 12.7) == 1)
// A continuous clock can finish braking while macOS suspends the process.
envelope.setPaused(true, duration: 2, at: 20)
envelope.setPaused(false, duration: 2, at: 200)
precondition(envelope.rate(at: 200) == 0 && envelope.rate(at: 201) == 0.5 && envelope.rate(at: 202) == 1)
print("OK: wallpaper brakes and accelerates over 2 seconds at 30/60/120/144 Hz; launch, reversal and wake remain continuous.")

// All visual controls preview in memory; only Save may change persistent preferences.
do {
    let name = "cz.coolajz.ARose.live-settings.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    defer { prefs.removePersistentDomain(forName: name) }
    let view = ARoseView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), isPreview: true, settings: prefs)!
    for _ in 0..<100 { view.engine.step() }
    let originalFigure = view.engine.savedFigure()
    let originalEngine = view.engine
    let options = RoseOptions(defaults: prefs) {}
    options.reload()
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    let controls = descendants(options.contentViewController.view)
    let sliders = controls.compactMap { $0 as? NSSlider }
    let popups = controls.compactMap { $0 as? NSPopUpButton }
    let debug = controls.compactMap { $0 as? NSButton }.first { $0.title.hasPrefix("Debug:") }!
    precondition(sliders.count == 3 && popups.count == 4)
    sliders[0].doubleValue = 35; options.perform(NSSelectorFromString("glowChanged"))
    sliders[1].doubleValue = 76; options.perform(NSSelectorFromString("luminousChanged"))
    sliders[2].doubleValue = 1.8; options.perform(NSSelectorFromString("pointSizeChanged"))
    precondition(view.glow == 0.35 && view.luminousIntensity == 7.6 && view.pointScale == 1.8)
    precondition(view.engine === originalEngine && view.engine.savedFigure() == originalFigure,
                 "Rendering sliders must not restart or advance the figure")
    debug.state = .on; options.perform(NSSelectorFromString("previewChanged"))
    precondition(view.debugCPU && !prefs.bool(forKey: "debugCPU"))
    popups[1].selectItem(at: 4); popups[2].selectItem(at: 1)
    options.perform(NSSelectorFromString("previewChanged"))
    precondition(view.engine.speed == 5 && view.engine.tail == 4 && view.engine.modernHistory.count == 4)
    precondition(prefs.integer(forKey: "speed") == 3 && prefs.integer(forKey: "tail") == 16)
    precondition(prefs.double(forKey: "glow") == 0.8 && prefs.double(forKey: "luminousIntensity") == 0 && prefs.double(forKey: "pointScale") == 1)
    options.perform(NSSelectorFromString("cancelAction"))
    precondition(view.glow == 0.8 && view.luminousIntensity == 0 && view.pointScale == 1)
    precondition(view.engine.speed == 3 && view.engine.tail == 16 && !view.debugCPU)
    options.reload()
    popups[0].selectItem(at: 0); options.perform(NSSelectorFromString("appearanceChanged"))
    popups[3].selectItem(at: 1); options.perform(NSSelectorFromString("previewChanged"))
    precondition(!view.engine.modern && view.engine.paletteMode == 1 && view.engine.frame >= originalFigure[1])
    options.perform(NSSelectorFromString("cancelAction"))
    precondition(view.engine.modern && view.engine.paletteMode == 2)
    options.reload()
    sliders[0].doubleValue = 45; options.perform(NSSelectorFromString("glowChanged"))
    sliders[1].doubleValue = 62; options.perform(NSSelectorFromString("luminousChanged"))
    sliders[2].doubleValue = 1.25; options.perform(NSSelectorFromString("pointSizeChanged"))
    options.perform(NSSelectorFromString("saveAction"))
    precondition(prefs.double(forKey: "glow") == 0.45 && prefs.integer(forKey: "luminousIntensity") == 62 && prefs.double(forKey: "pointScale") == 1.25)
    precondition(view.glow == 0.45 && view.luminousIntensity == 6.2 && view.pointScale == 1.25)
}
print("OK: all appearance controls preview immediately; Cancel restores settings; Save persists; sliders preserve the figure.")
