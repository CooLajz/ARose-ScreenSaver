import AppKit
import ScreenSaver
import OSLog
import Darwin

// Resolve against the saver bundle, not the macOS host application's bundle.
private enum RoseLocalization {
    static let bundle: Bundle = {
        let resources = Bundle(for: ARoseView.self)
        let language = Bundle.preferredLocalizations(from: ["en", "cs"], forPreferences: Locale.preferredLanguages).first ?? "en"
        guard let path = resources.path(forResource: language, ofType: "lproj"),
              let localized = Bundle(path: path) else { return resources }
        return localized
    }()
}
func roseText(_ key: String) -> String {
    RoseLocalization.bundle.localizedString(forKey: key, value: key, table: nil)
}

private let configurationLog = Logger(subsystem: "cz.coolajz.ARose", category: "Configuration")

// Process CPU time divided by available logical CPUs; not weighted compute throughput.
final class RoseCPUMeter {
    private var lastWall: Double?
    private var lastCPU = 0.0
    private(set) var percent: Double?
    private(set) var singleCorePercent: Double?
    static func singleCorePercentage(cpuDelta: Double, wallDelta: Double) -> Double? {
        guard cpuDelta.isFinite, wallDelta.isFinite, cpuDelta >= 0, wallDelta > 0 else { return nil }
        let result = 100 * (cpuDelta / wallDelta)
        return result.isFinite ? result : nil
    }
    static func percentage(cpuDelta: Double, wallDelta: Double, logicalProcessors: Int = ProcessInfo.processInfo.activeProcessorCount) -> Double? {
        guard cpuDelta.isFinite, wallDelta.isFinite, cpuDelta >= 0, wallDelta > 0, logicalProcessors > 0 else { return nil }
        return min(100, 100 * cpuDelta / wallDelta / Double(logicalProcessors))
    }
    func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastWall, now - lastWall < 1 { return }
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { percent = nil; singleCorePercent = nil; lastWall = nil; return }
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        if let lastWall {
            singleCorePercent = Self.singleCorePercentage(cpuDelta: cpu - lastCPU, wallDelta: now - lastWall)
            percent = Self.percentage(cpuDelta: cpu - lastCPU, wallDelta: now - lastWall)
        }
        lastWall = now; lastCPU = cpu
    }
}

