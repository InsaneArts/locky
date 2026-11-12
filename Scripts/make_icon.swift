// Draws Locky's app icon, Sources/Locky/Resources/AppIcon.icns: Scene's icon at night. The same three hills under a
// night sky, and where Scene has its sun, a moon with a keyhole. Flat colors, no glow: macOS adds the icon's edge.
// Run: swift Scripts/make_icon.swift (needs iconutil, which ships with macOS).
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "Locky.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// One of Scene's hills, on a 1024 canvas with its origin at the top left: a wave from `left` to `right`, its crest on
/// the left and its trough on the right, filled down to the bottom.
func hill(left: CGFloat, right: CGFloat, rise: CGFloat, dip: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: left))
    path.addCurve(to: CGPoint(x: 1024, y: right), control1: CGPoint(x: 340, y: left - rise), control2: CGPoint(x: 620, y: right + dip))
    path.addLine(to: CGPoint(x: 1024, y: 1024))
    path.addLine(to: CGPoint(x: 0, y: 1024))
    path.closeSubpath()
    return path
}

/// The picture, on a 1024 canvas with its origin at the top left.
func art(_ context: CGContext) {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let sky = CGGradient(colorsSpace: sRGB, colors: [color(0x161c44), color(0x33337f), color(0x8059c2)] as CFArray, locations: [0, 0.5, 1])!
    context.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: 660), options: [.drawsAfterEndLocation])
    // The moon, where Scene's sun is, and its keyhole.
    context.setFillColor(color(0xfbe2ad))
    context.fillEllipse(in: CGRect(x: 512 - 178, y: 472 - 178, width: 356, height: 356))
    context.setFillColor(color(0x2b2a62))
    context.fillEllipse(in: CGRect(x: 512 - 46, y: 408 - 46, width: 92, height: 92))
    let slot = CGMutablePath()
    slot.move(to: CGPoint(x: 512 - 21, y: 426))
    slot.addLine(to: CGPoint(x: 512 + 21, y: 426))
    slot.addLine(to: CGPoint(x: 512 + 42, y: 552))
    slot.addLine(to: CGPoint(x: 512 - 42, y: 552))
    slot.closeSubpath()
    context.addPath(slot)
    context.fillPath()
    // Scene's hills, back to front, a shade darker for the night.
    for (fill, path) in [(0x36386e, hill(left: 592, right: 635, rise: 92, dip: 65)), (0x222449, hill(left: 715, right: 775, rise: 138, dip: 82)),
                         (0x14151e, hill(left: 838, right: 888, rise: 118, dip: 74))] as [(UInt32, CGPath)] {
        context.setFillColor(color(fill))
        context.addPath(path)
        context.fillPath()
    }
}

func draw(size: Int) -> NSBitmapImageRep {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(size) / 1024
    // The origin at the top left, in 1024ths.
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: s, y: -s)
    // Apple's grid: an 824-point squircle on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: color(0x000000, 0.35))
    context.setFillColor(color(0x14151e))
    context.addPath(shape)
    context.fillPath()
    context.restoreGState()
    context.addPath(shape)
    context.clip()
    context.translateBy(x: tile.minX, y: tile.minY)
    context.scaleBy(x: tile.width / 1024, y: tile.height / 1024)
    art(context)
    return NSBitmapImageRep(cgImage: context.makeImage()!)
}

for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                     ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try draw(size: size).representation(using: .png, properties: [:])!.write(to: iconset.appending(path: "icon_\(name).png"))
}
let out = root.appending(path: "Sources/Locky/Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? out.path : "iconutil failed")
