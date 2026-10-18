import AppKit
import ScreenSaver
import Darwin
func cpuTime() -> Double {
    var r = rusage(); getrusage(RUSAGE_SELF, &r)
    return Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec) + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec) / 1e6
}

setbuf(stdout, nil)
let app = NSApplication.shared
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".build/metal-images"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
guard let gpu = RoseMetalRenderer(sprites: ARoseView.glowSprites) else { fatalError("Metal device or pipeline unavailable") }
for (size, backing, frame, tail) in [
    (CGSize(width: 960, height: 720), CGFloat(2), 1551, 16),
    (CGSize(width: 640, height: 480), CGFloat(1), 501, 1),
    (CGSize(width: 400, height: 800), CGFloat(2), 3501, 20),
    (CGSize(width: 1920, height: 1080), CGFloat(2), 1552, 16),
    (CGSize(width: 200, height: 125), CGFloat(2), 77, 4)
] {
let width = Int(size.width * backing), height = Int(size.height * backing)
let prefix = "\(width)x\(height)-f\(frame)-t\(tail)"
print(prefix)
for glow in [0.0, 0.8, 1.0] {
    let settings = UserDefaults(suiteName: "cz.coolajz.ARose.metal-test.\(UUID().uuidString)")!
    settings.setVolatileDomain(["appearance": 1, "palette": 2, "speed": 3, "tail": tail,
                               "glow": glow, "debugCPU": false], forName: UserDefaults.argumentDomain)
    let view = ARoseView(frame: CGRect(origin: .zero, size: size), isPreview: true, settings: settings)!
    for _ in 0..<frame { view.engine.step() }
    let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.scaleBy(x: backing, y: backing)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    c.setFillColor(CGColor(gray: 0, alpha: 1)); c.fill(CGRect(origin: .zero, size: size)); view.drawModern(in: c, backing: backing); NSGraphicsContext.restoreGraphicsState()
    let reference = c.makeImage()!
    guard let candidate = gpu.snapshot(size: size, backing: backing, history: view.engine.modernHistory,
                                       glow: glow, foreground: { view.drawMetalForeground(in: $0, backing: backing) }) else { fatalError("GPU command failed") }
    for (name, image) in [("cpu", reference), ("gpu", candidate)] {
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "\(output)/\(prefix)-\(name)-\(Int(glow*100)).png"))
    }
    func pixels(_ image: CGImage) -> [UInt8] {
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Array(UnsafeBufferPointer(start: c.data!.assumingMemoryBound(to: UInt8.self), count: width*height*4))
    }
    let a = pixels(reference), b = pixels(candidate)
    var changed = 0, maximum = 0, absolute = 0, energyA = 0, energyB = 0
    for i in a.indices where i % 4 != 3 {
        let delta = abs(Int(a[i])-Int(b[i])); absolute += delta; maximum = max(maximum, delta)
        if delta > 0 { changed += 1 }
        energyA += Int(a[i]); energyB += Int(b[i])
    }
    print("glow=\(glow) changed=\(changed) max=\(maximum) mean=\(Double(absolute)/Double(width*height*3)) energyRatio=\(Double(energyB)/Double(energyA))")
    // No byte-identical claim for blended glow. Catch geometry/color regressions
    // while allowing small resampling and intermediate rounding differences.
    let energyRatio = Double(energyB) / Double(energyA)
    if glow == 0 { precondition(changed == 0) }
    else if frame == 1551 { precondition(maximum <= 20 && abs(energyRatio - 1) < 0.04) }
    let full = gpu.snapshot(size: size, backing: backing, history: view.engine.modernHistory, glow: glow)!
    try NSBitmapImageRep(cgImage: full).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/\(prefix)-full-\(Int(glow*100)).png"))
    let f = pixels(full)
    var fullMax = 0, fullSum = 0, fullEnergy = 0
    for i in a.indices where i % 4 != 3 {
        let delta = abs(Int(a[i]) - Int(f[i])); fullMax = max(fullMax, delta); fullSum += delta; fullEnergy += Int(f[i])
    }
    print("FULL max=\(fullMax) mean=\(Double(fullSum)/Double(width*height*3)) energy=\(Double(fullEnergy)/Double(energyA))")
    var pointDelta = 0
    for i in b.indices where i % 4 != 3 { pointDelta = max(pointDelta, abs(Int(b[i]) - Int(f[i]))) }
    let pointEnergy = Double(fullEnergy) / Double(energyB)
    print("Point-only delta vs existing hybrid: max=\(pointDelta), energy=\(pointEnergy)")
    precondition(pointDelta <= 4 && abs(pointEnergy - 1) < 0.02,
                 "GPU points deviated from the existing hybrid reference")
    // The cropped debug texture must place exactly the same label in the same
    // corner as the former full-screen transparent foreground.
    let labelReference = gpu.snapshot(size: size, backing: backing, history: [], glow: 0,
                                      foreground: { view.drawMetalOverlay(in: $0) })!
    let labelCropped = gpu.snapshot(size: size, backing: backing, history: [], glow: 0,
                                    overlay: { view.drawMetalOverlay(in: $0) })!
    precondition(pixels(labelReference) == pixels(labelCropped), "Cropped CPU label changed placement or pixels")
    let empty = gpu.snapshot(size: size, backing: backing, history: [], glow: glow)!
    let emptyPixels = pixels(empty)
    precondition(emptyPixels.indices.filter { $0 % 4 != 3 }.allSatisfy { emptyPixels[$0] == 0 }, "Empty history must clear to black")
    let previous = view.engine.modernHistory
    view.engine.step()
    for alpha in [0.0, 0.37, 1.0] {
        let referenceHistory = RoseInterpolation.history(previous: previous, current: view.engine.modernHistory, alpha: alpha)
        let referenceImage = gpu.snapshot(size: size, backing: backing, history: referenceHistory, glow: glow)!
        let referenceCPU = gpu.lastSnapshotPreparationCPU
        let computedImage = gpu.snapshot(size: size, backing: backing, history: view.engine.modernHistory, glow: glow,
                                         previous: previous, alpha: alpha)!
        let computedCPU = gpu.lastSnapshotPreparationCPU
        let referenceBytes = pixels(referenceImage), computedBytes = pixels(computedImage)
        var maxError = 0, squareError = 0.0, referenceEnergy = 0.0, computedEnergy = 0.0
        for i in referenceBytes.indices where i % 4 != 3 {
            let delta = abs(Int(referenceBytes[i]) - Int(computedBytes[i]))
            maxError = max(maxError, delta); squareError += Double(delta * delta)
            referenceEnergy += Double(referenceBytes[i]); computedEnergy += Double(computedBytes[i])
        }
        let rms = sqrt(squareError / Double(width * height * 3))
        let energy = abs(computedEnergy / referenceEnergy - 1)
        print("INTERPOLATION alpha=\(alpha) max=\(maxError) rms=\(rms) energy=\(energy) CPU ms \(referenceCPU*1000) -> \(computedCPU*1000)")
        precondition(maxError <= 2 && rms < 0.02 && energy < 0.001, "GPU interpolation changed image")
    }
    if frame != 1551 { continue }
    var cpu = 0.0, preparation = 0.0, execution = 0.0
    for n in 0..<15 {
        view.engine.step()
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
        let start = cpuTime(); c.setFillColor(CGColor(gray: 0, alpha: 1)); c.fill(CGRect(origin: .zero, size: size)); view.drawModern(in: c, backing: backing); let duration = cpuTime() - start
        NSGraphicsContext.restoreGraphicsState()
        precondition(gpu.snapshot(size: size, backing: backing, history: view.engine.modernHistory,
                                  glow: glow) != nil)
        if n >= 5 { cpu += duration; preparation += gpu.lastSnapshotPreparationCPU; execution += gpu.lastSnapshotGPUTime }
    }
    print(String(format: "render CPU %.3f ms -> Metal preparation CPU %.3f ms; GPU %.3f ms", cpu*100, preparation*100, execution*100))

}

}

