import AppKit
import Metal
import QuartzCore

/// Dissolve's and Tiles' mask on the scene, and Dissolve's rim of light over it: one Metal shader, drawn on each frame of
/// the transition and only then. It stops by itself when its time is up, and `stop` stops it sooner. The source compiles
/// at runtime once, as theme shaders do (ShaderView).
@MainActor
final class TransitionMask: NSObject {
    struct Shape {
        var tiles: Bool
        var direction: LockTransition.Direction
        /// Where it starts: the middle of the screen coming in, the password field going out. In points from the top left.
        var origin: CGPoint
        /// The scene's size in points.
        var size: CGSize
    }

    /// Matches TransitionUniforms in the source below.
    private struct Uniforms {
        var size: SIMD2<Float>
        var origin: SIMD2<Float>
        var progress: Float
        var scale: Float
        var tiles: Int32
        var unlock: Int32
    }

    /// The scene's mask: the shader's layer, and what LockTransition adds to it.
    let layer = CALayer()
    private let mask = CAMetalLayer()
    /// Dissolve only.
    private let rim: CAMetalLayer?
    private let shape: Shape
    private let begin: CFTimeInterval
    private let duration: CFTimeInterval
    private weak var scene: NSView?
    private var link: CADisplayLink?
    private(set) var isRunning = false

    private static let device = MTLCreateSystemDefaultDevice()
    private static let queue = device?.makeCommandQueue()
    /// The mask's and the light's pipelines, compiled on first use.
    private static let pipelines: (mask: MTLRenderPipelineState, light: MTLRenderPipelineState)? = {
        guard let device, let library = try? device.makeLibrary(source: source, options: nil) else { return nil }
        func pipeline(_ fragment: String) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "transition_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        guard let mask = pipeline("transition_mask"), let light = pipeline("transition_light") else { return nil }
        return (mask, light)
    }()

    /// nil without Metal. `begin` is in the scene layer's time; `light` takes the rim.
    init?(_ shape: Shape, begin: CFTimeInterval, duration: CFTimeInterval, scene: NSView, light: NSView) {
        guard let device = Self.device, Self.pipelines != nil, let sceneLayer = scene.layer else { return nil }
        self.shape = shape
        self.begin = begin
        self.duration = duration
        self.scene = scene
        rim = shape.tiles ? nil : CAMetalLayer()
        super.init()
        layer.frame = sceneLayer.bounds
        // The drawable's first row at the top of the screen, in the scene's flipped layer as in the stage's.
        layer.isGeometryFlipped = sceneLayer.contentsAreFlipped()
        for (metal, frame) in [(mask, layer.bounds), (rim, light.layer?.bounds ?? .zero)] {
            guard let metal else { continue }
            metal.device = device
            metal.pixelFormat = .bgra8Unorm
            metal.isOpaque = false
            metal.framebufferOnly = true
            // Each frame shows with the Core Animation transaction it is drawn in: never a frame without the mask.
            metal.presentsWithTransaction = true
            metal.frame = frame
        }
        layer.addSublayer(mask)
        if let rim { light.layer?.addSublayer(rim) }
    }

    /// Draws the first frame now, then one on each display refresh until the time is up.
    func start() {
        isRunning = true
        step(at: CACurrentMediaTime())
        guard isRunning, let scene else { return }
        let link = scene.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        isRunning = false
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        step(at: link.targetTimestamp)
    }

    /// Draws the frame for `time` (in the scene layer's time); past the end, the last frame, and stops.
    func step(at time: CFTimeInterval) {
        guard isRunning else { return }
        let progress = min(max((time - begin) / duration, 0), 1)
        draw(progress)
        if progress >= 1 { stop() }
    }

    /// `render` only: the frame for `time` as pictures in place of the Metal layers, which Core Animation's renderer
    /// does not draw. Stops the shader.
    func freeze(at time: CFTimeInterval, scale: CGFloat) {
        stop()
        let progress = min(max((time - begin) / duration, 0), 1)
        for (metal, pipeline) in [(mask, Self.pipelines?.mask), (rim, Self.pipelines?.light)] {
            guard let metal, let pipeline else { continue }
            let still = CALayer()
            still.frame = metal.frame
            still.contents = picture(progress, pipeline: pipeline, size: CGSize(width: metal.bounds.width * scale, height: metal.bounds.height * scale))
            metal.superlayer?.replaceSublayer(metal, with: still)
        }
    }

    // MARK: Drawing

    /// Eases the time as each style moves: Dissolve in and out, Tiles at an even pace (each tile eases on its own).
    private func eased(_ t: Double) -> Float {
        Float(shape.tiles ? t : t * t * (3 - 2 * t))
    }

    private func uniforms(_ progress: Double, pixels: CGSize) -> Uniforms {
        Uniforms(size: SIMD2(Float(shape.size.width), Float(shape.size.height)), origin: SIMD2(Float(shape.origin.x), Float(shape.origin.y)),
                 progress: eased(progress), scale: Float(pixels.width / max(shape.size.width, 1)), tiles: shape.tiles ? 1 : 0,
                 unlock: shape.direction == .unlock ? 1 : 0)
    }

    /// Pixels per point on the screen: the scene's own, also when a preview shows it smaller.
    private var backing: CGFloat {
        guard let scene, scene.bounds.width > 0 else { return 2 }
        return scene.convertToBacking(scene.bounds).width / scene.bounds.width
    }

