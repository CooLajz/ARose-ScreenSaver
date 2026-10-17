import Foundation
func hashPixels(_ pixels: [UInt8]) -> UInt64 {
    var hash: UInt64 = 14695981039346656037
    for pixel in pixels { hash = (hash ^ UInt64(pixel)) &* 1099511628211 }
    return hash
}
for modern in 0...1 {
    for palette in 0...2 {
        let e = RoseEngine(); e.modern = modern == 1; e.paletteMode = palette; e.tail = 16
        for frame in 1...10000 {
            e.step()
            if [1, 200, 1000, 10000].contains(frame) {
                var values = [String(modern),String(palette),String(frame),String(hashPixels(e.pixels))]
                if modern == 1 { for i in [0,17,95] { let p = e.modernHistory.last![i]; values += [String(p.x),String(p.y),String(p.hue)] } }
                print(values.joined(separator: " "))
            }
        }
        let colors = RoseEngine.palette(mode: palette)
        var packed = [String]()
        for i in 0..<256 {
            let r = UInt32(colors[i * 3]) << 16
            let g = UInt32(colors[i * 3 + 1]) << 8
            let b = UInt32(colors[i * 3 + 2])
            packed.append(String(r | g | b))
        }
        print(packed.joined(separator: " "))
    }
}
