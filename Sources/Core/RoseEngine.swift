import Foundation

/// Reconstruction of BB.ARose 1.2 (archive ARoseBlitz1.1), not an emulator.
/// Coordinates retain the original signed integer truncation and 12-bit trig tables.
final class RoseEngine {
    static let width = 800, height = 600, pointCount = 96
    struct Point { var x = 0; var y = 0 }
    struct ModernPoint {
        let x: Double, y: Double, hue: Double
    }
    var modern = false
    private(set) var modernHistory = [[ModernPoint]]()
    struct Track {
        var angle: Int
        let base: Int
        var color: Int
        var history = Array(repeating: Point(), count: 20)
    }
    struct Sequence {
        let entries: [Int]
        var index = 0, counter = 0
        mutating func next() -> (Int, Int)? {
            guard counter == entries[index] else { counter += 1; return nil }
            let result = (entries[index + 1], entries[index + 2])
            index = (index + 3) % entries.count; counter = 0
            return result
        }
    }
    private(set) var rasterWidth = 800, rasterHeight = 600
    private(set) var pixels = [UInt8](repeating: 0, count: width * height)
    private(set) var frame = 0
    private(set) var tracks = (0..<96).map { Track(angle: $0 * 15, base: $0 * 15, color: $0) }
    private var radiusA = 0, targetA = 150, deltaA = 1
    private var radiusB = 0, targetB = 0, deltaB = 1
    private var frequency = 0, targetFrequency = 0, deltaFrequency = 1
    private var rotation = 0, mode = 1, modeIndex = 0, modeCounter = 0, slot = 0
    // The original starts with nothing=TRUE, advancing point phase on the first step.
    private var changed = true
    private var a = Sequence(entries: RoseTables.radiusA)
    private var b = Sequence(entries: RoseTables.radiusB)
    private var f = Sequence(entries: RoseTables.frequency)
    let sine: [Int]
    let cosine: [Int]
    var speed = 3
    var tail = 12
    /// 0: monochrome; 1: ECS palette; 2: AGA palette.
    var paletteMode = 2

    init(width: Int = 800, height: Int = 600) {
        // The original accumulates the angle in a single-precision temporary.
        var angle: Float = 0
        var s = [Int](), c = [Int]()
        let increment = Double(bitPattern: 0x3f71df46a2529d39)
        for _ in 0..<1440 {
            s.append(Int(sin(Double(angle)) * 4096))
            c.append(Int(cos(Double(angle)) * 4096))
            angle = Float(Double(angle) + increment)
        }
        sine = s; cosine = c
        resizeRaster(width: width, height: height)
    }

    // A screen-mode change clears the trail but preserves an ongoing figure.
    func resizeRaster(width: Int, height: Int) {
        let w = max(1, width), h = max(1, height)
        if frame == 0 { targetA = min(w / 2, h / 2) / 2 }
        guard w != rasterWidth || h != rasterHeight else { return }
        rasterWidth = w; rasterHeight = h
        pixels = [UInt8](repeating: 0, count: w * h)
        for i in tracks.indices { tracks[i].history = Array(repeating: Point(), count: 20) }
        slot = 0
    }

    private func wrap(_ value: Int) -> Int { (value % 1440 + 1440) % 1440 }
    private func plot(_ point: Point, _ color: UInt8) {
        guard point.x >= 0, point.x < rasterWidth, point.y >= 0, point.y < rasterHeight else { return }
        pixels[point.y * rasterWidth + point.x] = color
    }