    private func draw(_ progress: Double) {
        guard let pipelines = Self.pipelines, let queue = Self.queue else { return }
        // The mask is soft, so a pixel a point is plenty; the rim is thin and gets every pixel.
        for (metal, pipeline, density) in [(mask, pipelines.mask, min(backing, 1)), (rim, pipelines.light, backing)] {
            guard let metal else { continue }
            let pixels = CGSize(width: max((metal.bounds.width * density).rounded(), 1), height: max((metal.bounds.height * density).rounded(), 1))
            if metal.drawableSize != pixels { metal.drawableSize = pixels }
            guard let drawable = metal.nextDrawable(), let buffer = queue.makeCommandBuffer() else { continue }
            encode(progress, pipeline: pipeline, into: drawable.texture, pixels: pixels, buffer: buffer)
            buffer.commit()
            buffer.waitUntilScheduled()
            drawable.present()
        }
    }

    private func encode(_ progress: Double, pipeline: MTLRenderPipelineState, into texture: MTLTexture, pixels: CGSize, buffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var values = uniforms(progress, pixels: pixels)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&values, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// A frame drawn off the screen and read back, premultiplied.
    private func picture(_ progress: Double, pipeline: MTLRenderPipelineState, size: CGSize) -> CGImage? {
        guard let device = Self.device, let queue = Self.queue else { return nil }
        let width = max(Int(size.width), 1), height = max(Int(size.height), 1)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer() else { return nil }
        encode(progress, pipeline: pipeline, into: texture, pixels: CGSize(width: width, height: height), buffer: buffer)
        guard let blit = buffer.makeBlitCommandEncoder() else { return nil }
        blit.synchronize(resource: texture)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Both styles, each pixel's coverage (how much of the scene shows) and rim. Dissolve: fractal noise of three to four
    /// large cells across the screen, against a threshold that moves with the progress; going out, the noise is mixed
    /// with the distance from the password field, so the scene clears outward from it. Tiles: hexagons about 100 points
    /// across, each growing in and fading in on its own, in turn by distance from the origin; going out, the other way.
    nonisolated static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct TransitionUniforms {
        float2 size;      // the scene, in points
        float2 origin;    // where it starts, in points from the top left
        float progress;   // 0 to 1, eased
        float scale;      // pixels per point
        int tiles;
        int unlock;
    };

    vertex float4 transition_vertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        return float4(p * 2.0 - 1.0, 0.0, 1.0);
    }

    static float hash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    static float noise(float2 p) {
        float2 i = floor(p), f = fract(p);
        float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
        return mix(mix(hash(i), hash(i + float2(1, 0)), u.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
    }

    // Three octaves, mostly the first: large soft shapes, no fine grain.
    static float fbm(float2 p) {
        return 0.7 * noise(p) + 0.24 * noise(p * 2.03 + 17.1) + 0.06 * noise(p * 4.07 + 41.7);
    }

    // x: coverage, y: rim.
    static float2 dissolve(float2 p, constant TransitionUniforms &u) {
        float cell = max(u.size.x, u.size.y) / 3.5;
        // Spread the noise, which gathers about the middle, over 0 to 1.
        float v = saturate((fbm(p / cell + float2(3.7, 9.2)) - 0.2) / 0.6);
        if (u.unlock == 1) {
            float far = length(max(u.origin, u.size - u.origin));
            v = mix(v, distance(p, u.origin) / far, 0.55);
        }
        const float w = 0.08;
        float t = mix(-w, 1.0 + w, u.progress);
        float shown = 1.0 - smoothstep(t - w, t, v);
        float edge = (v - (t - 0.5 * w)) / (0.3 * w);
        float rim = exp(-edge * edge) * smoothstep(0.0, 0.12, u.progress) * smoothstep(1.0, 0.88, u.progress);
        return float2(u.unlock == 1 ? 1.0 - shown : shown, rim);
    }

    static float tiles(float2 p, constant TransitionUniforms &u) {
        // Pointy-top hexagons, 100 points from side to side.
        const float apothem = 50.0, radius = apothem * 2.0 / sqrt(3.0);
        float2 axial = float2((sqrt(3.0) / 3.0 * p.x - p.y / 3.0) / radius, (2.0 / 3.0 * p.y) / radius);
        float3 cube = float3(axial.x, axial.y, -axial.x - axial.y), rounded = round(cube), diff = abs(rounded - cube);
        if (diff.x > diff.y && diff.x > diff.z) rounded.x = -rounded.y - rounded.z;
        else if (diff.y > diff.z) rounded.y = -rounded.x - rounded.z;
        float2 center = radius * float2(sqrt(3.0) * rounded.x + sqrt(3.0) / 2.0 * rounded.y, 1.5 * rounded.y);
        float2 d = abs(p - center);
        float hex = max(d.x, dot(d, float2(0.5, sqrt(3.0) / 2.0))) / apothem;
        float far = length(max(u.origin, u.size - u.origin));
        const float spread = 0.55;
        float delay = spread * saturate(distance(center, u.origin) / far);
        float q = saturate((u.progress - delay) / (1.0 - spread));
        if (u.unlock == 1) q = 1.0 - q;
        float e = 1.0 - pow(1.0 - q, 3.0);
        float size = mix(0.75, 1.16, e);
        return (1.0 - smoothstep(size - 0.16, size, hex)) * smoothstep(0.0, 0.8, q);
    }

    fragment float4 transition_mask(float4 position [[position]], constant TransitionUniforms &u [[buffer(0)]]) {
        float2 p = position.xy / u.scale;
        float a = u.tiles == 1 ? tiles(p, u) : dissolve(p, u).x;
        return float4(a);
    }

    // Light, premultiplied: a soft white that brightens what is under it.
    fragment float4 transition_light(float4 position [[position]], constant TransitionUniforms &u [[buffer(0)]]) {
        float2 p = position.xy / u.scale;
        float rim = u.tiles == 1 ? 0.0 : dissolve(p, u).y;
        return float4(float3(0.35 * rim), 0.18 * rim);
    }
    """
}
