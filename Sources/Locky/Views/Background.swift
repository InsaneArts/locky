import AppKit
import AVFoundation
import CoreImage
import ImageIO
import MetalKit

enum Backgrounds {
    /// `overlay`: drawn above the widgets with transparency, for scanlines, grain, or a vignette.
    @MainActor
    static func makeView(_ background: Theme.Background, screen: NSScreen?, overlay: Bool = false) -> NSView {
        if overlay {
            let container = OverlayContainer()
            let content = makeView(background, screen: screen, transparent: true)
            content.autoresizingMask = [.width, .height]
            container.addSubview(content)
            return container
        }
        return makeView(background, screen: screen, transparent: false)
    }

    @MainActor
    private static func makeView(_ background: Theme.Background, screen: NSScreen?, transparent: Bool) -> NSView {
        switch background {
        case .shader(let url, let colors, let speed, let resolution, let fps, let params, let dim):
            return ShaderView.make(url: url, colors: colors, speed: speed, resolution: resolution, fps: fps, params: params, dim: dim,
                                   transparent: transparent)
        case .wallpaper(let blur, let dim, let tint, let tintAmount):
            let view = PictureView(dim: dim, tint: tint, tintAmount: tintAmount)
            if let screen, let url = Wallpaper.picture(for: screen) {
                view.load(url, blur: blur)
            }
            return view
        case .image(let url, let blur, let dim):
            let view = PictureView(dim: dim, tint: nil, tintAmount: 0)
            if transparent { view.layer?.backgroundColor = NSColor.clear.cgColor }
            view.load(url, blur: blur)
            return view
        case .video(let url, let dim):
            return VideoView(url: url, dim: dim)
        case .color(let hex):
            return GradientView(colors: [hex, hex], angle: 180, noise: 0)
        case .gradient(let colors, let angle, let noise):
            return GradientView(colors: colors, angle: angle, noise: noise)
        }
    }
}

/// Runs a theme's `shade(uv, t, res, p)` on every pixel, every frame. The source compiles at runtime, so a
/// theme ships a .metal file and no binary. See docs/themes.md for the contract.
final class ShaderView: MTKView, MTKViewDelegate {
    /// Matches LockyParams in the shader header below.
    private struct Params {
        var colors: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
        var values: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
        var count: Int32
        var valueCount: Int32
        var dim: Float
        /// Local wall-clock seconds since midnight, with fractions; set every frame.
        var clock: Float = 0
    }

    private struct Uniforms {
        var time: Float
        var pad: Float = 0
        var resolution: SIMD2<Float>
    }

    private var pipeline: MTLRenderPipelineState!
    private var queue: MTLCommandQueue!
    private var params: Params!
    private var speed: Float = 1
    private var resolutionScale: CGFloat = 1
    private let start = CACurrentMediaTime()

    static let header = """
    #include <metal_stdlib>
    using namespace metal;

    struct LockyParams {
        float4 colors[8];   // the theme's colors (rgb), in order
        float4 values[4];   // params, four per float4
        int count;          // how many colors
        int value_count;    // how many params
        float dim;
        float clock;        // local time: seconds since midnight (0 to 86400), for time-of-day effects
    };

    // Color i, or the last one when the theme gave fewer.
    static inline float3 locky_color(constant LockyParams &p, int i) {
        return p.colors[clamp(i, 0, max(p.count - 1, 0))].rgb;
    }

    // Param i, or `fallback` when the theme did not give it.
    static inline float locky_param(constant LockyParams &p, int i, float fallback) {
        return i < p.value_count ? p.values[i / 4][i % 4] : fallback;
    }

    struct LockyVertex { float4 position [[position]]; };

    vertex LockyVertex locky_vertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        return { float4(p * 2.0 - 1.0, 0.0, 1.0) };
    }

    #line 1

    """

    static func footer(transparent: Bool) -> String {
        // An overlay keeps the shader's alpha (premultiplied here); a background is opaque.
        let result = transparent ? "float4(c.rgb * c.a, c.a)" : "float4(c.rgb * (1.0 - p.dim), 1.0)"
        return """

        struct LockyUniforms { float time; float pad; float2 resolution; };

        fragment float4 locky_fragment(LockyVertex in [[stage_in]],
                                       constant LockyUniforms &u [[buffer(0)]],
                                       constant LockyParams &p [[buffer(1)]]) {
            float2 uv = float2(in.position.x / u.resolution.x, 1.0 - in.position.y / u.resolution.y);
            float4 c = shade(uv, u.time, u.resolution, p);
            return \(result);
        }
        """
    }