@objc(ARoseView)
final class ARoseView: ScreenSaverView {
    static let initialSettings: [String: Any] = ["speed": 3, "tail": 16, "palette": 2, "appearance": 1, "glow": 0.8, "debugCPU": false, "resumeFigure": false, "figureReset": 0]
    private(set) var engine = RoseEngine()
    private var lastTime: TimeInterval = 0
    private var accumulator: TimeInterval = 0
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var retroPalette = [UInt32]()
    private var options: RoseOptions?
    private var metalRenderer: RoseMetalRenderer?
    private var triedMetal = false
    // Diagnostic escape hatch; no new saved preference or settings schema.
    private let forceCPU = ProcessInfo.processInfo.environment["AROSE_RENDERER"] == "cpu"
    var glow = 0.0
    private var debugCPU = false
    private var cpuMeter = RoseCPUMeter()
    private var cpuTextValue = ""
    private var cpuText = ""
    private var cpuTextSize = NSSize.zero
    private let cpuTextAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white
    ]
    // Retain colors only while their simulation frame remains in the trail.
    private struct PointColors { let dot: CGColor; let core: CGColor }
    private var modernColors = [Int: [PointColors]]()
    private var loadedConfiguration = [Double]()
    private let defaults: UserDefaults
    // The standalone preview uses a separate bookmark from the system saver.
    var figureStorageKey = "figureState.v1"
    private static weak var figureWriter: ARoseView?
    private var figureSession = false
    private var lastFigureSave = 0
    private var figureResetGeneration = 0.0
    private var lastFigureActivity: TimeInterval = 0
    var paused = false
    var configurationSaved: (() -> Void)?

    override convenience init?(frame: NSRect, isPreview: Bool) {
        self.init(frame: frame, isPreview: isPreview,
                  settings: ScreenSaverDefaults(forModuleWithName: "cz.coolajz.ARose")!)
    }
    // Inject isolated preferences into rendering tests; production uses the saver domain.
    init?(frame: NSRect, isPreview: Bool, settings: UserDefaults) {
        defaults = settings
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 50.0
        defaults.register(defaults: Self.initialSettings)
        reset()
        RoseSettingsBridge.register(self)
    }
    required init?(coder: NSCoder) {
        defaults = ScreenSaverDefaults(forModuleWithName: "cz.coolajz.ARose")!
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 50.0
        defaults.register(defaults: Self.initialSettings)
        reset()
        RoseSettingsBridge.register(self)
    }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private func configuration() -> [Double] {
        ["appearance", "speed", "tail", "palette", "glow", "debugCPU", "resumeFigure", "figureReset"].map { defaults.double(forKey: $0) }
    }
    override func startAnimation() {
        configurationLog.notice("Figure start preview=\(self.isPreview) size=\(self.bounds.width)x\(self.bounds.height) enabled=\(self.defaults.bool(forKey: "resumeFigure"))")
        defaults.synchronize()
        if configuration() != loadedConfiguration { reset() }
        if !isPreview && !figureSession {
            if Self.figureWriter == nil { Self.figureWriter = self }
            lastFigureActivity = ProcessInfo.processInfo.systemUptime
            figureSession = true
            if defaults.bool(forKey: "resumeFigure"), let state = defaults.array(forKey: figureStorageKey) as? [Int] {
                let restored = engine.restoreFigure(state)
                configurationLog.notice("Figure restore success=\(restored) frame=\(self.engine.frame)")
            }
            lastFigureSave = engine.frame
        }
        lastTime = 0; accumulator = 0
        cpuMeter = RoseCPUMeter()
        super.startAnimation()
    }
    @discardableResult func adoptFigureReset() -> Bool {
        defaults.synchronize()
        let generation = defaults.double(forKey: "figureReset")
        guard generation != figureResetGeneration else { return false }
        reset()
        defaults.synchronize()
        return true
    }
    func saveFigure() {
        guard figureSession, !isPreview, Self.figureWriter === self,
              defaults.bool(forKey: "resumeFigure"), engine.frame > 0 else { return }
        guard !adoptFigureReset() else { return }
        defaults.set(engine.savedFigure(), forKey: figureStorageKey)
        guard defaults.synchronize() else {
            configurationLog.error("Figure checkpoint could not be synchronized")
            return
        }
        lastFigureSave = engine.frame
    }
    // Legacy macOS hosts can omit stopAnimation, including after short runs.
    // Checkpoint the first rendered frame and then once per second, not per draw.
    func checkpointFigureIfNeeded(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard figureSession, !isPreview, defaults.bool(forKey: "resumeFigure") else { return }
        // A legacy host can retain an inactive view without stopAnimation. A weak
        // reference alone cannot distinguish it from a live writer. Renew only
        // while frames advance; allow another view to take over an expired lease.
        if let writer = Self.figureWriter, writer !== self {
            if now - writer.lastFigureActivity > 1.5 {
                Self.figureWriter = self
                configurationLog.notice("Figure writer transferred from inactive view")
            }
        } else if Self.figureWriter == nil { Self.figureWriter = self }
        lastFigureActivity = now
        guard lastFigureSave == 0 || engine.frame - lastFigureSave >= 50 else { return }
        saveFigure()
    }
    override func stopAnimation() {
        configurationLog.notice("Figure stop preview=\(self.isPreview) session=\(self.figureSession) writer=\(Self.figureWriter === self) frame=\(self.engine.frame)")
        saveFigure()
        figureSession = false
        if Self.figureWriter === self { Self.figureWriter = nil }
        super.stopAnimation()
        lastTime = 0; accumulator = 0
    }
    func applyConfiguration() {
        if adoptFigureReset() { return }
        let state = defaults.bool(forKey: "resumeFigure") ? engine.savedFigure() : nil
        reset()
        if let state { engine.restoreFigure(state) }
    }
    func reset() {
        loadedConfiguration = configuration()
        figureResetGeneration = defaults.double(forKey: "figureReset")
        lastFigureSave = 0
        debugCPU = defaults.bool(forKey: "debugCPU")
        cpuMeter = RoseCPUMeter()
        modernColors.removeAll(keepingCapacity: true)
        engine = RoseEngine()
        let storedGlow = defaults.double(forKey: "glow")
        glow = storedGlow.isFinite ? min(1, max(0, storedGlow)) : 0
        engine.modern = defaults.integer(forKey: "appearance") == 1
        engine.speed = min(5, max(1, defaults.integer(forKey: "speed")))
        engine.tail = min(20, max(1, defaults.integer(forKey: "tail")))
        engine.paletteMode = min(2, max(0, defaults.integer(forKey: "palette")))
        let palette = RoseEngine.palette(mode: engine.paletteMode)
        // Store RGBA bytes in memory order on both supported architectures. This
        // avoids Core Graphics expanding an indexed color space on every redraw.
        retroPalette = (0..<256).map { i in
            let red = UInt32(palette[i * 3]) << 24
            let green = UInt32(palette[i * 3 + 1]) << 16
            let blue = UInt32(palette[i * 3 + 2]) << 8
            return (red | green | blue | 255).bigEndian
        }
        lastTime = 0; accumulator = 0; needsDisplay = true
    }
    override func animateOneFrame() {
        let now = ProcessInfo.processInfo.systemUptime
        if paused {
            if debugCPU { displayAnimationFrame() }
            lastTime = now
            return
        }
        if lastTime == 0 {
            engine.step()
            displayAnimationFrame()
            checkpointFigureIfNeeded()
            // Initial shader/atlas/drawable preparation is not elapsed animation
            // time. Start the clock only after the first image is submitted.
            lastTime = ProcessInfo.processInfo.systemUptime
            return
        }
        defer {
            lastTime = now
            checkpointFigureIfNeeded()
        }
        // Preserve PAL pacing even on 60/120 Hz displays; discard time spent asleep.
        accumulator += min(0.1, max(0, now - lastTime))
        let previousFrame = engine.frame
        while accumulator >= 0.02 { engine.step(); accumulator -= 0.02 }
        // Timer jitter can call us before the next PAL step. Keep the existing
        // image instead of redrawing an identical frame; never clear pending damage.
        if engine.frame != previousFrame { displayAnimationFrame() }
    }
    func frameImage() -> CGImage? {
        // The provider owns an immutable snapshot: the asynchronous compositor
        // must never observe a buffer that the next simulation step can mutate.
        var data = Data(count: engine.pixels.count * MemoryLayout<UInt32>.size)
        data.withUnsafeMutableBytes { bytes in
            let rgba = bytes.bindMemory(to: UInt32.self)
            for i in engine.pixels.indices { rgba[i] = retroPalette[Int(engine.pixels[i])] }
        }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: RoseEngine.width, height: RoseEngine.height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: RoseEngine.width * 4,
                       space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
                           .union(.byteOrder32Big), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    // Submit directly from the animation clock, not a coalesced AppKit draw pass.
    private func displayAnimationFrame() {
        if window != nil && engine.modern && !forceCPU {
            if !triedMetal {
                triedMetal = true
                metalRenderer = RoseMetalRenderer(sprites: Self.glowSprites)
                if let renderer = metalRenderer {
                    wantsLayer = true
                    layer?.addSublayer(renderer.surface)
                }
            }
            if let renderer = metalRenderer {
                let backing = window?.backingScaleFactor ?? 2
                renderer.surface.frame = bounds
                renderer.surface.contentsScale = backing
                renderer.surface.isHidden = false
                if renderer.present(size: bounds.size, backing: backing, history: engine.modernHistory,
                                    glow: glow, overlay: debugCPU ? { self.drawMetalOverlay(in: $0) } : nil) { return }
                renderer.surface.isHidden = true
            }
        } else { metalRenderer?.surface.isHidden = true }
        needsDisplay = true
    }
    override func layout() {
        super.layout()
        guard let renderer = metalRenderer, let window else { return }
        if renderer.surface.frame != bounds || renderer.surface.contentsScale != window.backingScaleFactor {
            displayAnimationFrame()
        }
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }
    var metalFrameStatistics: (submitted: Int, busy: Int, noDrawable: Int)? {
        metalRenderer?.frameStatistics
    }
    var metalBufferAllocationCount: Int? { metalRenderer?.instanceBufferAllocations }
    override func draw(_ dirtyRect: NSRect) {
        if engine.modern && metalRenderer?.surface.isHidden == false { return }
        metalRenderer?.surface.isHidden = true
        NSColor.black.setFill(); bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        defer { if debugCPU { drawCPU(in: context) } }
        if engine.modern { drawModern(in: context); return }
        guard let image = frameImage() else { return }
        let scale = min(bounds.width / 800, bounds.height / 600)
        let rect = CGRect(x: (bounds.width - 800 * scale) / 2,
                          y: (bounds.height - 600 * scale) / 2,
                          width: 800 * scale, height: 600 * scale)
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(image, in: rect)
    }
    private func drawCPU(in context: CGContext) {
        cpuMeter.sample()
        let single = cpuMeter.singleCorePercent.map { String(format: "%.1f %%", $0) } ?? "—"
        let total = cpuMeter.percent.map { String(format: "%.1f %%", $0) } ?? "—"
        let value = "\(roseText("1 core")): \(single)  |  \(roseText("All cores")): \(total)"
        if value != cpuTextValue {
            cpuTextValue = value
            cpuText = roseText("Process CPU") + "\n" + value
            cpuTextSize = (cpuText as NSString).size(withAttributes: cpuTextAttributes)
        }
        context.saveGState()
        defer { context.restoreGState() }
        context.setShouldAntialias(true)
        let size = cpuTextSize
        let box = NSRect(x: max(0, bounds.maxX - size.width - 24), y: bounds.minY + 10,
                         width: min(bounds.width, size.width + 14), height: size.height + 10)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        (cpuText as NSString).draw(in: box.insetBy(dx: 7, dy: 5), withAttributes: cpuTextAttributes)
    }
    func drawMetalOverlay(in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        drawCPU(in: context)
        NSGraphicsContext.restoreGraphicsState()
    }
    // Reference rasterizer for regression comparisons; not the production Metal path.
    func drawMetalForeground(in context: CGContext, backing: CGFloat? = nil) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        drawModern(in: context, includeGlow: false, backing: backing)
        if debugCPU { drawCPU(in: context) }
        NSGraphicsContext.restoreGraphicsState()
    }
    func drawModern(in context: CGContext, includeGlow: Bool = true, backing: CGFloat? = nil) {
        context.saveGState()
        defer { context.restoreGState() }
        // Uniform scaling keeps the rose circular on ultrawide and portrait displays.
        // Vector circles are rasterized by AppKit at the current Retina backing scale.
        let scale = min(bounds.width, bounds.height) / 640
        let backing = backing ?? window?.backingScaleFactor ?? 2
        let diameter = max(1 / backing, min(1.8, min(bounds.width, bounds.height) / 600))
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        if includeGlow && glow > 0 {
            // Add colored light before drawing the crisp cores. Cached soft sprites avoid
            // allocating blur filters or full-screen offscreen buffers on each frame.
            context.saveGState()
            context.setBlendMode(.plusLighter)
            context.interpolationQuality = .high
            let haloSize = diameter * (4 + 12 * glow)
            for (age, points) in engine.modernHistory.enumerated() {
                let strength = 0.25 + 0.75 * Double(age + 1) / Double(engine.modernHistory.count)
                context.setAlpha(glow * strength * 0.5)
                for point in points {
                    let sprite = Self.glowSprites[min(255, Int(point.hue * 256))]
                    context.draw(sprite, in: CGRect(x: bounds.midX + point.x * scale - haloSize / 2,
                                                   y: bounds.midY + point.y * scale - haloSize / 2,
                                                   width: haloSize, height: haloSize))
                }
            }
            context.restoreGState()
        }
        let oldestFrame = engine.frame - engine.modernHistory.count
        for key in Array(modernColors.keys) where key < oldestFrame || key >= engine.frame {
            modernColors.removeValue(forKey: key)
        }
        for (age, points) in engine.modernHistory.enumerated() {
            let frameID = oldestFrame + age
            let colors: [PointColors]
            if let cached = modernColors[frameID] { colors = cached }
            else {
                colors = points.map {
                    PointColors(dot: NSColor(calibratedHue: $0.hue, saturation: 0.9, brightness: 1, alpha: 1).cgColor,
                                core: NSColor(calibratedHue: $0.hue, saturation: 0.25, brightness: 1, alpha: 1).cgColor)
                }
                modernColors[frameID] = colors
            }
            let alpha = 0.25 + 0.75 * Double(age + 1) / Double(engine.modernHistory.count)
            for (index, point) in points.enumerated() {
                context.setAlpha(alpha)
                context.setFillColor(colors[index].dot)
                let x = bounds.midX + point.x * scale
                let y = bounds.midY + point.y * scale
                context.fillEllipse(in: CGRect(x: x - diameter / 2, y: y - diameter / 2,
                                               width: diameter, height: diameter))
                if glow > 0 {
                    context.setAlpha(alpha * glow * 0.8)
                    context.setFillColor(colors[index].core)
                    let core = diameter * 0.55
                    context.fillEllipse(in: CGRect(x: x - core / 2, y: y - core / 2, width: core, height: core))
                }
            }
        }
    }
    static let glowSprites: [CGImage] = (0..<256).map { index in
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                                bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let hue = Double(index) / 256
        let colors = [0.85, 0.35, 0.07, 0.0].map {
            NSColor(calibratedHue: hue, saturation: 0.95, brightness: 1, alpha: $0).cgColor
        }
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray, locations: [0, 0.25, 0.55, 1])!
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                   endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        return context.makeImage()!
    }
    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? {
        configurationLog.notice("Host requested the configuration sheet")
        // A remote host can reparent/tear down the content view when its pane
        // closes. Never export that detached window again on the next request.
        // An active local sheet must retain its controls and unsaved edits.
        if let options, options.window.sheetParent != nil || options.window.isVisible {
            configurationLog.notice("Reusing configuration: visible=\(options.window.isVisible), parent=\(options.window.sheetParent != nil), content=\(String(describing: options.window.contentView?.frame), privacy: .public)")
            return options.window
        }
        options = RoseOptions(defaults: defaults) { [weak self] in
            self?.applyConfiguration()
            self?.configurationSaved?()
        }
        options?.reload()
        configurationLog.notice("Created configuration: content=\(String(describing: self.options?.window.contentView?.frame), privacy: .public)")
        return options?.window
    }
}

