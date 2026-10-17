import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
let engine = RoseEngine()
check(engine.sine[0] == 0 && engine.cosine[0] == 4096, "Počáteční trigonometrie")
check(engine.tracks.count == 96, "Počet bodů")
engine.step()
check(engine.tracks.allSatisfy { $0.history[0].x == 400 && $0.history[0].y == 300 }, "První snímek musí být ve středu")
engine.step()
// Original truncation makes x=400 and y=300 for radius=1 after a 0.75° rotation.
check(engine.tracks[0].history[1].x == 400 && engine.tracks[0].history[1].y == 300, "Celočíselná rotace")
for mode in 0...2 {
    let colors = RoseEngine.palette(mode: mode)
    check(colors.count == 768 && Array(colors[0..<3]) == [0,0,0], "Paleta a černé pozadí")
}
check(Array(RoseEngine.palette(mode: 2)[3..<6]) == [255,0,0], "Začátek duhy")
check(Array(RoseEngine.palette(mode: 2)[288..<291]) == [255,0,0], "Konec duhy")
var sequence = RoseEngine.Sequence(entries: [1,73,1,2,0,1])
check(sequence.next() == nil, "Časování tabulky")
check(sequence.next()!.0 == 73, "První přechod")
check(sequence.next() == nil && sequence.next() == nil, "Délka druhého přechodu")
check(sequence.next()!.0 == 0, "Druhý přechod")
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/private/tmp"
for mode in 0...2 {
    let simulation = RoseEngine(); simulation.paletteMode = mode
    // More than an hour of PAL frames exercises repeated control-table wraps.
    for tick in 1...200_000 {
        simulation.step()
        if mode == 2 && [1000,2400,7000].contains(tick) {
            let palette = RoseEngine.palette(mode: mode)
            let space = palette.withUnsafeBufferPointer { CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: 255, colorTable: $0.baseAddress!)! }
            let provider = CGDataProvider(data: Data(simulation.pixels) as CFData)!
            let image = CGImage(width: 800, height: 600, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 800, space: space, bitmapInfo: [], provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let url = URL(fileURLWithPath: output).appendingPathComponent("frame-\(tick).png")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, nil)
            check(CGImageDestinationFinalize(destination), "Export PNG")
        }
    }
    check(simulation.frame == 200_000, "Dlouhý běh")
    check(simulation.pixels.contains(where: { $0 != 0 }), "Animace nesmí zůstat prázdná")
    check(simulation.pixels.max()! <= (mode == 0 ? 1 : mode == 1 ? 12 : 96), "Indexy barev")
}
for tail in [1,20] {
    let simulation = RoseEngine(); simulation.tail = tail; simulation.speed = 5
    for _ in 0..<3000 { simulation.step() }
    check(simulation.pixels.contains(where: { $0 != 0 }), "Krajní délka stopy")
}
print("OK: matematika, tabulky, palety, krajní stopy a 600 000 snímků simulace.")

let modern = RoseEngine()
modern.modern = true
for _ in 0..<2400 { modern.step() }
check(modern.modernHistory.count == 12, "Moderní historie respektuje délku stopy")
check(modern.modernHistory.allSatisfy { $0.count == 96 }, "Moderní počet bodů")
let samples = modern.modernHistory.flatMap { $0 }
check(samples.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.hue >= 0 && $0.hue < 1 }, "Platné moderní souřadnice a odstíny")
check(samples.contains { abs($0.x - $0.x.rounded()) > 0.1 }, "Moderní souřadnice nesmějí být kvantované na celé pixely")
check(Set(samples.map { Int($0.hue * 65536) }).count > 96, "Plynulá paleta přesahuje původních 96 barev")
modern.tail = 1; modern.step()
check(modern.modernHistory.count == 1, "Zkrácení moderní stopy")
print("OK: moderní subpixelové souřadnice, plynulé odstíny a historie stop.")
