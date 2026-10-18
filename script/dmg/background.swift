import AppKit
let size = NSSize(width: 680, height: 420)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
func text(_ value: String, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let width = (value as NSString).size(withAttributes: attributes).width
    (value as NSString).draw(at: NSPoint(x: (680 - width) / 2, y: y), withAttributes: attributes)
}
text("ARose", y: 338, size: 34, color: NSColor(calibratedWhite: 0.15, alpha: 1), weight: .semibold)
text("Amiga 1995 · macOS today", y: 309, size: 14, color: .darkGray)
text("→", y: 177, size: 52, color: NSColor(calibratedWhite: 0.55, alpha: 1), weight: .light)
text("Přetáhněte ARose do složky Aplikace", y: 69, size: 16, color: .darkGray, weight: .medium)
text("Drag ARose to Applications", y: 44, size: 14, color: .gray)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
