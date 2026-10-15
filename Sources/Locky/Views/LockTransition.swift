import AppKit
import CoreImage

extension Settings {
    /// settings.json's lock_animation: the lock comes in and goes out with LockTransition. On unless false.
    var lockAnimation: Bool { self["lock_animation"].bool ?? true }
}

/// How a lock comes in and goes out, with settings.json's lock_animation on. In: the desktop goes out of focus under the
/// backdrop (a blur of what is behind the window), and the scene opens over it from the middle of the screen, an iris;
/// the clock, the widgets, and the password field come last. Out, after a correct password or Touch ID: the scene opens
/// from the password field onto the blurred desktop, which then comes into focus. Only opacity, transform, and a mask's
/// scale move, all in the render server: nothing runs per frame.
@MainActor
enum LockTransition {
    /// What started a lock.
    enum Trigger: Equatable {
        /// Lock Now: the menu, the shortcut, or the command line.
        case user
        case idle, displaySleep, screenSaver, systemSleep

        /// AutoLock's reason. A reason it does not know counts as a sleep, which never animates.
        init(autoLock reason: String) {
            self = switch reason {
            case "idle": .idle
            case "display sleep": .displaySleep
            case "screen saver": .screenSaver
            default: .systemSleep
            }
        }
    }

    enum Direction: String { case lock, unlock }

    /// A lock comes in animated only after Lock Now or inactivity, with the display awake. While a display sleeps (or is
    /// about to, or the Mac is) the animations may stall, and on wake the screen must already be covered: those locks
    /// cover it at once, opaque from the first frame.
    nonisolated static func animatesLock(_ trigger: Trigger, setting: Bool, displayAsleep: Bool) -> Bool {
        setting && !displayAsleep && (trigger == .user || trigger == .idle)
    }

    /// A lock goes out animated only after a correct password or Touch ID, once it has come in. A hand-over to the macOS
    /// lock screen and every other end fade as before, as does Reduce Motion.
    nonisolated static func animatesUnlock(unlocked: Bool, setting: Bool, handingOver: Bool, comingIn: Bool, reduceMotion: Bool) -> Bool {
        unlocked && setting && !handingOver && !comingIn && !reduceMotion
    }

    /// Seconds from the start until the window is opaque again (in) or orders out (out).
    nonisolated static func length(_ direction: Direction, reduceMotion: Bool = false) -> CFTimeInterval {
        switch direction {
        case .lock: reduceMotion ? 0.25 : 0.65
        case .unlock: 0.64
        }
    }

    /// The iris at full size: opaque inside `inner`, clear outside `outer` (inverted: the other way round), around
    /// `center`. `inner` passes the corner of `bounds` farthest from the center with a tenth to spare, so the scene covers
    /// the screen before the spring settles.
    struct Iris: Equatable {
        var center: CGPoint
        var inner: CGFloat
        var outer: CGFloat
    }

    /// The width of the iris's soft edge at full size: a fifth of the way to the farthest corner, 60 points at least. The
    /// edge scales with the iris, so a narrower one looks hard while the iris is small.
    nonisolated static func edge(farthest: CGFloat) -> CGFloat { max(60, farthest * 0.2) }

