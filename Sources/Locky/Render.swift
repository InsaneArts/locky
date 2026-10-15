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
    /// theme. Shaders show the frame of the moment they are drawn. With `transition`, the lock's way in or out at that
    /// point (0 to 1) of its time, over a stand-in desktop, in `style` or else settings.json's (Focus for none).
    static func image(theme: String, widget: String? = nil, size: CGSize, appearance: NSAppearance.Name?,
                      config: URL = RuntimePath.defaultConfig,
                      transition: (direction: LockTransition.Direction, progress: Double)? = nil,
                      style: LockTransition.Style? = nil) async throws -> CGImage {
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
        let now = CACurrentMediaTime()
        // Before the layout: views added after it leave the container's layer where the renderer does not see it.
        if let transition, let scene = container.subviews.first as? LockScreenView {
            stage(transition, style: style ?? settings.lockAnimation ?? .focus, scene: scene, in: container, at: now)
        }
        container.layoutSubtreeIfNeeded()
        freezeShaders(in: container)
        guard let layer = container.layer, let image = draw(layer, size: size, at: now) else { throw Failure(description: "the lock screen did not draw") }
        return image
    }

    /// The stand-in desktop and its blurred copy under the scene, and the way in or out started so long before `now` that
    /// the renderer, drawing at `now`, draws the animations the lock runs at `progress`.
    private static func stage(_ transition: (direction: LockTransition.Direction, progress: Double), style: LockTransition.Style,
                              scene: LockScreenView, in container: NSView, at now: CFTimeInterval) {
        let picture = StandInDesktop.picture(size: container.bounds.size, scale: scale)
        let desktop = NSView()
        desktop.wantsLayer = true
        desktop.layer?.contents = picture
        desktop.layer?.contentsGravity = .resize
        let backdrop = LockTransition.backdrop(reduceTransparency: false, picture: picture.flatMap { StandInDesktop.blurred($0, scale: scale) })
        let stage = TransitionStage(frame: container.bounds, scene: scene, backdrop: backdrop, desktop: desktop)
        container.addSubview(stage)
        let start = now - min(max(transition.progress, 0), 1) * LockTransition.length(transition.direction, style: style)
        let middle = CGPoint(x: scene.bounds.midX, y: scene.bounds.midY)
        switch transition.direction {
        case .lock:
            LockTransition.comeIn(stage, style: style, origin: middle, at: start, reduceMotion: false)
        case .unlock:
            let field = scene.auth.map { CGPoint(x: $0.view.frame.midX, y: $0.view.frame.midY) } ?? middle
            LockTransition.goOut(stage, style: style, origin: field, at: start)
        }
        stage.shader?.freeze(at: now, scale: scale)
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
    static func draw(_ root: CALayer, size: CGSize, at time: CFTimeInterval) -> CGImage? {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        // AppKit's own pending changes first: committed after the scale below, they would undo it.
        CATransaction.flush()
        // The renderer counts in pixels: the screen grows to them from its corner.
        root.anchorPoint = .zero
        root.position = .zero
        root.transform = CATransform3DMakeScale(scale, scale, 1)
        let renderer = CARenderer(mtlTexture: texture, options: nil)
        renderer.layer = root
        renderer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        CATransaction.flush()
        renderer.beginFrame(atTime: time, timeStamp: nil)
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