// Exchange only ARose preferences. Each sandboxed host commits through its own
// ScreenSaverDefaults; no direct writes into another process's preference files.
enum RoseSettingsBridge {
    static let request = Notification.Name("cz.coolajz.ARose.settings.request")
    static let response = Notification.Name("cz.coolajz.ARose.settings.response")
    static let keys = ["appearance", "speed", "tail", "palette", "glow", "debugCPU", "resumeFigure", "figureReset"]
    static let views = NSHashTable<ARoseView>.weakObjects()
    static var observer: NSObjectProtocol?

    struct Message: Codable {
        let id: String
        let values: [String: Double]?
    }
    static func encode(_ message: Message) -> String? {
        guard let data = try? JSONEncoder().encode(message) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func decode(_ object: Any?) -> Message? {
        guard let text = object as? String, text.utf8.count < 4096,
              let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(Message.self, from: data),
              UUID(uuidString: message.id) != nil else { return nil }
        if let values = message.values {
            guard Set(values.keys) == Set(keys), values.values.allSatisfy({ $0.isFinite }),
                  [0.0, 1.0].contains(values["appearance"]!),
                  (1...5).contains(values["speed"]!), values["speed"]! == values["speed"]!.rounded(),
                  [1.0, 4, 8, 12, 16, 20].contains(values["tail"]!),
                  [0.0, 1, 2].contains(values["palette"]!),
                  (0...1).contains(values["glow"]!),
                  [0.0, 1.0].contains(values["debugCPU"]!),
                  [0.0, 1.0].contains(values["resumeFigure"]!),
                  (0...1_000_000_000_000).contains(values["figureReset"]!),
                  values["figureReset"]! == values["figureReset"]!.rounded() else { return nil }
        }
        return message
    }
    static func snapshot(_ defaults: UserDefaults) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.double(forKey: $0)) })
    }
    static func register(_ view: ARoseView) {
        guard ProcessInfo.processInfo.processName.hasPrefix("legacyScreenSaver") else { return }
        views.add(view)
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(forName: request, object: nil, queue: .main) { notification in
            guard let message = decode(notification.object),
                  let defaults = ScreenSaverDefaults(forModuleWithName: "cz.coolajz.ARose") else { return }
            defaults.synchronize()
            if let values = message.values {
                if values["figureReset"] != defaults.double(forKey: "figureReset") {
                    defaults.removeObject(forKey: "figureState.v1")
                    defaults.removeObject(forKey: "previewFigureState.v1")
                }
                for (key, value) in values { defaults.set(value, forKey: key) }
                guard defaults.synchronize() else { return }
                for view in views.allObjects { view.applyConfiguration() }
                configurationLog.notice("Settings received from preview and synchronized")
            }
            guard let reply = encode(Message(id: message.id, values: snapshot(defaults))) else { return }
            // Sandboxed processes cannot attach userInfo to distributed notifications.
            DistributedNotificationCenter.default().postNotificationName(response, object: reply, userInfo: nil, deliverImmediately: true)
        }
    }
}

