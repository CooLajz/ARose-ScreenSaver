import AppKit

// Render a real deterministic ARose frame without altering user preferences.
let app = NSApplication.shared
let view = ARoseView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), isPreview: true)!
view.engine.modern = true
view.glow = 0.85
view.engine.speed = 3
view.engine.tail = 20
for _ in 0..<1100 { view.engine.step() }
for (width, height, name) in [(90,58,"thumbnail.png"),(180,116,"thumbnail@2x.png")] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Resources/" + name))
}