    /// The compiled pipeline for a shader file, or the compiler's message.
    static func compile(_ source: String, device: MTLDevice, transparent: Bool = false) throws -> MTLRenderPipelineState {
        let library = try device.makeLibrary(source: header + source + footer(transparent: transparent), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "locky_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "locky_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    static func make(url: URL, colors: [String], speed: Double, resolution: Double, fps: Int, params values: [Double], dim: Double,
                     transparent: Bool = false) -> NSView {
        guard let device = MTLCreateSystemDefaultDevice() else { return MessageView("No Metal device") }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let view = ShaderView(frame: .zero, device: device)
            view.pipeline = try compile(source, device: device, transparent: transparent)
            if transparent {
                view.layer?.isOpaque = false
                view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            }
            view.queue = device.makeCommandQueue()
            view.colorPixelFormat = .bgra8Unorm
            if fps <= 0 {
                // A still picture: drawn once, and again only when the size changes.
                view.isPaused = true
                view.enableSetNeedsDisplay = true
            } else {
                view.preferredFramesPerSecond = min(fps, 120)
            }
            view.speed = Float(speed)
            view.resolutionScale = min(max(resolution, 0.25), 1)
            view.autoResizeDrawable = view.resolutionScale == 1
            (view.layer as? CAMetalLayer)?.maximumDrawableCount = 2
            view.params = makeParams(colors: colors, values: values, dim: dim)
            view.delegate = view
            return view
        } catch {
            // Show the compiler's message: someone is writing this shader and needs it.
            return MessageView("\(url.lastPathComponent) does not compile:\n\(error.localizedDescription)")
        }
    }

    private static func makeParams(colors: [String], values: [Double], dim: Double) -> Params {
        var rgb = colors.prefix(8).map { hex -> SIMD4<Float> in
            let c = NSColor(hex: hex) ?? .black
            return SIMD4(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), Float(c.alphaComponent))
        }
        while rgb.count < 8 { rgb.append(rgb.last ?? .zero) }
        var floats = values.prefix(16).map(Float.init)
        let valueCount = floats.count
        while floats.count < 16 { floats.append(0) }
        let v = stride(from: 0, to: 16, by: 4).map { SIMD4(floats[$0], floats[$0 + 1], floats[$0 + 2], floats[$0 + 3]) }
        return Params(colors: (rgb[0], rgb[1], rgb[2], rgb[3], rgb[4], rgb[5], rgb[6], rgb[7]), values: (v[0], v[1], v[2], v[3]),
                      count: Int32(max(1, min(colors.count, 8))), valueCount: Int32(valueCount), dim: Float(dim))
    }

    override func layout() {
        super.layout()
        if resolutionScale < 1, let scale = window?.backingScaleFactor {
            drawableSize = CGSize(width: bounds.width * scale * resolutionScale, height: bounds.height * scale * resolutionScale)
        }
        if isPaused { needsDisplay = true }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = Uniforms(time: Float(CACurrentMediaTime() - start) * speed,
                                resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)))
        let now = Date()
        params.clock = Float(now.timeIntervalSince(Calendar.current.startOfDay(for: now)))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<Params>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// Holds an overlay above the widgets. It never takes clicks: the password field and Touch ID sit above it
/// anyway, and nothing below should lose a click to a decoration.
final class OverlayContainer: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A picture, optionally blurred, dimmed, and tinted: the user's wallpaper or an image file.
final class PictureView: NSView {
    private let dimLayer = CALayer()
    private let tintLayer = CALayer()

    /// The picture is darkened by `dim` (0...1), then mixed with `tint` by `tintAmount`.
    init(dim: Double, tint: String?, tintAmount: Double) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
        dimLayer.backgroundColor = NSColor.black.withAlphaComponent(dim).cgColor
        tintLayer.backgroundColor = (tint.flatMap(NSColor.init(hex:)) ?? .clear).withAlphaComponent(tint == nil ? 0 : tintAmount).cgColor
        layer?.addSublayer(dimLayer)
        layer?.addSublayer(tintLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimLayer.frame = bounds
        tintLayer.frame = bounds
        CATransaction.commit()
    }

    /// Loads and blurs off the main thread; the picture appears when ready.
    func load(_ url: URL, blur: Double) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        Task.detached(priority: .userInitiated) {
            guard let image = Self.render(url, blur: blur * Double(scale)) else { return }
            await MainActor.run { [weak self] in self?.layer?.contents = image }
        }
    }

    nonisolated private static func render(_ url: URL, blur: Double) -> CGImage? {
        guard let source = CIImage(contentsOf: url) else { return nil }
        // Big wallpapers blur faster at a reduced size, and a blurred picture loses nothing by it.
        let longest = max(source.extent.width, source.extent.height)
        let reduce = blur > 0 && longest > 3000 ? 3000 / longest : 1
        var image = source.transformed(by: CGAffineTransform(scaleX: reduce, y: reduce))
        if blur > 0 {
            let extent = image.extent
            image = image.clampedToExtent().applyingGaussianBlur(sigma: blur * reduce).cropped(to: extent)
        }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(image, from: image.extent)
    }
}

/// Plays a video on a silent loop, like a Wallpaper Engine video wallpaper.
final class VideoView: NSView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private let shade = CALayer()

    init(url: URL, dim: Double) {
        super.init(frame: .zero)
        wantsLayer = true
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        layer = playerLayer
        shade.backgroundColor = NSColor.black.withAlphaComponent(dim).cgColor
        playerLayer.addSublayer(shade)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        shade.frame = bounds
    }
}

