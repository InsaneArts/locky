import AppKit
import Metal

/// `locky render`: a theme's lock screen as a picture, without a window on the screen and without Screen Recording. The
/// screen is a theme editor preview's session in a window that never shows, and Core Animation's own renderer draws its
/// layers into a texture, glass included. A capture of the views (cacheDisplay, CALayer.render) leaves glass and Metal
/// out, so it is not used.
@MainActor
enum Render {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// Pixels per point, as on a Retina display.
    static let scale: CGFloat = 2

    /// The theme with privacy mode on, whatever settings.json says. With `widget`, that widget alone, in the middle of the
    /// theme. Shaders show the frame of the moment they are drawn.
    static func image(theme: String, widget: String? = nil, size: CGSize, appearance: NSAppearance.Name?,
                      config: URL = RuntimePath.defaultConfig) async throws -> CGImage {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if let appearance { window.appearance = NSAppearance(named: appearance) }
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.wantsLayer = true
        window.contentView = container

        var settings = Settings.load(config: config).settings
        settings["privacy"] = .bool(true)
        if let widget { settings.showOnly(widget, in: theme) }
        var options = LockSession.Options(theme: theme, previewSize: size, settings: settings, container: container, remembers: false)
        options.path = .standard(config: config)
        let session = LockSession(mode: .embedded, options: options)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.onReady = { continuation.resume() }
            session.begin()
        }
        defer { session.end("rendered") }
        if let failed = session.started?.failed, failed.theme == theme { throw Failure(description: LuaError(failed.problem).summary) }
        if let widget, session.started?.theme.widgets.first?.known != true { throw Failure(description: "no widget named \"\(widget)\"") }
        container.layoutSubtreeIfNeeded()
        freezeShaders(in: container)
        guard let layer = container.layer, let image = draw(layer, size: size) else { throw Failure(description: "the lock screen did not draw") }
        return image
    }

    /// Puts a picture of each shader's frame under its sublayers (the password field's dim): the renderer draws layers'
    /// contents, not Metal drawables.
    private static func freezeShaders(in view: NSView) {
        if let shader = view as? ShaderView, let image = shader.frameImage() {
            let still = CALayer()
            still.contents = image
            still.frame = shader.bounds
            shader.layer?.insertSublayer(still, at: 0)
        }
        view.subviews.forEach(freezeShaders)
    }

    /// Renders `root` and its sublayers into a texture with CARenderer, and reads it back right side up.
    private static func draw(_ root: CALayer, size: CGSize) -> CGImage? {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        // The renderer counts in pixels: the screen grows to them from its corner.
        root.anchorPoint = .zero
        root.position = .zero
        root.transform = CATransform3DMakeScale(scale, scale, 1)
        let renderer = CARenderer(mtlTexture: texture, options: nil)
        renderer.layer = root
        renderer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        guard let buffer = queue.makeCommandBuffer(), let blit = buffer.makeBlitCommandEncoder() else { return nil }
        blit.synchronize(resource: texture)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let upsideDown = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: sRGB,
                                       bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil, shouldInterpolate: false,
                                       intent: .defaultIntent),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(upsideDown, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
