import AppKit
import QuartzCore

final class LightCanvas: NSView {
    let renderer = RoseMetalRenderer(sprites: ARoseView.glowSprites)!
    var glow = 0.8
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(renderer.surface)
    }
    required init?(coder: NSCoder) { fatalError() }
    func present(_ history: [[RoseEngine.ModernPoint]], _ previous: [[RoseEngine.ModernPoint]], _ alpha: Double, _ revision: UInt64) {
        let backing = window?.backingScaleFactor ?? 2
        renderer.surface.frame = bounds
        renderer.surface.contentsScale = backing
        _ = renderer.present(size: bounds.size, backing: backing, history: history, glow: glow,
                             previous: previous, alpha: alpha, revision: revision)
    }
}
final class Comparison: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var timer: Timer?
    var pauseKeys: Any?
    var paused = false
    let intensity = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    let intensityLabel = NSTextField(labelWithString: "Svítivost: 50 %")
    let glow = NSSlider(value: 80, minValue: 0, maxValue: 100, target: nil, action: nil)
    let glowLabel = NSTextField(labelWithString: "Záře: 80 %")
    let pointSize = NSSlider(value: 1, minValue: 0.75, maxValue: 2, target: nil, action: nil)
    let pointSizeLabel = NSTextField(labelWithString: "Velikost: 1,00×")
    @objc func pointSizeChanged() {
        right.renderer.pointScale = pointSize.doubleValue
        pointSizeLabel.stringValue = String(format: "Velikost: %.2f×", pointSize.doubleValue)
        right.present(engine.modernHistory, previous, accumulator / 0.02, revision)
    }
    @objc func glowChanged() {
        glowLabel.stringValue = "Záře: \(glow.integerValue) %"
        for canvas in [left, right] {
            canvas.glow = glow.doubleValue / 100
            canvas.present(engine.modernHistory, previous, accumulator / 0.02, revision)
        }
    }
    @objc func intensityChanged() {
        right.renderer.luminousIntensity = intensity.doubleValue / 10
        intensityLabel.stringValue = "Svítivost: \(intensity.integerValue) %"
        right.present(engine.modernHistory, previous, accumulator / 0.02, revision)
    }
    let pauseButton = NSButton(title: "Pozastavit · mezerník", target: nil, action: nil)
    @objc func togglePause() {
        paused.toggle()
        pauseButton.title = paused ? "Pokračovat · mezerník" : "Pozastavit · mezerník"
        time = ProcessInfo.processInfo.systemUptime
    }
    let engine = RoseEngine()
    var previous = [[RoseEngine.ModernPoint]]()
    var revision: UInt64 = 0
    var time = ProcessInfo.processInfo.systemUptime
    var accumulator = 0.0
    let left = LightCanvas(frame: .zero), right = LightCanvas(frame: .zero)
    func applicationDidFinishLaunching(_ notification: Notification) {
        engine.modern = true; engine.tail = 16; engine.speed = 3
        for _ in 0..<1550 { engine.step() }
        previous = engine.modernHistory
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "ARose — porovnání světelných bodů"
        window.isReleasedWhenClosed = false
        pauseButton.target = self; pauseButton.action = #selector(togglePause)
        pauseKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
            if !event.isARepeat { self?.togglePause() }
            return nil
        }
        pauseButton.bezelStyle = .rounded
        pauseButton.frame = NSRect(x: 0, y: 0, width: 220, height: 30)
        let accessory = NSTitlebarAccessoryViewController()
        intensity.target = self; intensity.action = #selector(intensityChanged)
        intensity.isContinuous = true
        intensity.setAccessibilityLabel("Svítivost bodů")
        intensity.widthAnchor.constraint(equalToConstant: 160).isActive = true
        intensityLabel.widthAnchor.constraint(equalToConstant: 140).isActive = true
        glow.target = self; glow.action = #selector(glowChanged)
        glow.isContinuous = true
        glow.setAccessibilityLabel("Záře obou variant")
        glow.widthAnchor.constraint(equalToConstant: 160).isActive = true
        glowLabel.widthAnchor.constraint(equalToConstant: 90).isActive = true
        pointSize.target = self; pointSize.action = #selector(pointSizeChanged)
        pointSize.isContinuous = true
        pointSize.setAccessibilityLabel("Velikost bodů pravé varianty")
        pointSize.toolTip = "Mění průměr bodů od 0,75× do 2×. Velikost měkké záře zůstává stejná."
        pointSize.widthAnchor.constraint(equalToConstant: 130).isActive = true
        pointSizeLabel.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let controls = NSStackView(views: [glowLabel, glow, intensityLabel, intensity, pointSizeLabel, pointSize, pauseButton])
        controls.spacing = 10
        controls.frame = NSRect(x: 0, y: 0, width: 1070, height: 36)
        accessory.view = controls; accessory.layoutAttribute = .bottom
        window.contentMinSize = NSSize(width: 1120, height: 400)
        window.addTitlebarAccessoryViewController(accessory)
        let columns = NSStackView()
        columns.distribution = .fillEqually; columns.orientation = .horizontal; columns.spacing = 2
        for (title, canvas) in [("Moderní — současný vzhled", left), ("Moderní — světelné body", right)] {
            let label = NSTextField(labelWithString: title)
            label.alignment = .center
            let column = NSStackView(views: [label, canvas])
            column.orientation = .vertical; column.alignment = .centerX
            canvas.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
            columns.addArrangedSubview(column)
        }
        columns.frame = window.contentView!.bounds
        columns.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(columns)
        right.renderer.luminousIntensity = 5
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        time = ProcessInfo.processInfo.systemUptime
        timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [self] _ in
            let now = ProcessInfo.processInfo.systemUptime
            if paused { time = now; return }
            accumulator += min(0.1, now - time); time = now
            while accumulator >= 0.02 {
                previous = engine.modernHistory; engine.step(); revision &+= 1; accumulator -= 0.02
            }
            for canvas in [left, right] { canvas.present(engine.modernHistory, previous, accumulator / 0.02, revision) }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Comparison(); app.delegate = delegate
app.run()
