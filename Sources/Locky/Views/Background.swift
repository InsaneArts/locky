import AppKit
import AVFoundation
import CoreImage
import ImageIO
import MetalKit

enum Backgrounds {
    /// `overlay`: drawn above the widgets with transparency, for scanlines, grain, or a vignette.
    /// `still` (Low Power Mode, Reduce Motion, or battery_saver on battery) draws a shader once and keeps a video on its
    /// first frame.
    /// `epoch` is when a shader's animation starts: a preview that replaces its session keeps it, so the
    /// animation goes on where it was.
    @MainActor
    static func makeView(_ background: Theme.Background, screen: NSScreen?, overlay: Bool = false, still: Bool = false,
                         epoch: CFTimeInterval? = nil) -> NSView {
        if overlay {
            let container = OverlayContainer()
            let content = makeView(background, screen: screen, transparent: true, still: still, epoch: epoch)
            content.autoresizingMask = [.width, .height]
            container.addSubview(content)
            return container
        }
        return makeView(background, screen: screen, transparent: false, still: still, epoch: epoch)
    }

    @MainActor
    private static func makeView(_ background: Theme.Background, screen: NSScreen?, transparent: Bool, still: Bool,
                                 epoch: CFTimeInterval?) -> NSView {
        switch background {
        case .shader(let url, let colors, let speed, let resolution, let fps, let params, let dim):
            return ShaderView.make(url: url, colors: colors, speed: speed, resolution: resolution, fps: still ? 0 : fps, params: params, dim: dim,
                                   transparent: transparent, epoch: epoch)
        case .wallpaper(let blur, let dim, let tint, let tintAmount):
            let view = PictureView(dim: dim, tint: tint, tintAmount: tintAmount)
            view.load(screen.flatMap(Wallpaper.picture(for:)), blur: blur)
            return view
        case .image(let url, let blur, let dim):
            let view = PictureView(dim: dim, tint: nil, tintAmount: 0)
            if transparent { view.layer?.backgroundColor = NSColor.clear.cgColor }
            view.load(url, blur: blur)
            return view
        case .video(let url, let dim):
            return VideoView(url: url, dim: dim, playing: !still)
        case .color(let hex):
            return GradientView(colors: [hex, hex], angle: 180, noise: 0)
        case .gradient(let colors, let angle, let noise):
            return GradientView(colors: colors, angle: angle, noise: noise)
        }
    }

    /// Changes a view makeView made for `old` to show `new`, in place, when that can be done: the same picture
    /// with another blur, dim, or tint, the same video with another dim, or another color or gradient. The view
    /// changes smoothly, without a blank moment. false when `new` needs a new view.
    @MainActor
    static func update(_ view: NSView, from old: Theme.Background, to new: Theme.Background) -> Bool {
        switch (old, new, view) {
        case (.wallpaper, .wallpaper(let blur, let dim, let tint, let tintAmount), let picture as PictureView):
            picture.set(blur: blur, dim: dim, tint: tint, tintAmount: tintAmount)
        case (.image(let before, _, _), .image(let after, let blur, let dim), let picture as PictureView) where before == after:
            picture.set(blur: blur, dim: dim, tint: nil, tintAmount: 0)
        case (.video(let before, _), .video(let after, let dim), let video as VideoView) where before == after:
            video.set(dim: dim)
        case (.color, .color(let hex), let gradient as GradientView), (.gradient, .color(let hex), let gradient as GradientView):
            gradient.set(colors: [hex, hex], angle: 180, noise: 0)
        case (.color, .gradient(let colors, let angle, let noise), let gradient as GradientView),
             (.gradient, .gradient(let colors, let angle, let noise), let gradient as GradientView):
            gradient.set(colors: colors, angle: angle, noise: noise)
        default:
            return false
        }
        return true
    }
}

/// A background with more to load after it shows: a picture, a video's first frame, a shader's first frame. The
/// theme editor's preview waits for it before it fades a new background in.
@MainActor
protocol BackgroundLoading: AnyObject {
    var isLoaded: Bool { get }
}

/// Runs a theme's `shade(uv, t, res, p)` on every pixel, every frame. The source compiles at runtime, so a
/// theme ships a .metal file and no binary. See docs/themes.md for the contract.
final class ShaderView: MTKView, MTKViewDelegate, BackgroundLoading {
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
    private var start = CACurrentMediaTime()
    /// Whether a frame has been drawn.
    private(set) var isLoaded = false

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
                     transparent: Bool = false, epoch: CFTimeInterval? = nil) -> NSView {
        guard let device = MTLCreateSystemDefaultDevice() else { return MessageView("No Metal device") }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let view = ShaderView(frame: .zero, device: device)
            if let epoch { view.start = epoch }
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
        isLoaded = true
    }
}

/// Holds an overlay above the widgets. It never takes clicks: the password field and Touch ID sit above it
/// anyway, and nothing below should lose a click to a decoration.
final class OverlayContainer: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A picture, optionally blurred, dimmed, and tinted: the user's wallpaper or an image file.
final class PictureView: NSView, BackgroundLoading {
    private let dimLayer = CALayer()
    private let tintLayer = CALayer()
    /// Whether the picture is in place, or there is none to load.
    private(set) var isLoaded = false
    private var url: URL?
    private var blur = 0.0
    /// The picture at a working size before the blur, and how much it was reduced: another blur starts from it.
    private var reduced: (image: CGImage, scale: Double)?
    private var rendering: Task<Void, Never>?

