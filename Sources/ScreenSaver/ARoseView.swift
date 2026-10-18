import AppKit
import ScreenSaver
import OSLog
import Darwin
import QuartzCore

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

// A display link retains its target; keep the view weak so legacy hosts can release it.
@available(macOS 14.0, *)
private final class RoseDisplayTarget: NSObject {
    weak var view: ARoseView?
    init(_ view: ARoseView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) {
        guard let view else { link.invalidate(); return }
        view.displayTick(at: link.targetTimestamp)
    }
}

@objc(ARoseView)
final class ARoseView: ScreenSaverView {
    static let initialSettings: [String: Any] = ["speed": 3, "tail": 16, "palette": 2, "appearance": 1, "glow": 0.8, "debugCPU": false, "resumeFigure": false, "figureReset": 0, "scaleRetro": true]
    private(set) var engine = RoseEngine()
    private var lastTime: TimeInterval = 0
    private var accumulator: TimeInterval = 0
    private var displayClock: AnyObject?
    private var animationActive = false
    private var hasStartedAnimation = false
    private var awaitingFirstAnimationFrame = false
    private var screenObserver: NSObjectProtocol?
    private var previousHistory = [[RoseEngine.ModernPoint]]()
    private var interpolationEnabled = false
    private var presentationRevision: UInt64 = 0
    private var presentationHistory: [[RoseEngine.ModernPoint]]? {
        interpolationEnabled ? RoseInterpolation.history(previous: previousHistory, current: engine.modernHistory,
                                                          alpha: accumulator / 0.02) : nil
    }