    nonisolated static func iris(from center: CGPoint, in bounds: CGRect) -> Iris {
        let corners = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                       CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)]
        let farthest = corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 0
        let inner = farthest * 1.1
        return Iris(center: center, inner: inner, outer: inner + edge(farthest: farthest))
    }

    /// The iris as a mask layer at full size. The edge eases from opaque to clear (a smoothstep), and ends short of the
    /// square's sides: inverted, a frame of opaque layers then overlaps the square without a seam, so everything outside
    /// the hole stays opaque however small the iris is scaled.
    static func mask(_ iris: Iris, inverted: Bool, smallest: CGFloat) -> CALayer {
        let half = iris.outer / 0.9
        let group = CALayer()
        group.bounds = CGRect(x: 0, y: 0, width: 2 * half, height: 2 * half)
        group.position = iris.center
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.frame = group.bounds
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        let steps = 10
        var colors: [CGColor] = [], locations: [NSNumber] = []
        for step in 0...steps {
            let f = CGFloat(step) / CGFloat(steps)
            let eased = f * f * (3 - 2 * f)
            colors.append(CGColor(gray: 1, alpha: inverted ? eased : 1 - eased))
            locations.append(NSNumber(value: Double((iris.inner + (iris.outer - iris.inner) * f) / half)))
        }
        gradient.colors = colors
        gradient.locations = locations
        group.addSublayer(gradient)
        if inverted {
            // Far enough that, at the smallest scale, the frame still reaches past the screen.
            let far = 2 * half / smallest
            let overlap = half * 0.08, side = 2 * half
            for frame in [CGRect(x: -far, y: -far, width: far + overlap, height: side + 2 * far),
                          CGRect(x: side - overlap, y: -far, width: far + overlap, height: side + 2 * far),
                          CGRect(x: 0, y: -far, width: side, height: far + overlap),
                          CGRect(x: 0, y: side - overlap, width: side, height: far + overlap)] {
                let solid = CALayer()
                solid.frame = frame
                solid.backgroundColor = CGColor(gray: 1, alpha: 1)
                group.addSublayer(solid)
            }
        }
        return group
    }

    /// The blur under the scene: the desktop out of focus, or with Reduce Transparency a plain dim. The preview and
    /// `render` pass a picture of their stand-in desktop, blurred.
    static func backdrop(reduceTransparency: Bool, picture: CGImage? = nil) -> NSView {
        if reduceTransparency || picture != nil {
            let view = NSView()
            view.wantsLayer = true
            if reduceTransparency {
                view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
            } else {
                view.layer?.contents = picture
                view.layer?.contentsGravity = .resize
            }
            return view
        }
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        // Locky is often not the active app as a lock starts: an inactive material would be a flat color.
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    // MARK: Animations

    /// The lock comes in from `start` (in the scene layer's time): the backdrop from 0 to 0.3 s, the iris from `origin`
    /// (in the scene's coordinates) from 0.08 s with the scene's opacity over its first 0.2 s, then the scene's items
    /// (LockScreenView.entrance). With Reduce Motion, the backdrop and the scene fade in together in 0.25 s. Each value
    /// is set to where it ends, and the animations run from where it starts.
    static func comeIn(backdrop: NSView, scene: LockScreenView, origin: CGPoint, at start: CFTimeInterval, reduceMotion: Bool) {
        backdrop.isHidden = false
        backdrop.alphaValue = 1
        guard let sceneLayer = scene.layer, let backdropLayer = backdrop.layer else { return }
        if reduceMotion {
            backdropLayer.add(fade(from: 0, to: 1, at: start, duration: 0.25), forKey: "locky.transition.opacity")
            sceneLayer.add(fade(from: 0, to: 1, at: start, duration: 0.25), forKey: "locky.transition.opacity")
            return
        }
        backdropLayer.add(fade(from: 0, to: 1, at: start, duration: 0.3), forKey: "locky.transition.opacity")
        sceneLayer.add(fade(from: 0, to: 1, at: start + 0.08, duration: 0.2), forKey: "locky.transition.opacity")
        let iris = iris(from: scene.convertToLayer(origin), in: sceneLayer.bounds)
        let smallest: CGFloat = 0.02
        let mask = mask(iris, inverted: false, smallest: smallest)
        mask.add(grow(from: smallest, at: start + 0.08), forKey: "locky.transition.iris")
        sceneLayer.mask = mask
        scene.entrance = start
    }

    /// The window is opaque again: the scene alone covers the screen.
    static func finishComingIn(backdrop: NSView, scene: LockScreenView) {
        scene.layer?.mask = nil
        backdrop.isHidden = true
        scene.entrance = nil
    }

    /// The lock goes out from `start`: the scene's items leave at once (0.18 s), the scene opens from `origin` (the
    /// password field's middle) from 0.06 s onto the backdrop, and the backdrop fades from 0.36 to 0.64 s, when the sharp
    /// desktop shows.
    static func goOut(backdrop: NSView, scene: LockScreenView, origin: CGPoint, at start: CFTimeInterval) {
        backdrop.isHidden = false
        backdrop.alphaValue = 0
        guard let sceneLayer = scene.layer, let backdropLayer = backdrop.layer else { return }
        backdropLayer.add(fade(from: 1, to: 0, at: start + 0.36, duration: 0.28), forKey: "locky.transition.opacity")
        scene.exit(at: start)
        let iris = iris(from: scene.convertToLayer(origin), in: sceneLayer.bounds)
        let smallest: CGFloat = 0.001
        let mask = mask(iris, inverted: true, smallest: smallest)
        mask.add(grow(from: smallest, at: start + 0.06), forKey: "locky.transition.iris")
        sceneLayer.mask = mask
    }

    /// The preview only: the scene as it was before `goOut` or `comeIn`, to play them again.
    static func reset(backdrop: NSView, scene: LockScreenView) {
        backdrop.layer?.removeAnimation(forKey: "locky.transition.opacity")
        scene.layer?.removeAnimation(forKey: "locky.transition.opacity")
        scene.layer?.mask = nil
        scene.resetTransition()
    }

    /// An item of the scene enters at `begin`: opacity up from 0 (added to its own, so a hidden item stays hidden) and its
    /// size from 96 % about its middle.
    static func enter(_ layer: CALayer, at begin: CFTimeInterval) {
        let opacity = spring("opacity", from: -1, to: 0, at: begin)
        opacity.isAdditive = true
        layer.add(opacity, forKey: "locky.enter.opacity")
        layer.add(spring("transform", from: centeredScale(0.96, of: layer), to: CATransform3DIdentity, at: begin), forKey: "locky.enter.transform")
    }

    /// An item of the scene leaves at `begin`, in 0.18 s: opacity down to 0 and its size up to 104 %. It stays gone.
    static func exit(_ layer: CALayer, at begin: CFTimeInterval) {
        let opacity = fade(from: 0, to: -1, at: begin, duration: 0.18)
        opacity.isAdditive = true
        opacity.fillMode = .both
        opacity.isRemovedOnCompletion = false
        layer.add(opacity, forKey: "locky.exit.opacity")
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = CATransform3DIdentity
        scale.toValue = centeredScale(1.04, of: layer)
        scale.beginTime = begin
        scale.duration = 0.18
        scale.timingFunction = Motion.easeOut
        scale.fillMode = .both
        scale.isRemovedOnCompletion = false
        layer.add(scale, forKey: "locky.exit.transform")
    }

    static func removeItemAnimations(_ layer: CALayer) {
        for key in ["locky.enter.opacity", "locky.enter.transform", "locky.exit.opacity", "locky.exit.transform"] { layer.removeAnimation(forKey: key) }
    }

    /// A scale about the layer's middle. A view's layer has its anchor at a corner.
    private static func centeredScale(_ scale: CGFloat, of layer: CALayer) -> CATransform3D {
        let x = layer.bounds.width * (0.5 - layer.anchorPoint.x), y = layer.bounds.height * (0.5 - layer.anchorPoint.y)
        return CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(x, y, 0), scale, scale, 1), -x, -y, 0)
    }

    private static func fade(from: CGFloat, to: CGFloat, at begin: CFTimeInterval, duration: CFTimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.beginTime = begin
        animation.duration = duration
        animation.timingFunction = Motion.easeOut
        animation.fillMode = .backwards
        return animation
    }

    /// The iris's spring: no bounce, a perceived 0.45 s.
    private static func grow(from smallest: CGFloat, at begin: CFTimeInterval) -> CASpringAnimation {
        let animation = CASpringAnimation(perceptualDuration: 0.45, bounce: 0)
        animation.keyPath = "transform.scale"
        animation.fromValue = smallest
        animation.toValue = 1
        animation.beginTime = begin
        animation.duration = animation.settlingDuration
        animation.fillMode = .backwards
        return animation
    }

    /// The items' spring: no bounce, a perceived 0.4 s.
    private static func spring(_ keyPath: String, from: Any, to: Any, at begin: CFTimeInterval) -> CASpringAnimation {
        let animation = CASpringAnimation(perceptualDuration: 0.4, bounce: 0)
        animation.keyPath = keyPath
        animation.fromValue = from
        animation.toValue = to
        animation.beginTime = begin
        animation.duration = animation.settlingDuration
        animation.fillMode = .backwards
        return animation
    }
}