    /// The picture is darkened by `dim` (0...1), then mixed with `tint` by `tintAmount`.
    init(dim: Double, tint: String?, tintAmount: Double) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
        layer?.addSublayer(dimLayer)
        layer?.addSublayer(tintLayer)
        shade(dim: dim, tint: tint, tintAmount: tintAmount)
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

    private func shade(dim: Double, tint: String?, tintAmount: Double) {
        dimLayer.backgroundColor = NSColor.black.withAlphaComponent(dim).cgColor
        tintLayer.backgroundColor = (tint.flatMap(NSColor.init(hex:)) ?? .clear).withAlphaComponent(tint == nil ? 0 : tintAmount).cgColor
    }

    /// Loads and blurs off the main thread; the picture appears when ready. Without a picture, it stays black.
    func load(_ url: URL?, blur: Double) {
        self.url = url
        self.blur = blur
        reduced = nil
        guard url != nil else {
            isLoaded = true
            return
        }
        render()
    }

    /// Another blur, dim, or tint for the same picture: the dim and tint change at once, and the picture keeps its
    /// old blur until the new one is ready.
    func set(blur: Double, dim: Double, tint: String?, tintAmount: Double) {
        shade(dim: dim, tint: tint, tintAmount: tintAmount)
        guard blur != self.blur else { return }
        self.blur = blur
        if url != nil { render() }
    }

    private func render() {
        let url = url, reduced = reduced
        let sigma = blur * Double(NSScreen.main?.backingScaleFactor ?? 2)
        rendering?.cancel()
        rendering = Task.detached(priority: .userInitiated) { [weak self] in
            var working = reduced
            let image: CGImage?
            if sigma > 0 {
                // Big wallpapers blur faster at a reduced size, and a blurred picture loses nothing by it.
                if working == nil, let url { working = Self.read(url, longest: 3000) }
                image = working.flatMap { Self.blurred($0.image, sigma: sigma * $0.scale) }
            } else {
                image = url.flatMap { Self.read($0, longest: nil)?.image }
            }
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                if let working { self.reduced = working }
                if let image { self.layer?.contents = image }
                self.isLoaded = true
            }
        }
    }

    /// Thread-safe, like every CIContext; it keeps no intermediate images, which are big for a wallpaper.
    private static let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    /// The picture, reduced to at most `longest` pixels across when that is given, and the scale it was reduced by.
    nonisolated private static func read(_ url: URL, longest: CGFloat?) -> (image: CGImage, scale: Double)? {
        guard let source = CIImage(contentsOf: url) else { return nil }
        let size = max(source.extent.width, source.extent.height)
        let reduce = longest.map { size > $0 ? $0 / size : 1 } ?? 1
        let image = source.transformed(by: CGAffineTransform(scaleX: reduce, y: reduce))
        return context.createCGImage(image, from: image.extent).map { ($0, Double(reduce)) }
    }

    nonisolated private static func blurred(_ picture: CGImage, sigma: Double) -> CGImage? {
        let image = CIImage(cgImage: picture)
        let extent = image.extent
        return context.createCGImage(image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent), from: extent)
    }
}

/// Plays a video on a silent loop, like a Wallpaper Engine video wallpaper.
final class VideoView: NSView, BackgroundLoading {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private let shade = CALayer()

    /// Whether its first frame is ready.
    var isLoaded: Bool { (layer as? AVPlayerLayer)?.isReadyForDisplay ?? true }

    func set(dim: Double) {
        shade.backgroundColor = NSColor.black.withAlphaComponent(dim).cgColor
    }

    /// Not `playing`, it shows the video's first frame.
    init(url: URL, dim: Double, playing: Bool = true) {
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
        if playing { player.play() }
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
        layer?.addSublayer(gradient)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        set(colors: colors, angle: angle, noise: noise)
        CATransaction.commit()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Other colors, angle, or grain; outside a transaction that disables actions, the change animates.
    func set(colors: [String], angle: Double, noise: Double) {
        gradient.colors = colors.map { (NSColor(hex: $0) ?? .black).cgColor }
        let radians = (angle - 90) * .pi / 180
        gradient.startPoint = CGPoint(x: 0.5 - cos(radians) / 2, y: 0.5 + sin(radians) / 2)
        gradient.endPoint = CGPoint(x: 0.5 + cos(radians) / 2, y: 0.5 - sin(radians) / 2)
        if noise > 0, grain.superlayer == nil {
            grain.contents = Self.noiseTile
            grain.compositingFilter = "overlayBlendMode"
            grain.frame = bounds
            layer?.addSublayer(grain)
        }
        grain.opacity = Float(min(max(noise, 0), 1))
    }

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
    /// $LOCKY_WALLPAPER replaces it, for screenshots and theme work: an image file, or "none" for no picture.
    @MainActor
    static func picture(for screen: NSScreen) -> URL? {
        if let override = ProcessInfo.processInfo.environment["LOCKY_WALLPAPER"] {
            return override == "none" ? nil : URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
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
