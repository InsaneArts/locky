// Draws Locky's app icon, Sources/Locky/Resources/AppIcon.icns: a night sky with an aurora over a ridge, and
// a white lock. Run: swift Scripts/make_icon.swift (needs iconutil, which ships with macOS).
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "Locky.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    // Apple's grid: an 824-point squircle on a 1024 canvas.
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    color(0x050a16).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [color(0x02040a), color(0x0b1a33), color(0x0f2a40)])!.draw(in: tile, angle: 90)
    // The aurora: thin rays along a wave, bright where they start and fading upward, green to blue to violet.
    let rays = 160
    for i in 0..<rays {
        let t = CGFloat(i) / CGFloat(rays - 1)
        let base = tile.minY + tile.height * (0.40 + 0.07 * sin(t * .pi * 2.1 + 0.5))
        let height = tile.height * (0.22 + 0.20 * (0.5 + 0.5 * sin(t * .pi * 6.3 + 1.1)) * (0.6 + 0.4 * sin(t * .pi * 1.7)))
        let hue = t < 0.55 ? color(0x22ee88).blended(withFraction: t / 0.55, of: color(0x1694e8))!
            : color(0x1694e8).blended(withFraction: (t - 0.55) / 0.45, of: color(0xa533f8))!
        let rect = CGRect(x: tile.minX + tile.width * t, y: base, width: tile.width / CGFloat(rays - 1) + 1 * s, height: height)
        NSGradient(colors: [hue.withAlphaComponent(0), hue.withAlphaComponent(0.62), hue.withAlphaComponent(0.18), hue.withAlphaComponent(0)],
                   atLocations: [0, 0.08, 0.45, 1], colorSpace: .sRGB)!.draw(in: rect, angle: 90)
    }
    // A soft glow where the rays start.
    NSGradient(colors: [color(0x22ee88, 0.28), color(0x22ee88, 0)])!
        .draw(in: NSBezierPath(ovalIn: CGRect(x: tile.minX + tile.width * 0.05, y: tile.minY + tile.height * 0.30, width: tile.width * 0.7, height: tile.height * 0.28)),
              relativeCenterPosition: .zero)
    // Stars.
    var seed: UInt32 = 7
    for _ in 0..<40 {
        seed = seed &* 1_103_515_245 &+ 12345
        let px = CGFloat(seed % 1000) / 1000
        seed = seed &* 1_103_515_245 &+ 12345
        let py = CGFloat(seed % 1000) / 1000
        let r = (1.5 + CGFloat(seed % 3)) * s
        color(0xffffff, 0.55).setFill()
        NSBezierPath(ovalIn: CGRect(x: tile.minX + tile.width * px, y: tile.minY + tile.height * (0.45 + py * 0.55), width: r * 2, height: r * 2)).fill()
    }
    // The ridge.
    let ridge = NSBezierPath()
    ridge.move(to: CGPoint(x: tile.minX, y: tile.minY))
    for (x, y) in [(0.0, 0.26), (0.18, 0.34), (0.33, 0.27), (0.52, 0.38), (0.70, 0.29), (0.86, 0.35), (1.0, 0.28)] as [(CGFloat, CGFloat)] {
        ridge.line(to: CGPoint(x: tile.minX + tile.width * x, y: tile.minY + tile.height * y))
    }
    ridge.line(to: CGPoint(x: tile.maxX, y: tile.minY))
    ridge.close()
    color(0x04070f).setFill()
    ridge.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The lock.
    let config = NSImage.SymbolConfiguration(pointSize: 360 * s, weight: .semibold).applying(.init(paletteColors: [.white]))
    if let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let glyph = lock.size
        let rect = CGRect(x: tile.midX - glyph.width / 2, y: tile.midY - glyph.height / 2 + 30 * s, width: glyph.width, height: glyph.height)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = color(0x22ee88, 0.6)
        glow.shadowBlurRadius = 40 * s
        glow.set()
        lock.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                     ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try draw(size: CGFloat(size)).representation(using: .png, properties: [:])!.write(to: iconset.appending(path: "icon_\(name).png"))
}
let out = root.appending(path: "Sources/Locky/Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? out.path : "iconutil failed")