final class RoseOptions: NSObject {
    let window: NSWindow
    private let defaults: UserDefaults
    private let apply: () -> Void
    private let speed = NSPopUpButton(), tail = NSPopUpButton(), palette = NSPopUpButton()
    private let appearance = NSPopUpButton()
    private let debugCPU = NSButton(checkboxWithTitle: roseText("Debug: show process CPU usage"), target: nil, action: nil)
    private let resumeFigure = NSButton(checkboxWithTitle: roseText("Resume from last figure"), target: nil, action: nil)
    private var forgetPending = false
    private lazy var forgetButton = NSButton(title: roseText("Forget saved figure"), target: self, action: #selector(forgetAction))
    private var originalPalette = 2
    private let glowSlider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let glowValue = NSTextField(labelWithString: roseText("Off"))
    private let paletteTitles = [roseText("Black and white"), roseText("Amiga ECS · 16 colors"), roseText("Amiga AGA · 256 colors")]
    private let tailValues = [1, 4, 8, 12, 16, 20]

    init(defaults: UserDefaults, apply: @escaping () -> Void) {
        self.defaults = defaults; self.apply = apply
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                          styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        // Retain the window for this presentation; subsequent requests get fresh content.
        window.isReleasedWhenClosed = false
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 520))
        window.contentViewController = content
        window.title = roseText("ARose Settings")
        speed.addItems(withTitles: [roseText("Very slow"), roseText("Slow"), roseText("Normal"), roseText("Fast"), roseText("Very fast")])
        tail.addItems(withTitles: [roseText("No trail"), roseText("Short"), roseText("Medium short"), roseText("Medium"), roseText("Long"), roseText("Longest")])
        appearance.addItems(withTitles: [roseText("Original Amiga"), roseText("Modern")])
        appearance.target = self; appearance.action = #selector(appearanceChanged)
        palette.addItems(withTitles: paletteTitles)
        let title = NSTextField(labelWithString: roseText("ARose · two styles"))
        title.font = .boldSystemFont(ofSize: 20)
        let subtitle = NSTextField(wrappingLabelWithString: roseText("Choose the original Amiga pixel graphics or fine dots at your display resolution with a smooth RGB rainbow."))
        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        for (label, control) in [(roseText("Style"), appearance), (roseText("Speed"), speed), (roseText("Trail"), tail), (roseText("Colors"), palette)] {
            let name = NSTextField(labelWithString: label)
            name.widthAnchor.constraint(equalToConstant: 80).isActive = true
            control.widthAnchor.constraint(equalToConstant: 270).isActive = true
            stack.addArrangedSubview(NSStackView(views: [name, control]))
        }
        let glowLabel = NSTextField(labelWithString: roseText("Glow"))
        glowLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
        glowSlider.widthAnchor.constraint(equalToConstant: 190).isActive = true
        glowSlider.target = self; glowSlider.action = #selector(glowChanged)
        glowSlider.isContinuous = true
        glowSlider.setAccessibilityLabel(roseText("Glow intensity"))
        glowSlider.toolTip = roseText("Adjust the intensity of the colored glow. Zero keeps the dots crisp without glow.")
        glowValue.widthAnchor.constraint(equalToConstant: 72).isActive = true
        stack.addArrangedSubview(NSStackView(views: [glowLabel, glowSlider, glowValue]))
        debugCPU.toolTip = roseText("CPU normalization explanation")
        stack.addArrangedSubview(resumeFigure)
        stack.addArrangedSubview(forgetButton)
        stack.addArrangedSubview(debugCPU)
        let cancel = NSButton(title: roseText("Cancel"), target: self, action: #selector(cancelAction))
        let save = NSButton(title: roseText("Save"), target: self, action: #selector(saveAction))
        save.keyEquivalent = "\r"; cancel.keyEquivalent = "\u{1b}"
        stack.addArrangedSubview(NSStackView(views: [cancel, save]))
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
    }
    func reload() {
        forgetPending = false
        forgetButton.title = roseText("Forget saved figure")
        defaults.synchronize()
        speed.selectItem(at: min(4, max(0, defaults.integer(forKey: "speed") - 1)))
        tail.selectItem(at: tailValues.firstIndex(of: defaults.integer(forKey: "tail")) ?? 4)
        originalPalette = min(2, max(0, defaults.integer(forKey: "palette")))
        appearance.selectItem(at: defaults.integer(forKey: "appearance") == 1 ? 1 : 0)
        let storedGlow = defaults.double(forKey: "glow")
        glowSlider.doubleValue = storedGlow.isFinite ? min(100, max(0, storedGlow * 100)) : 0
        resumeFigure.state = defaults.bool(forKey: "resumeFigure") ? .on : .off
        debugCPU.state = defaults.bool(forKey: "debugCPU") ? .on : .off
        glowChanged()
        updatePalette()
    }
    @objc private func glowChanged() {
        glowValue.stringValue = glowSlider.integerValue == 0 ? roseText("Off") : "\(glowSlider.integerValue) %"
    }
    @objc private func appearanceChanged() {
        if palette.isEnabled { originalPalette = max(0, palette.indexOfSelectedItem) }
        updatePalette()
    }
    private func updatePalette() {
        palette.removeAllItems()
        let modern = appearance.indexOfSelectedItem == 1
        palette.addItems(withTitles: modern ? [roseText("Smooth RGB rainbow")] : paletteTitles)
        palette.selectItem(at: modern ? 0 : originalPalette)
        palette.isEnabled = !modern
        glowSlider.isEnabled = modern
        glowValue.textColor = modern ? .labelColor : .disabledControlTextColor
    }
    private func dismiss() {
        configurationLog.notice("Dismissing configuration: visible=\(self.window.isVisible), parent=\(self.window.sheetParent != nil)")
        if let parent = window.sheetParent {
            parent.endSheet(window)
            window.orderOut(nil)
        } else {
            window.close()
        }
    }
    @objc private func cancelAction() {
        configurationLog.notice("Configuration cancelled")
        dismiss()
    }
    @objc private func forgetAction() {
        forgetPending = true
        forgetButton.title = roseText("Figure will reset after saving")
    }
    @objc private func saveAction() {
        if forgetPending {
            defaults.set(max(defaults.double(forKey: "figureReset") + 1, Date().timeIntervalSince1970.rounded()), forKey: "figureReset")
            defaults.removeObject(forKey: "figureState.v1")
            defaults.removeObject(forKey: "previewFigureState.v1")
        }
        defaults.set(resumeFigure.state == .on, forKey: "resumeFigure")
        defaults.set(debugCPU.state == .on, forKey: "debugCPU")
        defaults.set(speed.indexOfSelectedItem + 1, forKey: "speed")
        defaults.set(tailValues[tail.indexOfSelectedItem], forKey: "tail")
        defaults.set(appearance.indexOfSelectedItem, forKey: "appearance")
        defaults.set(appearance.indexOfSelectedItem == 1 ? originalPalette : palette.indexOfSelectedItem, forKey: "palette")
        defaults.set(glowSlider.doubleValue / 100, forKey: "glow")
        defaults.synchronize()
        configurationLog.notice("Configuration saved")
        apply(); dismiss()
    }
}
