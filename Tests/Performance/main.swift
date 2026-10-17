import AppKit
import ScreenSaver
import Darwin

// Offscreen benchmark: no change to saved user preferences.
let app = NSApplication.shared
let defaults = UserDefaults(suiteName: "cz.coolajz.ARose.benchmark.\(UUID().uuidString)")!
defaults.setVolatileDomain(["appearance": 1, "speed": 3, "palette": 2, "tail": 16, "debugCPU": false], forName: UserDefaults.argumentDomain)
let output = CommandLine.arguments[1]
let retro = CommandLine.arguments.contains("--retro")
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
func cpuTime() -> Double {
    var r = rusage(); getrusage(RUSAGE_SELF, &r)
    return Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec) + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec) / 1e6
}
for glow in [0.0, 0.8] {
    let view = ARoseView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), isPreview: true, settings: defaults)!
    view.glow = glow
    // Set simulation parameters explicitly: ScreenSaverDefaults instances may
    // resolve host preferences differently from the test's volatile domain.
    view.engine.modern = !retro
    view.engine.speed = 3
    view.engine.tail = 16
    view.engine.paletteMode = 2
    for _ in 0..<1500 { view.engine.step() }
    let bitmap = CGContext(data: nil, width: 3840, height: 2160, bitsPerComponent: 8,
                           bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let context = NSGraphicsContext(cgContext: bitmap, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    bitmap.scaleBy(x: 2, y: 2)
    var render = 0.0, simulation = 0.0
    for n in 0..<100 {
        let a = cpuTime(); view.engine.step(); let b = cpuTime()
        view.draw(view.bounds); let c = cpuTime()
        if n >= 10 { simulation += b-a; render += c-b }
        if [10, 50, 99].contains(n) {
            let data = NSBitmapImageRep(cgImage: bitmap.makeImage()!).representation(using: .png, properties: [:])!
            try data.write(to: URL(fileURLWithPath: "\(output)/glow-\(Int(glow*100))-\(n).png"))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    print(String(format: "glow=%.0f render_cpu_ms=%.3f simulation_cpu_ms=%.3f", glow*100, render/90*1000, simulation/90*1000))
}
