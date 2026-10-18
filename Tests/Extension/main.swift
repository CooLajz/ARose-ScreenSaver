import AppKit
import ScreenSaver
import ObjectiveC

// This catches incorrect private API declarations before packaging: the host
// requires NSServiceViewController for both remote views, not NSViewController.
_ = NSApplication.shared
guard let serviceClass = NSClassFromString("NSServiceViewController") else {
    fatalError("ViewBridge service controller is unavailable")
}
// NSServiceViewController cannot be allocated outside a ViewBridge service.
// Validate its class contract here; exercise actual presentation in Settings.
precondition(ARoseExtensionViewController.isSubclass(of: serviceClass))
precondition(ARoseConfigurationViewController.isSubclass(of: serviceClass))
for cls in [ARoseExtensionViewController.self, ARoseConfigurationViewController.self] as [AnyClass] {
    var count: UInt32 = 0
    let methods = class_copyMethodList(cls, &count)!
    defer { free(methods) }
    precondition((0..<Int(count)).contains { method_getName(methods[$0]) == NSSelectorFromString("loadView") })
}
precondition(class_getInstanceMethod(ARoseConfigurationViewController.self, NSSelectorFromString("configureSheetDidEnd")) != nil)
for name in ["ARoseExtension", "ARoseExtensionViewController", "ARoseConfigurationViewController"] {
    precondition(NSClassFromString(name) != nil, "Missing extension class: \(name)")
}
print("OK: extension controllers satisfy runtime ViewBridge ancestry, entry points and completion contract.")

func litPixels(in view: ARoseView) -> Int {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width),
        pixelsHigh: Int(view.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    let pixels = bitmap.bitmapData!
    var count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let offset = y * bitmap.bytesPerRow + x * 4
            if max(pixels[offset], pixels[offset + 1], pixels[offset + 2]) > 16 { count += 1 }
        }
    }
    return count
}

// Settings requests a fresh stopped view after closing Options. It must have
// visible content without startAnimation and without advancing the real figure.
for appearance in [0, 1] {
    let suite = "ARose.IdlePreviewTest.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(appearance, forKey: "appearance")
    let seed = RoseEngine()
    for _ in 0..<100 { seed.step() }
    let bookmark = seed.savedFigure()
    defaults.set(bookmark, forKey: "figureState.v1")
    defaults.set(true, forKey: "resumeFigure")
    let view = ARoseView(frame: NSRect(x: 0, y: 0, width: 640, height: 360),
                        isPreview: false, settings: defaults)!
    view.showsIdlePreview = true
    precondition(litPixels(in: view) > 40, "Stopped extension thumbnail must not be black")
    precondition(litPixels(in: view) > 40, "Cached thumbnail must remain visible")
    precondition(view.engine.frame == 0 && !view.isAnimating)
    precondition(defaults.array(forKey: "figureState.v1") as? [Int] == bookmark)
    view.startAnimation()
    precondition(view.engine.frame == bookmark[1], "Live animation must resume the original bookmark")
    view.stopAnimation()
    defaults.set(false, forKey: "resumeFigure")
    let fresh = ARoseView(frame: view.frame, isPreview: false, settings: defaults)!
    fresh.showsIdlePreview = true
    precondition(litPixels(in: fresh) > 40, "A fresh installation also needs a visible thumbnail")
    precondition(fresh.engine.frame == 0 && !fresh.isAnimating)
}
print("OK: stopped extension thumbnails render in both styles without changing animation or saved figures.")