    private func updateDisplayClock() {
        guard #available(macOS 14.0, *) else { return }
        let wanted = animationActive && engine.modern && window != nil
        if !wanted {
            (displayClock as? CADisplayLink)?.invalidate()
            displayClock = nil
            return
        }
        guard displayClock == nil else { return }
        // Prepare GPU resources before starting the display clock.
        displayAnimationFrame()
        let link = displayLink(target: RoseDisplayTarget(self), selector: #selector(RoseDisplayTarget.tick(_:)))
        let maximum = Float(max(1, window?.screen?.maximumFramesPerSecond ?? 60))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
        link.add(to: .main, forMode: .common)
        displayClock = link
        lastTime = 0
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRetroRaster()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let window {
            screenObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification,
                object: window, queue: .main) { [weak self] _ in self?.viewDidChangeBackingProperties() }
        }
        if #available(macOS 14.0, *) { (displayClock as? CADisplayLink)?.invalidate() }
        displayClock = nil
        updateDisplayClock()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateRetroRaster()
        needsLayout = true
        if #available(macOS 14.0, *), let link = displayClock as? CADisplayLink {
            let maximum = Float(max(1, window?.screen?.maximumFramesPerSecond ?? 60))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
        }
    }
    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if #available(macOS 14.0, *) { (displayClock as? CADisplayLink)?.invalidate() }
    }
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
    private var cpuTextUpdatedAt = 0.0
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
    // Extension hosts can request a stopped view for the Settings thumbnail.
    // Keep its poster independent of the real simulation and saved figure.
    var showsIdlePreview = false
    private var idlePreviewRequested = false
    private var idlePreviewImage: CGImage?
    private var idlePreviewSize = NSSize.zero

    override convenience init?(frame: NSRect, isPreview: Bool) {
        self.init(frame: frame, isPreview: isPreview,
                  settings: ScreenSaverDefaults(forModuleWithName: "cz.coolajz.ARose")!)
    }
    // The companion app and tests inject their own isolated preference domains.
    init?(frame: NSRect, isPreview: Bool, settings: UserDefaults) {
        defaults = settings
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 50.0
        defaults.register(defaults: Self.initialSettings)
        reset()
    }
    required init?(coder: NSCoder) {
        defaults = ScreenSaverDefaults(forModuleWithName: "cz.coolajz.ARose")!
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 50.0
        defaults.register(defaults: Self.initialSettings)
        reset()
    }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private func configuration() -> [Double] {
        ["appearance", "speed", "tail", "palette", "glow", "debugCPU", "resumeFigure", "figureReset", "scaleRetro"].map { defaults.double(forKey: $0) }
    }
    override func startAnimation() {
        defaults.synchronize()
        requestIdlePreview(false)
        // Repeated host requests must not reset a running presentation clock.
        if animationActive {
            if configuration() != loadedConfiguration { applyConfiguration() }
            return
        }
        idlePreviewImage = nil
        configurationLog.notice("Figure start preview=\(self.isPreview) size=\(self.bounds.width)x\(self.bounds.height) enabled=\(self.defaults.bool(forKey: "resumeFigure"))")
        // A real new session starts fresh, then optionally restores its bookmark.
        // Keep first-start warm-up and temporary thumbnail stop/start unchanged.
        if configuration() != loadedConfiguration || (!isPreview && hasStartedAnimation) { reset() }
        updateRetroRaster()
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
        cpuTextUpdatedAt = 0
        super.startAnimation()
        animationActive = true
        hasStartedAnimation = true
        awaitingFirstAnimationFrame = engine.modern && engine.modernHistory.isEmpty
        updateDisplayClock()
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
        animationActive = false
        awaitingFirstAnimationFrame = false
        updateDisplayClock()
        saveFigure()
        figureSession = false
        if Self.figureWriter === self { Self.figureWriter = nil }
        super.stopAnimation()
        lastTime = 0; accumulator = 0
        if idlePreviewRequested { needsDisplay = true }
    }
    func requestIdlePreview(_ requested: Bool) {
        guard idlePreviewRequested != requested else { return }
        idlePreviewRequested = requested
        if !requested { idlePreviewImage = nil }
        needsDisplay = true
    }
    func applyConfiguration() {
        if adoptFigureReset() { refreshPresentation(); return }
        let state = defaults.bool(forKey: "resumeFigure") ? engine.savedFigure() : nil
        reset()
        if let state { engine.restoreFigure(state) }
        refreshPresentation()
    }
    // Manual commands must update Metal even when the animation clock is paused.
    // Discard old interpolation endpoints and invalidate every in-flight slot's cache.
    private func refreshPresentation() {
        previousHistory = engine.modernHistory
        interpolationEnabled = false
        accumulator = 0
        presentationRevision &+= 1
        modernColors.removeAll(keepingCapacity: true)
        displayAnimationFrame()
    }
    func restartAnimation() {
        reset()
        refreshPresentation()
    }
    func advanceFrames(_ count: Int) {
        for _ in 0..<max(0, count) { engine.step() }
        refreshPresentation()
    }
    func reset() {
        idlePreviewImage = nil
        loadedConfiguration = configuration()
        figureResetGeneration = defaults.double(forKey: "figureReset")
        lastFigureSave = 0
        debugCPU = defaults.bool(forKey: "debugCPU")
        cpuMeter = RoseCPUMeter()
        cpuTextUpdatedAt = 0
        modernColors.removeAll(keepingCapacity: true)
        previousHistory.removeAll()
        interpolationEnabled = false
        presentationRevision &+= 1
        engine = RoseEngine()
        let storedGlow = defaults.double(forKey: "glow")
        glow = storedGlow.isFinite ? min(1, max(0, storedGlow)) : 0
        engine.scaleRetro = defaults.bool(forKey: "scaleRetro")
        engine.modern = defaults.integer(forKey: "appearance") == 1
        updateRetroRaster()
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
        updateDisplayClock()
    }
    override func animateOneFrame() {
        // The host/preview timer remains the fallback for retro and older macOS.
        guard displayClock == nil else { return }
        advanceAnimation(at: ProcessInfo.processInfo.systemUptime, interpolate: false)
    }
    fileprivate func displayTick(at time: TimeInterval) {
        guard animationActive else { return }
        advanceAnimation(at: time, interpolate: true)
    }
    func advanceAnimation(at now: TimeInterval, interpolate: Bool) {
        if paused {
            if debugCPU { displayAnimationFrame() }
            lastTime = now
            return
        }
        if lastTime == 0 {
            previousHistory = engine.modernHistory
            engine.step()
            awaitingFirstAnimationFrame = false
            interpolationEnabled = false
            presentationRevision &+= 1
            displayAnimationFrame()
            checkpointFigureIfNeeded()
            // Initial shader/atlas/drawable preparation is not elapsed animation
            // time. Start the clock only after the first image is submitted.
            lastTime = interpolate ? now : ProcessInfo.processInfo.systemUptime
            return
        }
        defer {
            lastTime = now
            checkpointFigureIfNeeded()
        }
        // Preserve PAL pacing even on 60/120 Hz displays; discard time spent asleep.
        accumulator += min(0.1, max(0, now - lastTime))
        let previousFrame = engine.frame
        while accumulator + 1e-12 >= 0.02 {
            if interpolate { previousHistory = engine.modernHistory }
            engine.step(); presentationRevision &+= 1; accumulator = max(0, accumulator - 0.02)
        }
        interpolationEnabled = interpolate
        // Timer jitter can call us before the next PAL step. Keep the existing
        // image instead of redrawing an identical frame; never clear pending damage.
        if interpolate || engine.frame != previousFrame { displayAnimationFrame() }
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
        return CGImage(width: engine.rasterWidth, height: engine.rasterHeight,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: engine.rasterWidth * 4,
                       space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
                           .union(.byteOrder32Big), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    // Submit directly from the animation clock, not a coalesced AppKit draw pass.
    private func displayAnimationFrame() {
        // Restoring a bookmark restores geometry but starts with empty trails.
        // Publishing that empty Metal frame exposes a black gap during the
        // system fade. Wait for the first real simulation tick instead.
        if awaitingFirstAnimationFrame && engine.modernHistory.isEmpty { return }
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
                if debugCPU { updateCPUText() }
                if renderer.present(size: bounds.size, backing: backing, history: engine.modernHistory,
                                    glow: glow, previous: interpolationEnabled ? previousHistory : engine.modernHistory,
                                    alpha: interpolationEnabled ? accumulator / 0.02 : 1, revision: presentationRevision, overlay: debugCPU ? { self.drawMetalOverlay(in: $0) } : nil,
                                    overlayKey: debugCPU ? cpuText : nil) { return }
                renderer.surface.isHidden = true
            }
        } else { metalRenderer?.surface.isHidden = true }
        needsDisplay = true
    }
    private func updateRetroRaster() {
        guard !engine.modern, bounds.width > 0, bounds.height > 0 else { return }
        let backing = window?.backingScaleFactor ?? 1
        engine.resizeRaster(width: Int((bounds.width * backing).rounded()),
                            height: Int((bounds.height * backing).rounded()))
    }
    override func layout() {
        super.layout()
        updateRetroRaster()
        guard let renderer = metalRenderer, let window else { return }
        if renderer.surface.frame != bounds || renderer.surface.contentsScale != window.backingScaleFactor {
            displayAnimationFrame()
        }
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
        if showsIdlePreview && idlePreviewRequested && !animationActive && engine.frame == 0 {
            if idlePreviewImage == nil || idlePreviewSize != bounds.size {
                idlePreviewImage = makeIdlePreviewImage()
                idlePreviewSize = bounds.size
            }
            if let image = idlePreviewImage {
                context.interpolationQuality = .high
                context.draw(image, in: bounds)
            }
            return
        }
        defer { if debugCPU { drawCPU(in: context) } }
        if engine.modern { drawModern(in: context); return }
        guard let image = frameImage() else { return }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(image, in: bounds)
    }
    private func makeIdlePreviewImage() -> CGImage? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        // The system displays this as a small still image. A bounded raster
        // avoids allocating another full-screen backing store in the service.
        let scale = min(1, 640 / max(bounds.width, bounds.height))
        let width = max(1, Int((bounds.width * scale).rounded()))
        let height = max(1, Int((bounds.height * scale).rounded()))
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        guard let poster = ARoseView(frame: frame, isPreview: true, settings: defaults),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        // Use the shared renderer and current appearance/palette/glow settings.
        // This detached preview never starts a figure session or saves defaults.
        let state = defaults.array(forKey: figureStorageKey) as? [Int]
        let restored = defaults.bool(forKey: "resumeFigure") && state.map { poster.engine.restoreFigure($0) } == true
        for _ in 0..<(restored ? poster.engine.tail : 600) { poster.engine.step() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        poster.draw(frame)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }
    private func updateCPUText() {
        let now = ProcessInfo.processInfo.systemUptime
        guard cpuTextUpdatedAt == 0 || now - cpuTextUpdatedAt >= 1 else { return }
        cpuTextUpdatedAt = now
        cpuMeter.sample()
        let single = cpuMeter.singleCorePercent.map { String(format: "%.1f %%", $0) } ?? "—"
        let total = cpuMeter.percent.map { String(format: "%.1f %%", $0) } ?? "—"
        let value = "\(roseText("1 core")): \(single)  |  \(roseText("All cores")): \(total)"
        if value != cpuTextValue {
            cpuTextValue = value
            cpuText = roseText("Process CPU") + "\n" + value
            cpuTextSize = (cpuText as NSString).size(withAttributes: cpuTextAttributes)
        }
    }
    private func drawCPU(in context: CGContext) {
        updateCPUText()
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
        let history = presentationHistory ?? engine.modernHistory
        if interpolationEnabled { modernColors.removeAll(keepingCapacity: true) }
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
            for (age, points) in history.enumerated() {
                let strength = 0.25 + 0.75 * Double(age + 1) / Double(history.count)
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
        let oldestFrame = engine.frame - history.count
        for key in Array(modernColors.keys) where key < oldestFrame || key >= engine.frame {
            modernColors.removeValue(forKey: key)
        }
        for (age, points) in history.enumerated() {
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
            let alpha = 0.25 + 0.75 * Double(age + 1) / Double(history.count)
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
        }
        options?.reload()
        configurationLog.notice("Created configuration: content=\(String(describing: self.options?.window.contentView?.frame), privacy: .public)")
        return options?.window
    }
}

