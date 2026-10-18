import AppKit
import QuartzCore

final class WindowTest: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: ARoseView!
    var timer: Timer?
    var ticks = 0
    var beforeResizeCount = 0
    var steadyResult = ""
    var displayRate = ""
    var startupAllocations = 0
    var pausedSubmissions = 0
    var pausedFrame = 0
    let settings = UserDefaults(suiteName: "cz.coolajz.ARose.window-test.\(UUID().uuidString)")!
    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.setVolatileDomain(["appearance": 1, "speed": 3, "palette": 2, "tail": 16,
                                    "glow": 0.8, "debugCPU": false], forName: UserDefaults.argumentDomain)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARose — Metal rendering test"
        let startup = ARoseView(frame: window.contentView!.bounds, isPreview: false, settings: settings)!
        startup.showsIdlePreview = true
        window.contentView = startup
        window.makeKeyAndOrderFront(nil)
        startup.startAnimation()
        precondition(startup.engine.frame == 0 && (startup.metalFrameStatistics?.submitted ?? 0) == 0,
                     "Startup published a blank Metal frame before the first simulation tick")
        startup.advanceAnimation(at: 100, interpolate: true)
        precondition(startup.engine.frame == 1 && !startup.engine.modernHistory.isEmpty)
        startup.startAnimation()
        startup.advanceAnimation(at: 100.005, interpolate: true)
        precondition(startup.engine.frame == 1,
                     "Repeated start reset the clock and advanced the simulation early")
        startup.stopAnimation()
        startup.startAnimation()
        precondition(startup.engine.frame == 0 && startup.engine.modernHistory.isEmpty,
                     "Reused full-screen view continued despite resume being disabled")
        startup.advanceAnimation(at: 200, interpolate: true)
        precondition(startup.engine.frame == 1 && !startup.engine.modernHistory.isEmpty,
                     "Restarted full-screen view did not submit new geometry")
        startup.stopAnimation()
        print("OK: startup waits for real geometry; repeated start preserves the presentation clock.")
        view = ARoseView(frame: window.contentView!.bounds, isPreview: false, settings: settings)!
        view.autoresizingMask = [.width, .height]; window.contentView = view
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        view.animateOneFrame()
        precondition(view.engine.frame == 1)
        view.animateOneFrame()
        precondition(view.engine.frame == 1, "Initial GPU setup was counted as elapsed simulation time")
        view.startAnimation()
        let simulationStart = view.engine.frame
        let clockStart = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [self] _ in
            ticks += 1; view.animateOneFrame()
            if ticks == 30 { startupAllocations = view.metalBufferAllocationCount! }
            if ticks == 190 {
                let elapsed = ProcessInfo.processInfo.systemUptime - clockStart
                let steps = view.engine.frame - simulationStart
                precondition(abs(Double(steps) - elapsed * 50) < 12, "Display link changed simulation speed")
                displayRate = "Display-driven rate: \(Double(view.metalFrameStatistics!.submitted) / elapsed) submissions/s; screen maximum \(window.screen?.maximumFramesPerSecond ?? 0) Hz."
                print(displayRate)
                view.paused = true
            }
            if ticks == 200 {
                precondition(view.layer?.sublayers?.contains(where: { $0 is CAMetalLayer && !$0.isHidden }) == true,
                             "Metal presentation layer missing")
                let stats = view.metalFrameStatistics!
                precondition(stats.submitted > 100, "Insufficient frames submitted")
                precondition(stats.busy == 0 && stats.noDrawable == 0, "Frames dropped during steady animation")
                steadyResult = "Metal steady animation: \(stats)"
                precondition(startupAllocations <= 6 && view.metalBufferAllocationCount == startupAllocations,
                             "Trail growth caused repeated GPU instance-buffer allocations")
                beforeResizeCount = stats.submitted
                window.setContentSize(NSSize(width: 1100, height: 680))
            }
            if ticks == 240 {
                precondition(view.metalFrameStatistics!.submitted > beforeResizeCount,
                             "Paused resize did not refresh Metal")
                pausedSubmissions = view.metalFrameStatistics!.submitted
                pausedFrame = view.engine.frame
                view.advanceFrames(500)
            }
            if ticks == 250 {
                precondition(view.paused && view.engine.frame == pausedFrame + 500,
                             "Manual advance changed pause or failed to advance the figure")
                precondition(view.metalFrameStatistics!.submitted > pausedSubmissions,
                             "Paused advance did not refresh Metal")
                pausedSubmissions = view.metalFrameStatistics!.submitted
                view.restartAnimation()
            }
            if ticks == 260 {
                precondition(view.paused && view.engine.frame == 0,
                             "Manual restart changed pause or failed to reset the figure")
                precondition(view.metalFrameStatistics!.submitted > pausedSubmissions,
                             "Paused restart did not clear the old Metal image")
                view.paused = false
            }
            if ticks == 600 { view.glow = 0; view.needsDisplay = true }
            if ticks == 700 {
                precondition(view.layer?.sublayers?.contains { $0 is CAMetalLayer && !$0.isHidden } == true)
                view.glow = 0.8; view.needsDisplay = true
            }
            if ticks == 900 { view.reset() }
            if ticks == 1100 {
                precondition(view.layer?.sublayers?.contains(where: { $0 is CAMetalLayer && !$0.isHidden }) == true)
                try! "OK: Metal window, paused resize/advance/restart, glow toggle and reset. \(steadyResult) \(displayRate)\n".write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
                view.stopAnimation()
                timer?.invalidate(); NSApp.terminate(nil)
            }
        }
    }
}
let app = NSApplication.shared
let delegate = WindowTest(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