/// A linear gradient, with optional film grain so dark gradients do not band.
final class GradientView: NSView {
    private let gradient = CAGradientLayer()
    private let grain = CALayer()

    init(colors: [String], angle: Double, noise: Double) {
        super.init(frame: .zero)
        wantsLayer = true
        gradient.colors = colors.map { (NSColor(hex: $0) ?? .black).cgColor }
        let radians = (angle - 90) * .pi / 180
        gradient.startPoint = CGPoint(x: 0.5 - cos(radians) / 2, y: 0.5 + sin(radians) / 2)
        gradient.endPoint = CGPoint(x: 0.5 + cos(radians) / 2, y: 0.5 - sin(radians) / 2)
        layer?.addSublayer(gradient)
        if noise > 0 {
            grain.contents = Self.noiseTile
            grain.opacity = Float(min(noise, 1))
            grain.compositingFilter = "overlayBlendMode"
            layer?.addSublayer(grain)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        grain.frame = bounds
        CATransaction.commit()
    }

    /// 512×512 gray noise, made once.
    @MainActor private static let noiseTile: CGImage? = {
        let size = 512
        var pixels = [UInt8](repeating: 0, count: size * size)
        var seed: UInt32 = 0x9E37_79B9
        for i in pixels.indices {
            seed ^= seed << 13
            seed ^= seed >> 17
            seed ^= seed << 5
            pixels[i] = UInt8(truncatingIfNeeded: seed)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        return provider.flatMap {
            CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGBitmapInfo(rawValue: 0), provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }()
}

/// Black, with a line of text: what a broken background looks like.
final class MessageView: NSView {
    init(_ message: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        let label = NSTextField(wrappingLabelWithString: message)
        label.textColor = .systemRed
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.frame = CGRect(x: 24, y: 24, width: 900, height: 300)
        addSubview(label)
        LogFile.shared.write(level: "error", message: message, source: "background")
    }

    required init?(coder: NSCoder) { fatalError() }
}

extension NSColor {
    convenience init?(hex: String) {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let rgba = digits.count == 6 ? value << 8 | 0xFF : value
        self.init(srgbRed: CGFloat(rgba >> 24 & 0xFF) / 255, green: CGFloat(rgba >> 16 & 0xFF) / 255,
                  blue: CGFloat(rgba >> 8 & 0xFF) / 255, alpha: CGFloat(rgba & 0xFF) / 255)
    }
}

enum Wallpaper {
    /// The desktop picture of `screen` as an image file. A dynamic wallpaper (.madesktop) has no single image,
    /// so this falls back to its thumbnail, which is plenty under a blur. nil when there is nothing to show.
    @MainActor
    static func picture(for screen: NSScreen) -> URL? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        if url.pathExtension.lowercased() == "madesktop" {
            guard let plist = NSDictionary(contentsOf: url), let thumbnail = plist["thumbnailPath"] as? String else { return nil }
            let candidate = thumbnail.hasPrefix("/") ? URL(fileURLWithPath: thumbnail) : url.deletingLastPathComponent().appending(path: thumbnail)
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

extension Wallpaper {
    /// Up to `count` dominant colors of a picture, most common first, as "#rrggbb": k-means over a 48×48
    /// thumbnail, which takes a few milliseconds.
    static func colors(of url: URL, count: Int = 5) -> [String] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 48,
              ] as CFDictionary) else { return [] }
        let width = thumbnail.width, height = thumbnail.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))
        let points = stride(from: 0, to: pixels.count, by: 4).map { SIMD3<Float>(Float(pixels[$0]), Float(pixels[$0 + 1]), Float(pixels[$0 + 2])) }
        guard !points.isEmpty else { return [] }
        let k = min(count, points.count)
        // Start from evenly spaced pixels in brightness order, so runs are repeatable.
        let sorted = points.sorted { $0.sum() < $1.sum() }
        var centers = (0..<k).map { sorted[$0 * (sorted.count - 1) / max(k - 1, 1)] }
        var members = [Int](repeating: 0, count: k)
        for _ in 0..<12 {
            var sums = [SIMD3<Float>](repeating: .zero, count: k)
            members = [Int](repeating: 0, count: k)
            for point in points {
                var best = 0, bestDistance = Float.infinity
                for (index, center) in centers.enumerated() {
                    let d = point - center, distance = (d * d).sum()
                    if distance < bestDistance { bestDistance = distance; best = index }
                }
                sums[best] += point
                members[best] += 1
            }
            for index in 0..<k where members[index] > 0 { centers[index] = sums[index] / Float(members[index]) }
        }
        return zip(centers, members).filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map { center, _ in
            String(format: "#%02x%02x%02x", Int(center.x.rounded()), Int(center.y.rounded()), Int(center.z.rounded()))
        }
    }
}
