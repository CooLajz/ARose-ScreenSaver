import AppKit
import ScreenSaver

let app = NSApplication.shared
func reference(_ view: ARoseView, palette: Int) -> CGImage {
    let colors = RoseEngine.palette(mode: palette)
    let space = colors.withUnsafeBufferPointer {
        CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: 255, colorTable: $0.baseAddress!)!
    }
    return CGImage(width: 800, height: 600, bitsPerComponent: 8, bitsPerPixel: 8,
                   bytesPerRow: 800, space: space, bitmapInfo: [],
                   provider: CGDataProvider(data: Data(view.engine.pixels) as CFData)!,
                   decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}
func render(_ image: CGImage, width: Int, height: Int) -> Data {
    let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(CGColor(gray: 0, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let scale = min(Double(width) / 800, Double(height) / 600)
    c.interpolationQuality = .none; c.setShouldAntialias(false)
    c.draw(image, in: CGRect(x: (Double(width)-800*scale)/2, y: (Double(height)-600*scale)/2,
                             width: 800*scale, height: 600*scale))
    return Data(bytes: c.data!, count: height * c.bytesPerRow)
}
var comparisons = 0
for palette in 0...2 {
    let settings = UserDefaults(suiteName: "cz.coolajz.ARose.render-test.\(UUID().uuidString)")!
    settings.setVolatileDomain(["appearance": 0, "palette": palette, "speed": 3,
                               "tail": 16, "glow": 0, "debugCPU": false], forName: UserDefaults.argumentDomain)
    let view = ARoseView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), isPreview: true, settings: settings)!
    precondition(!view.engine.modern && view.engine.paletteMode == palette)
    for frame in 0...1600 {
        if [0, 1, 20, 311, 1511, 1551, 1600].contains(frame) {
            let old = reference(view, palette: palette)
            let new = view.frameImage()!
            for (w, h) in [(800, 600), (1173, 717), (3840, 2160)] {
                precondition(render(old, width: w, height: h) == render(new, width: w, height: h),
                             "Retro mismatch: palette \(palette), frame \(frame), \(w)x\(h)")
                comparisons += 1
            }
        }
        view.engine.step()
    }
    let retained = view.frameImage()!
    let snapshot = render(retained, width: 800, height: 600)
    for _ in 0..<100 { view.engine.step(); _ = view.frameImage() }
    precondition(render(retained, width: 800, height: 600) == snapshot, "Published image mutated")
}
print("OK: \(comparisons) retro comparisons match indexed rendering exactly; retained snapshots remain immutable.")
