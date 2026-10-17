import AppKit
import QuartzCore

final class WindowTest: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: ARoseView!
    var timer: Timer?
    var ticks = 0
    var beforeResizeCount = 0
    var steadyResult = ""
    var startupAllocations = 0
    let settings = UserDefaults(suiteName: "cz.coolajz.ARose.window-test.\(UUID().uuidString)")!
    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.setVolatileDomain(["appearance": 1, "speed": 3, "palette": 2, "tail": 16,
                                    "glow": 0.8, "debugCPU": false], forName: UserDefaults.argumentDomain)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARose — Metal rendering test"
        view = ARoseView(frame: window.contentView!.bounds, isPreview: false, settings: settings)!
        view.autoresizingMask = [.width, .height]; window.contentView = view
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        view.animateOneFrame()
        precondition(view.engine.frame == 1)
        view.animateOneFrame()
        precondition(view.engine.frame == 1, "Initial GPU setup was counted as elapsed simulation time")
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [self] _ in
            ticks += 1; view.animateOneFrame()
            if ticks == 30 { startupAllocations = view.metalBufferAllocationCount! }
            if ticks == 190 { view.paused = true }
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
                try! "OK: Metal window, paused resize, glow toggle and reset. \(steadyResult)\n".write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
                timer?.invalidate(); NSApp.terminate(nil)
            }
        }
    }
}
let app = NSApplication.shared
let delegate = WindowTest(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