    func step() {
        let length = min(20, max(1, tail))
        slot %= length
        // Erase all old positions first, as the Amiga module does, including overlaps.
        for track in tracks { plot(track.history[slot], 0) }
        // The stored angle advances once; the original renders twice that angle.
        let renderRotation = wrap(2 * rotation)
        let sr = sine[renderRotation], cr = cosine[renderRotation]
        var modernPoints = [ModernPoint]()
        if modern { modernPoints.reserveCapacity(Self.pointCount) }
        let radians = Double.pi / 720
        let modernSin = sin(Double(renderRotation) * radians)
        let modernCos = cos(Double(renderRotation) * radians)
        for i in tracks.indices {
            let theta = tracks[i].angle
            if modern {
                // Evaluate before integer quantization, then draw at the destination resolution.
                let t = Double(theta) * radians
                let p = Double(frequency) * Double(tracks[i].base) / 200 * radians
                let u = Double(radiusA) * sin(t) + Double(radiusB) * sin(p)
                let v = Double(radiusA) * cos(t) + Double(radiusB) * cos(p)
                let hue = (Double(i) / Double(Self.pointCount) + Double(frame) / 1200)
                    .truncatingRemainder(dividingBy: 1)
                modernPoints.append(ModernPoint(x: v * modernCos - u * modernSin,
                                               y: v * modernSin + u * modernCos, hue: hue))
            }
            let phi = wrap(frequency * tracks[i].base / 200)
            let u = (radiusA * sine[theta] + radiusB * sine[phi]) / 4096
            let v = (radiusA * cosine[theta] + radiusB * cosine[phi]) / 4096
            let point = Point(x: rasterWidth / 2 + (v * cr - u * sr) / 4096,
                              y: rasterHeight / 2 - (v * sr + u * cr) / 4096)
            // Original resets off-screen trail coordinates to the top-left pixel.
            tracks[i].history[slot] = point.x >= 0 && point.x < rasterWidth && point.y >= 0 && point.y < rasterHeight ? point : Point()
            let color = paletteMode == 0 ? 1 : (paletteMode == 1 ? tracks[i].color / 8 + 1 : tracks[i].color + 1)
            plot(point, UInt8(color))
            tracks[i].color = (tracks[i].color + 1) % 96
        }
        if modern {
            modernHistory.append(modernPoints)
            if modernHistory.count > length { modernHistory.removeFirst(modernHistory.count - length) }
        }
        let increment = min(5, max(1, speed)) * (!modern && paletteMode == 1 ? 2 : 1)
        if mode == 1 { rotation = wrap(rotation + increment) }
        if mode == 2 || changed {
            for i in tracks.indices { tracks[i].angle = wrap(tracks[i].angle - increment) }
        }
        slot = (slot + 1) % length
        changed = true
        if frequency != targetFrequency { frequency += deltaFrequency; changed = false }
        if radiusA != targetA { radiusA += deltaA; changed = false }
        if radiusB != targetB { radiusB += deltaB; changed = false }
        if let (target, delta) = a.next() { targetA = target; deltaA = target < radiusA ? -delta : delta }
        if let (target, delta) = b.next() { targetB = target; deltaB = target < radiusB ? -delta : delta }
        if let (target, delta) = f.next() { targetFrequency = target; deltaFrequency = target < frequency ? -delta : delta }
        if modeCounter == RoseTables.rotation[modeIndex] {
            mode = RoseTables.rotation[modeIndex + 1]
            modeIndex = (modeIndex + 2) % RoseTables.rotation.count; modeCounter = 0
        } else { modeCounter += 1 }
        frame += 1
    }