final class RoseOptions: NSObject {
    let contentViewController = NSViewController()
    var dismissHandler: (() -> Void)?
    lazy var window: NSWindow = {
        let window = NSWindow(contentViewController: contentViewController)
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.title = roseText("ARose Settings")
        return window
    }()
    private let defaults: UserDefaults
    private let apply: () -> Void
    private let speed = NSPopUpButton(), tail = NSPopUpButton(), palette = NSPopUpButton()
    private let appearance = NSPopUpButton()
    private let debugCPU = NSButton(checkboxWithTitle: roseText("Debug: show process CPU usage"), target: nil, action: nil)
    private let scaleRetro = NSButton(checkboxWithTitle: roseText("Scale retro figures to display resolution"), target: nil, action: nil)
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
        super.init()
        // The same controls can be hosted by a local window, legacy sheet or appex.
        contentViewController.view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 680))
        contentViewController.preferredContentSize = NSSize(width: 460, height: 680)
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
        stack.addArrangedSubview(scaleRetro)
        let scaleNote = NSTextField(wrappingLabelWithString: roseText("Retro scaling explanation"))
        scaleNote.font = .systemFont(ofSize: 11)
        scaleNote.textColor = .secondaryLabelColor
        scaleNote.widthAnchor.constraint(equalToConstant: 412).isActive = true
        stack.addArrangedSubview(scaleNote)
        stack.addArrangedSubview(resumeFigure)
        stack.addArrangedSubview(forgetButton)
        stack.addArrangedSubview(debugCPU)
        stack.addArrangedSubview(NSButton(title: roseText("Installation and updates…"), target: self, action: #selector(openUpdates)))
        let cancel = NSButton(title: roseText("Cancel"), target: self, action: #selector(cancelAction))
        let save = NSButton(title: roseText("Save"), target: self, action: #selector(saveAction))
        save.keyEquivalent = "\r"; cancel.keyEquivalent = "\u{1b}"
        stack.addArrangedSubview(NSStackView(views: [cancel, save]))
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentViewController.view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: contentViewController.view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentViewController.view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentViewController.view.topAnchor, constant: 24)])
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
        scaleRetro.state = defaults.bool(forKey: "scaleRetro") ? .on : .off
        resumeFigure.state = defaults.bool(forKey: "resumeFigure") ? .on : .off
        debugCPU.state = defaults.bool(forKey: "debugCPU") ? .on : .off
        glowChanged()
        updatePalette()
    }
    @objc private func openUpdates() {
        // Prefer the enclosing app for an extension, even when an older
        // companion with the same bundle identifier is still installed.
        let resourceBundle = Bundle(for: ARoseView.self).bundleURL
        let enclosingApp = resourceBundle.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let appURL = resourceBundle.pathExtension == "appex" && enclosingApp.pathExtension == "app"
            ? enclosingApp : NSWorkspace.shared.urlForApplication(withBundleIdentifier: "cz.coolajz.ARose.Preview")
        guard let app = appURL else {
            let alert = NSAlert()
            alert.messageText = roseText("Install the companion app to manage updates.")
            alert.informativeText = roseText("The standalone screen saver works without the companion app.")
            alert.addButton(withTitle: roseText("OK"))
            if let parent = contentViewController.view.window { alert.beginSheetModal(for: parent) }
            return
        }
        // First launch of a newly installed host app can make Launch Services
        // re-register its extension even if our app never calls pluginkit -a.
        // Complete the remote sheet before that can invalidate its connection.
        // This is a navigation action, not Save: pending edits stay uncommitted.
        dismissHandler?()
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                let alert = NSAlert()
                alert.messageText = roseText("Unable to open the companion app.")
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: roseText("OK"))
                if let parent = self.contentViewController.view.window { alert.beginSheetModal(for: parent) }
            }
        }
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
        scaleRetro.isEnabled = !modern
        palette.isEnabled = !modern
        glowSlider.isEnabled = modern
        glowValue.textColor = modern ? .labelColor : .disabledControlTextColor
    }
    private func dismiss() {
        if let dismissHandler { dismissHandler(); return }
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
        defaults.set(scaleRetro.state == .on, forKey: "scaleRetro")
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