// Same changing 120 Hz workload on both paths; exclude synchronous readback from
// preparation timings. This measures CPU preparation, not whole-process usage.
let benchmarkEngine = RoseEngine()
benchmarkEngine.modern = true; benchmarkEngine.speed = 3; benchmarkEngine.tail = 16
for _ in 0..<1551 { benchmarkEngine.step() }
var previous = benchmarkEngine.modernHistory
var referenceTotal = 0.0, computeTotal = 0.0
for tick in 0..<120 {
    if tick % 12 < 5 { previous = benchmarkEngine.modernHistory; benchmarkEngine.step() }
    let alpha = Double((tick * 5) % 12) / 12
    let begin = cpuTime()
    let history = RoseInterpolation.history(previous: previous, current: benchmarkEngine.modernHistory, alpha: alpha)
    let interpolationCPU = cpuTime() - begin
    precondition(gpu.snapshot(size: CGSize(width: 640, height: 480), backing: 1,
                              history: history, glow: 0.8) != nil)
    let referenceCPU = interpolationCPU + gpu.lastSnapshotPreparationCPU
    precondition(gpu.snapshot(size: CGSize(width: 640, height: 480), backing: 1,
                              history: benchmarkEngine.modernHistory, glow: 0.8, previous: previous, alpha: alpha) != nil)
    if tick >= 24 { referenceTotal += referenceCPU; computeTotal += gpu.lastSnapshotPreparationCPU }
}
print("INTERPOLATION BENCHMARK CPU preparation ms/frame: \(referenceTotal / 96 * 1000) -> \(computeTotal / 96 * 1000)")

var overlayPaints = 0
func cachedLabel(_ context: CGContext) {
    overlayPaints += 1
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 600, y: 10, width: 20, height: 20))
}
let labelSize = CGSize(width: 640, height: 480)
let cachedFirst = gpu.snapshot(size: labelSize, backing: 1, history: [], glow: 0, overlay: cachedLabel, overlayKey: "first")!
for _ in 0..<10 {
    let reused = gpu.snapshot(size: labelSize, backing: 1, history: [], glow: 0, overlay: cachedLabel, overlayKey: "first")!
    precondition((reused.dataProvider!.data! as Data) == (cachedFirst.dataProvider!.data! as Data))
}
precondition(overlayPaints == 1, "Unchanged overlay must reuse texture")
_ = gpu.snapshot(size: labelSize, backing: 1, history: [], glow: 0, overlay: cachedLabel, overlayKey: "second")
precondition(overlayPaints == 2, "Changed value must repaint")
_ = gpu.snapshot(size: CGSize(width: 700, height: 480), backing: 1, history: [], glow: 0, overlay: cachedLabel, overlayKey: "second")
precondition(overlayPaints == 3, "Resize must repaint even when cropped texture dimensions stay unchanged")
_ = gpu.snapshot(size: labelSize, backing: 2, history: [], glow: 0, overlay: cachedLabel, overlayKey: "second")
precondition(overlayPaints == 4, "Backing-scale change must repaint")
print("OK: overlay reuse preserves pixels; value, bounds and backing changes invalidate the cache.")