    // Versioned mathematical state; trails rebuild without replaying elapsed frames.
    // Shared field order with the Windows engine. Never persist trig tables or pixels.
    func savedFigure() -> [Int] {
        [1, frame, radiusA, targetA, deltaA, radiusB, targetB, deltaB,
         frequency, targetFrequency, deltaFrequency, rotation, mode, modeIndex,
         modeCounter, changed ? 1 : 0, a.index, a.counter, b.index, b.counter,
         f.index, f.counter, tracks[0].angle, tracks[0].color]
    }
    @discardableResult func restoreFigure(_ v: [Int]) -> Bool {
        guard v.count == 24, v[0] == 1, (0...1_000_000_000_000).contains(v[1]),
              [2, 3, 5, 6].allSatisfy({ (-100_000...100_000).contains(v[$0]) }),
              [8, 9].allSatisfy({ (-1_000_000...1_000_000).contains(v[$0]) }),
              [4, 7, 10].allSatisfy({ (-30...30).contains(v[$0]) }),
              (0..<1440).contains(v[11]), (0...2).contains(v[12]),
              (0..<RoseTables.rotation.count).contains(v[13]), v[13] % 2 == 0,
              (0...RoseTables.rotation[v[13]]).contains(v[14]),
              (0...1).contains(v[15]), (0..<1440).contains(v[22]),
              (0..<96).contains(v[23]) else { return false }
        for (offset, table) in [(16, RoseTables.radiusA), (18, RoseTables.radiusB), (20, RoseTables.frequency)] {
            guard table.indices.contains(v[offset]), v[offset] % 3 == 0,
                  (0...table[v[offset]]).contains(v[offset + 1]) else { return false }
        }
        frame = v[1]; radiusA = v[2]; targetA = v[3]; deltaA = v[4]
        radiusB = v[5]; targetB = v[6]; deltaB = v[7]
        frequency = v[8]; targetFrequency = v[9]; deltaFrequency = v[10]
        rotation = v[11]; mode = v[12]; modeIndex = v[13]; modeCounter = v[14]; changed = v[15] == 1
        a.index = v[16]; a.counter = v[17]; b.index = v[18]; b.counter = v[19]; f.index = v[20]; f.counter = v[21]
        for i in tracks.indices {
            tracks[i].angle = wrap(v[22] + tracks[i].base)
            tracks[i].color = (v[23] + i) % 96
            tracks[i].history = Array(repeating: Point(), count: 20)
        }
        slot = 0; pixels = [UInt8](repeating: 0, count: rasterWidth * rasterHeight)
        modernHistory.removeAll()
        return true
    }

    static func palette(mode: Int) -> [UInt8] {
        var colors = [UInt8](repeating: 0, count: 256 * 3)
        if mode == 0 { colors[3...5] = [255,255,255]; return colors }
        if mode == 1 {
            let ecs: [[UInt8]] = [[255,0,0],[255,136,0],[255,255,0],[136,255,0],
                [0,255,0],[0,255,136],[0,255,255],[0,136,255],[0,0,255],
                [136,0,255],[255,0,255],[255,0,136]]
            for (i, rgb) in ecs.enumerated() { colors.replaceSubrange((i+1)*3..<(i+2)*3, with: rgb) }
        } else {
            for i in 0..<96 {
                let v = UInt8((i % 16) * 17)
                let rgb: [UInt8]
                switch i / 16 {
                case 0: rgb = [255,v,0]
                case 1: rgb = [255-v,255,0]
                case 2: rgb = [0,255,v]
                case 3: rgb = [0,255-v,255]
                case 4: rgb = [v,0,255]
                default: rgb = [255,0,255-v]
                }
                colors.replaceSubrange((i+1)*3..<(i+2)*3, with: rgb)
            }
        }
        return colors
    }
}

// Presentation only: never feeds interpolated values back into the simulation.
enum RoseInterpolation {
    static func history(previous: [[RoseEngine.ModernPoint]], current: [[RoseEngine.ModernPoint]],
                        alpha: Double) -> [[RoseEngine.ModernPoint]] {
        guard previous.count == current.count else { return current }
        let t = min(1, max(0, alpha))
        return zip(previous, current).map { old, new in
            guard old.count == new.count else { return new }
            return zip(old, new).map { a, b in
                var delta = b.hue - a.hue
                if delta > 0.5 { delta -= 1 }
                if delta < -0.5 { delta += 1 }
                let hue = a.hue + delta * t
                return RoseEngine.ModernPoint(x: a.x + (b.x - a.x) * t,
                                              y: a.y + (b.y - a.y) * t,
                                              hue: hue - floor(hue))
            }
        }
    }
}
