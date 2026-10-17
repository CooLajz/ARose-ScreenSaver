import AppKit
let a = CommandLine.arguments[1], b = CommandLine.arguments[2]
for name in try FileManager.default.contentsOfDirectory(atPath: a).sorted() where name.hasSuffix(".png") {
    let x = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: a+"/"+name)))!
    let y = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: b+"/"+name)))!
    precondition(x.pixelsWide == y.pixelsWide && x.pixelsHigh == y.pixelsHigh)
    var changed = 0, maximum = 0
    precondition(x.bitsPerPixel == y.bitsPerPixel && x.samplesPerPixel == y.samplesPerPixel)
    let rowBytes = x.pixelsWide * x.bitsPerPixel / 8
    for row in 0..<x.pixelsHigh {
        let u = x.bitmapData! + row*x.bytesPerRow
        let v = y.bitmapData! + row*y.bytesPerRow
        for i in 0..<rowBytes {
            let delta = abs(Int(u[i])-Int(v[i]))
            if delta > 0 { changed += 1 }; maximum = max(maximum, delta)
        }
    }
    print("\(name): changed_channels=\(changed) max_delta=\(maximum)")
    precondition(changed == 0, "Rendering differs from reference")
}