/// A shield's content with lock_animation on: the backdrop under the scene. In the preview, a stand-in desktop under both.
/// Its background is black at 1/255, which nobody sees: no pixel of the window is clear, so no click passes through it
/// while the lock comes in.
final class TransitionStage: NSView {
    let scene: LockScreenView
    let backdrop: NSView

    init(frame: CGRect, scene: LockScreenView, backdrop: NSView, desktop: NSView? = nil) {
        self.scene = scene
        self.backdrop = backdrop
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(1 / 255).cgColor
        for view in [desktop, backdrop, scene].compactMap({ $0 }) {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// The preview's and `render`'s desktop: a few windows on a neutral gradient, and the same picture blurred as the backdrop
/// shows a desktop. A real desktop shows only through a lock's own window.
enum StandInDesktop {
    static func picture(size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        // From the top left: points count from the bottom here.
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * size.width, y: size.height - (y + h) * size.height, width: w * size.width, height: h * size.height)
        }
        let colors = [CGColor(srgbRed: 0.36, green: 0.42, blue: 0.52, alpha: 1), CGColor(srgbRed: 0.62, green: 0.56, blue: 0.52, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        }
        context.setFillColor(CGColor(gray: 1, alpha: 0.35))
        context.fill(rect(0, 0, 1, 0.027))
        for (index, frame) in [rect(0.06, 0.12, 0.42, 0.5), rect(0.4, 0.3, 0.5, 0.55), rect(0.12, 0.66, 0.26, 0.26)].enumerated() {
            let corner = 10.0
            context.setShadow(offset: CGSize(width: 0, height: -8), blur: 30, color: CGColor(gray: 0, alpha: 0.35))
            context.setFillColor(CGColor(gray: index == 1 ? 0.97 : 0.92, alpha: 1))
            context.addPath(CGPath(roundedRect: frame, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.fillPath()
            context.setShadow(offset: .zero, blur: 0, color: nil)
            // A title bar and a few lines of text, as gray bars.
            context.setFillColor(CGColor(gray: 0.84, alpha: 1))
            context.fill(CGRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 18))
            context.addPath(CGPath(roundedRect: CGRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28), cornerWidth: corner,
                                   cornerHeight: corner, transform: nil))
            context.fillPath()
            context.setFillColor(CGColor(gray: 0.72, alpha: 1))
            var y = frame.maxY - 56
            var line = 0
            while y > frame.minY + 20 {
                let length = [0.8, 0.62, 0.9, 0.45, 0.7][line % 5]
                context.fill(CGRect(x: frame.minX + 20, y: y, width: (frame.width - 40) * length, height: 8))
                y -= 22
                line += 1
            }
        }
        return context.makeImage()
    }

    /// The picture as the full-screen material shows it in Dark Mode: blurred, a little more saturated, and darker.
    static func blurred(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: input.clampedToExtent(), kCIInputRadiusKey: 40 * scale]),
              let blurred = blur.outputImage?.cropped(to: input.extent),
              let tone = CIFilter(name: "CIColorControls", parameters: [kCIInputImageKey: blurred, kCIInputSaturationKey: 1.15,
                                                                        kCIInputBrightnessKey: -0.08]),
              let output = tone.outputImage else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
    }
}
