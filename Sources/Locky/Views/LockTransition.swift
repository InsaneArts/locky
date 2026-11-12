import AppKit
import CoreImage

extension Settings {
    /// settings.json's lock_animation: the style the lock comes in and goes out with (LockTransition), nil for none.
    /// "none" and false (an older Locky's off) are none; true (its on), a missing key, and a style this version does not
    /// know are Focus. Focus stores no key.
    var lockAnimation: LockTransition.Style? {
        get {
            switch self["lock_animation"] {
            case .bool(false), .string("none"): nil
            case .string(let name): LockTransition.Style(rawValue: name) ?? .focus
            default: .focus
            }
        }
        set { self["lock_animation"] = newValue == .focus ? .nil : .string(newValue?.rawValue ?? "none") }
    }
}

/// How a lock comes in and goes out, in one of seven styles (Style). In: the desktop goes out of focus under the backdrop
/// (a blur of what is behind the window), and the scene comes over it. Out, after a correct password or Touch ID: the
/// scene goes, the blurred desktop shows, and it comes into focus at the very end. Most styles move only opacity,
/// transform, and a mask's geometry, all in the render server; Dissolve and Tiles draw their mask with Metal on each
/// frame of the transition (TransitionMask), and only then.
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

    /// How the lock comes in and goes out. Each one moves only the backdrop's opacity, the scene's transform and opacity,
    /// a mask on the scene, and light drawn over it.
    enum Style: String, CaseIterable, Sendable {
        /// The backdrop and the scene fade in together. Reduce Motion's style, shorter.
        case fade
        /// The scene settles from a little larger as it fades in, and grows as it fades out.
        case focus
        /// The scene opens from the middle of the screen, and out from the password field.
        case iris
        /// The scene comes down from above the screen like a curtain, and lifts up off it.
        case lift
        /// A wide soft edge crosses the screen in the reading direction, with a faint sheen.
        case sweep
        /// The scene forms out of large soft clouds, and clears from the password field outward.
        case dissolve
        /// Hexagons pop in from the middle, and out from the password field.
        case tiles

        var title: String { rawValue.capitalizedFirst }
    }

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

    /// Seconds from the start until the window is opaque again (in) or orders out (out). With Reduce Motion, the lock
    /// fades in for a quarter second, whatever the style.
    nonisolated static func length(_ direction: Direction, style: Style, reduceMotion: Bool = false) -> CFTimeInterval {
        switch direction {
        case .lock:
            if reduceMotion { return 0.25 }
            return switch style {
            case .fade: 0.5
            case .focus: 0.6
            case .iris, .sweep: 0.65
            case .lift, .dissolve: 0.7
            case .tiles: 0.75
            }
        case .unlock:
            return switch style {
            case .fade, .sweep: 0.5
            case .focus, .lift, .dissolve, .tiles: 0.55
            case .iris: 0.64
            }
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

    /// The lock comes in on `stage` from `start` (in the scene layer's time), in `style`; `origin` (in the scene's
    /// coordinates) is where Iris and Tiles start. With Reduce Motion, the backdrop and the scene fade in together in
    /// 0.25 s. Each value is set to where it ends, the covering state, and the animations run from where it starts: a
    /// stalled animation still covers the screen.
    static func comeIn(_ stage: TransitionStage, style: Style, origin: CGPoint, at start: CFTimeInterval, reduceMotion: Bool) {
        let backdrop = stage.backdrop, scene = stage.scene
        backdrop.isHidden = false
        backdrop.alphaValue = 1
        guard let sceneLayer = scene.layer, let backdropLayer = backdrop.layer else { return }
        if reduceMotion {
            backdropLayer.add(fade(from: 0, to: 1, at: start, duration: 0.25), forKey: "locky.transition.opacity")
            sceneLayer.add(fade(from: 0, to: 1, at: start, duration: 0.25), forKey: "locky.transition.opacity")
            return
        }
        let length = length(.lock, style: style)
        switch style {
        case .fade:
            backdropLayer.add(fade(from: 0, to: 1, at: start, duration: 0.5, timing: smooth), forKey: "locky.transition.opacity")
            sceneLayer.add(fade(from: 0, to: 1, at: start, duration: 0.5, timing: smooth), forKey: "locky.transition.opacity")
        case .focus:
            backdropLayer.add(fade(from: 0, to: 1, at: start, duration: 0.45, timing: smooth), forKey: "locky.transition.opacity")
            sceneLayer.add(fade(from: 0, to: 1, at: start, duration: 0.35, timing: smooth), forKey: "locky.transition.opacity")
            sceneLayer.add(settle("transform", from: centeredScale(1.08, of: sceneLayer), to: CATransform3DIdentity, at: start,
                                  response: 0.42, duration: length), forKey: "locky.transition.transform")
        case .iris:
            backdropLayer.add(fade(from: 0, to: 1, at: start, duration: 0.3), forKey: "locky.transition.opacity")
            sceneLayer.add(fade(from: 0, to: 1, at: start + 0.08, duration: 0.2), forKey: "locky.transition.opacity")
            let iris = iris(from: scene.convertToLayer(origin), in: sceneLayer.bounds)
            let smallest: CGFloat = 0.02
            let mask = mask(iris, inverted: false, smallest: smallest)
            mask.add(grow(from: smallest, at: start + 0.08), forKey: "locky.transition.iris")
            sceneLayer.mask = mask
            scene.entrance = start
        case .lift:
            backdropLayer.add(fade(from: 0, to: 1, at: start, duration: 0.3, timing: smooth), forKey: "locky.transition.opacity")
            sceneLayer.add(settle("transform", from: lifted(sceneLayer), to: CATransform3DIdentity, at: start, response: 0.55, duration: length),
                           forKey: "locky.transition.transform")
            // The soft bottom edge moves past the screen's edge as the curtain lands.
            let curtain = curtain(sceneLayer.bounds)
            curtain.add(edge(curtain, in: false, at: start + 0.3, duration: length - 0.3), forKey: "locky.transition.curtain")
            sceneLayer.mask = curtain
        case .sweep:
            backdropLayer.add(fade(from: 0, to: 1, at: start, duration: 0.35, timing: smooth), forKey: "locky.transition.opacity")
            sweep(stage, coming: true, at: start, duration: length)
        case .dissolve, .tiles:
            backdropLayer.add(fade(from: 0, to: 1, at: start, duration: 0.4, timing: smooth), forKey: "locky.transition.opacity")
            // Without Metal, a fade.
            if !startShader(stage, style: style, direction: .lock, origin: origin, at: start, length: length) {
                sceneLayer.add(fade(from: 0, to: 1, at: start, duration: 0.5, timing: smooth), forKey: "locky.transition.opacity")
            }
        }
    }

    /// The window is opaque again: the scene alone covers the screen, with no mask and no light, and nothing runs per frame.
    static func finishComingIn(_ stage: TransitionStage) {
        stopShader(stage)
        stage.scene.layer?.mask = nil
        stage.backdrop.isHidden = true
        stage.scene.entrance = nil
    }

    /// The lock goes out from `start`, in `style`; `origin` is the password field's middle, where Iris, Dissolve, and
    /// Tiles clear first. The backdrop fades last, when the sharp desktop shows.
    static func goOut(_ stage: TransitionStage, style: Style, origin: CGPoint, at start: CFTimeInterval) {
        let backdrop = stage.backdrop, scene = stage.scene
        backdrop.isHidden = false
        backdrop.alphaValue = 0
        guard let sceneLayer = scene.layer, let backdropLayer = backdrop.layer else { return }
        let length = length(.unlock, style: style)
        switch style {
        case .fade:
            backdropLayer.add(focusing(at: start + 0.15, until: start + length), forKey: "locky.transition.opacity")
            sceneLayer.add(hold(fade(from: 1, to: 0, at: start, duration: 0.35, timing: smooth)), forKey: "locky.transition.opacity")
        case .focus:
            backdropLayer.add(focusing(at: start + 0.1, until: start + length), forKey: "locky.transition.opacity")
            sceneLayer.add(hold(fade(from: 1, to: 0, at: start, duration: 0.4, timing: Motion.easeOut)), forKey: "locky.transition.opacity")
            let grow = CABasicAnimation(keyPath: "transform")
            grow.fromValue = CATransform3DIdentity
            grow.toValue = centeredScale(1.1, of: sceneLayer)
            grow.beginTime = start
            grow.duration = 0.4
            grow.timingFunction = Motion.easeOut
            sceneLayer.add(hold(grow), forKey: "locky.transition.transform")
        case .iris:
            backdropLayer.add(fade(from: 1, to: 0, at: start + 0.36, duration: 0.28), forKey: "locky.transition.opacity")
            scene.exit(at: start)
            let iris = iris(from: scene.convertToLayer(origin), in: sceneLayer.bounds)
            let smallest: CGFloat = 0.001
            let mask = mask(iris, inverted: true, smallest: smallest)
            mask.add(grow(from: smallest, at: start + 0.06), forKey: "locky.transition.iris")
            sceneLayer.mask = mask
        case .lift:
            backdropLayer.add(focusing(at: start + length * 0.4, until: start + length), forKey: "locky.transition.opacity")
            scene.exit(at: start, duration: 0.1)
            let rise = CABasicAnimation(keyPath: "transform")
            rise.fromValue = CATransform3DIdentity
            rise.toValue = lifted(sceneLayer)
            rise.beginTime = start + 0.05
            rise.duration = length - 0.05
            rise.timingFunction = sweepCurve
            sceneLayer.add(hold(rise), forKey: "locky.transition.transform")
            // The soft edge comes into the screen as the curtain starts to lift.
            let curtain = curtain(sceneLayer.bounds)
            curtain.add(hold(edge(curtain, in: true, at: start + 0.05, duration: 0.15)), forKey: "locky.transition.curtain")
            sceneLayer.mask = curtain
        case .sweep:
            backdropLayer.add(focusing(at: start + length * 0.4, until: start + length), forKey: "locky.transition.opacity")
            sweep(stage, coming: false, at: start, duration: length)
        case .dissolve, .tiles:
            backdropLayer.add(focusing(at: start + length * 0.4, until: start + length), forKey: "locky.transition.opacity")
            if !startShader(stage, style: style, direction: .unlock, origin: origin, at: start, length: length) {
                sceneLayer.add(hold(fade(from: 1, to: 0, at: start, duration: 0.35, timing: smooth)), forKey: "locky.transition.opacity")
            }
        }
    }

    /// The preview only: the stage as it was before `goOut` or `comeIn`, to play them again.
    static func reset(_ stage: TransitionStage) {
        stopShader(stage)
        stage.backdrop.layer?.removeAnimation(forKey: "locky.transition.opacity")
        stage.scene.layer?.removeAnimation(forKey: "locky.transition.opacity")
        stage.scene.layer?.removeAnimation(forKey: "locky.transition.transform")
        stage.scene.layer?.mask = nil
        stage.scene.resetTransition()
    }

    /// An item of the scene enters at `begin`: opacity up from 0 (added to its own, so a hidden item stays hidden) and its
    /// size from 96 % about its middle.
    static func enter(_ layer: CALayer, at begin: CFTimeInterval) {
        let opacity = spring("opacity", from: -1, to: 0, at: begin)
        opacity.isAdditive = true
        layer.add(opacity, forKey: "locky.enter.opacity")
        layer.add(spring("transform", from: centeredScale(0.96, of: layer), to: CATransform3DIdentity, at: begin), forKey: "locky.enter.transform")
    }

    /// An item of the scene leaves at `begin`, in `duration`: opacity down to 0 and its size up to 104 %. It stays gone.
    static func exit(_ layer: CALayer, at begin: CFTimeInterval, duration: CFTimeInterval = 0.18) {
        let opacity = fade(from: 0, to: -1, at: begin, duration: duration)
        opacity.isAdditive = true
        layer.add(hold(opacity), forKey: "locky.exit.opacity")
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = CATransform3DIdentity
        scale.toValue = centeredScale(1.04, of: layer)
        scale.beginTime = begin
        scale.duration = duration
        scale.timingFunction = Motion.easeOut
        layer.add(hold(scale), forKey: "locky.exit.transform")
    }

    static func removeItemAnimations(_ layer: CALayer) {
        for key in ["locky.enter.opacity", "locky.enter.transform", "locky.exit.opacity", "locky.exit.transform"] { layer.removeAnimation(forKey: key) }
    }

    // MARK: Lift and Sweep

    /// Lift's soft edge, at the curtain's bottom.
    private static let featherWidth: CGFloat = 24

    /// The scene moved up by its own height, just off the top of the screen. The stage is not flipped: up is +y.
    private static func lifted(_ layer: CALayer) -> CATransform3D {
        CATransform3DMakeTranslation(0, layer.bounds.height, 0)
    }

    /// Lift's mask: opaque, with soft edges just past the scene's top and bottom, so it covers all of it; `edge` moves it
    /// up, which brings the bottom edge into the scene while it moves. Soft at both ends, it reads the same either way up.
    private static func curtain(_ bounds: CGRect) -> CAGradientLayer {
        let mask = CAGradientLayer()
        mask.frame = bounds.insetBy(dx: 0, dy: -featherWidth)
        mask.startPoint = CGPoint(x: 0.5, y: 0)
        mask.endPoint = CGPoint(x: 0.5, y: 1)
        let edge = Double(featherWidth / mask.frame.height), steps = 12
        let rise = (0...steps).map { Double($0) / Double(steps) }
        mask.colors = (rise + rise.reversed()).map { f in CGColor(gray: 1, alpha: CGFloat(f * f * (3 - 2 * f))) }
        mask.locations = (rise.map { $0 * edge } + rise.map { 1 - edge + $0 * edge }).map { NSNumber(value: $0) }
        return mask
    }

    /// Lift's soft edge comes into the scene (`in`) or goes out below it. The curtain's model place is with the edge out:
    /// coming in, it ends there; going out, the animation holds the edge in.
    private static func edge(_ curtain: CALayer, in coming: Bool, at begin: CFTimeInterval, duration: CFTimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "position.y")
        let out = curtain.position.y, inside = out - featherWidth
        animation.fromValue = coming ? out : inside
        animation.toValue = coming ? inside : out
        animation.beginTime = begin
        animation.duration = duration
        animation.timingFunction = smooth
        animation.fillMode = .backwards
        return animation
    }

    /// Sweep's curve: slow off the edge, fast across the middle, slow onto the other edge.
    private static var sweepCurve: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1) }

    /// Sweep: a soft edge a third of the screen wide crosses it in the reading direction, the scene on one side, the
    /// blurred desktop on the other, with a faint sheen on the edge. Going out, it goes on the same way.
    private static func sweep(_ stage: TransitionStage, coming: Bool, at start: CFTimeInterval, duration: CFTimeInterval) {
        guard let sceneLayer = stage.scene.layer, let lightLayer = stage.light.layer else { return }
        let width = sceneLayer.bounds.width, feather = (width * 0.35).rounded()
        let rightward = stage.scene.userInterfaceLayoutDirection == .leftToRight
        // The mask is two screens and the edge wide: the scene's side, the edge, and the desktop's side, in that order
        // from the left when the scene's side leads; it moves by a screen and the edge.
        let total = 2 * width + feather, travel = width + feather
        let sceneFirst = coming == rightward
        let mask = CAGradientLayer()
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        let (colors, locations) = ramp(from: sceneFirst ? 1 : 0, to: sceneFirst ? 0 : 1, between: Double(width / total), and: Double(travel / total))
        mask.colors = colors
        mask.locations = locations
        // Rightward it ends at 0 and starts a screen and the edge to the left; leftward the other way round.
        let from = rightward ? -travel : 0, to = rightward ? 0 : -travel
        mask.frame = CGRect(x: to, y: sceneLayer.bounds.minY, width: total, height: sceneLayer.bounds.height)
        let sheen = CAGradientLayer()
        sheen.startPoint = CGPoint(x: 0, y: 0.5)
        sheen.endPoint = CGPoint(x: 1, y: 0.5)
        sheen.colors = [0, 0.1, 0].map { CGColor(gray: 1, alpha: $0) }
        sheen.locations = [0, 0.5, 1]
        sheen.frame = CGRect(x: to + width, y: 0, width: feather, height: lightLayer.bounds.height)
        for (layer, key) in [(mask as CALayer, "locky.transition.sweep"), (sheen, "locky.transition.sheen")] {
            let move = CABasicAnimation(keyPath: "position.x")
            move.fromValue = layer.position.x + from - to
            move.toValue = layer.position.x
            move.beginTime = start
            move.duration = duration
            move.timingFunction = sweepCurve
            move.fillMode = .backwards
            layer.add(move, forKey: key)
        }
        sceneLayer.mask = mask
        stage.light.isHidden = false
        lightLayer.addSublayer(sheen)
    }

    /// Gradient stops that go from `a` to `b` opacity between the locations `start` and `end`, eased (a smoothstep), with
    /// flat ends.
    private static func ramp(from a: CGFloat, to b: CGFloat, between start: Double, and end: Double) -> ([CGColor], [NSNumber]) {
        var colors: [CGColor] = [CGColor(gray: 1, alpha: a)], locations: [NSNumber] = [0]
        let steps = 12
        for step in 0...steps {
            let f = CGFloat(step) / CGFloat(steps)
            let eased = f * f * (3 - 2 * f)
            colors.append(CGColor(gray: 1, alpha: a + (b - a) * eased))
            locations.append(NSNumber(value: start + (end - start) * Double(f)))
        }
        colors.append(CGColor(gray: 1, alpha: b))
        locations.append(1)
        return (colors, locations)
    }

    // MARK: Dissolve and Tiles

    /// Starts Dissolve's or Tiles' shader on `stage`. Coming in, a solid layer in the mask fades in over the last tenth of
    /// the way in, in the render server: the scene covers the screen by the end whatever the shader drew. false without
    /// Metal.
    private static func startShader(_ stage: TransitionStage, style: Style, direction: Direction, origin: CGPoint, at start: CFTimeInterval,
                                    length: CFTimeInterval) -> Bool {
        guard let sceneLayer = stage.scene.layer else { return false }
        let scene = stage.scene
        // Points from the top left, as the shader counts.
        let top = CGPoint(x: origin.x, y: scene.isFlipped ? origin.y : scene.bounds.height - origin.y)
        let shape = TransitionMask.Shape(tiles: style == .tiles, direction: direction, origin: top, size: sceneLayer.bounds.size)
        // The shader is done a tenth before the end, coming in: the solid layer then takes over.
        let drawn = direction == .lock ? length * 0.9 : length
        guard let shader = TransitionMask(shape, begin: start, duration: drawn, scene: scene, light: stage.light) else { return false }
        if direction == .lock {
            let solid = CALayer()
            solid.frame = shader.layer.bounds
            solid.backgroundColor = CGColor(gray: 1, alpha: 1)
            let cover = CAKeyframeAnimation(keyPath: "opacity")
            cover.values = [0, 0, 1]
            cover.keyTimes = [0, 0.9, 1]
            cover.beginTime = start
            cover.duration = length
            cover.fillMode = .backwards
            solid.add(cover, forKey: "locky.transition.cover")
            shader.layer.addSublayer(solid)
        }
        stage.shader = shader
        sceneLayer.mask = shader.layer
        stage.light.isHidden = false
        shader.start()
        return true
    }

    /// Stops the shader, if one runs, and clears the light.
    private static func stopShader(_ stage: TransitionStage) {
        stage.shader?.stop()
        stage.shader = nil
        stage.light.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        stage.light.isHidden = true
    }

    // MARK: Curves

    /// A scale about the layer's middle. A view's layer has its anchor at a corner.
    private static func centeredScale(_ scale: CGFloat, of layer: CALayer) -> CATransform3D {
        let x = layer.bounds.width * (0.5 - layer.anchorPoint.x), y = layer.bounds.height * (0.5 - layer.anchorPoint.y)
        return CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(x, y, 0), scale, scale, 1), -x, -y, 0)
    }

    /// A soft ease in and out, for fades of the backdrop and the scene.
    private static var smooth: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1) }

    private static func fade(from: CGFloat, to: CGFloat, at begin: CFTimeInterval, duration: CFTimeInterval,
                             timing: CAMediaTimingFunction = Motion.easeOut) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.beginTime = begin
        animation.duration = duration
        animation.timingFunction = timing
        animation.fillMode = .backwards
        return animation
    }

    /// Going out, the blurred desktop comes into focus: the backdrop fades evenly in and out, so the desktop is sharp
    /// only at the very end.
    private static func focusing(at begin: CFTimeInterval, until end: CFTimeInterval) -> CABasicAnimation {
        fade(from: 1, to: 0, at: begin, duration: end - begin, timing: CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 1))
    }

    /// The animation keeps its end after it ends, and its start before: going out, the model values stay where they are.
    private static func hold<A: CAAnimation>(_ animation: A) -> A {
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// A critically damped spring of `response` seconds that lands exactly at `duration`: the spring's curve, scaled so its
    /// last hundredth of a percent does not run on past the end, where the window turns opaque.
    private static func settle(_ keyPath: String, from: CATransform3D, to: CATransform3D, at begin: CFTimeInterval, response: Double,
                               duration: CFTimeInterval) -> CAKeyframeAnimation {
        let omega = 2 * Double.pi / response, steps = 60
        let end = 1 - (1 + omega * duration) * exp(-omega * duration)
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = (0...steps).map { step in
            let t = duration * Double(step) / Double(steps)
            let f = CGFloat((1 - (1 + omega * t) * exp(-omega * t)) / end)
            return mix(from, to, f)
        }
        animation.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        animation.beginTime = begin
        animation.duration = duration
        animation.fillMode = .backwards
        return animation
    }

    private static func mix(_ a: CATransform3D, _ b: CATransform3D, _ f: CGFloat) -> CATransform3D {
        func m(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * f }
        return CATransform3D(m11: m(a.m11, b.m11), m12: m(a.m12, b.m12), m13: m(a.m13, b.m13), m14: m(a.m14, b.m14),
                             m21: m(a.m21, b.m21), m22: m(a.m22, b.m22), m23: m(a.m23, b.m23), m24: m(a.m24, b.m24),
                             m31: m(a.m31, b.m31), m32: m(a.m32, b.m32), m33: m(a.m33, b.m33), m34: m(a.m34, b.m34),
                             m41: m(a.m41, b.m41), m42: m(a.m42, b.m42), m43: m(a.m43, b.m43), m44: m(a.m44, b.m44))
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

/// A shield's content with lock_animation on: the backdrop under the scene, and the light some styles draw over it. In
/// the preview, a stand-in desktop under all of them. Its background is black at 1/255, which nobody sees: no pixel of
/// the window is clear, so no click passes through it while the lock comes in.
final class TransitionStage: NSView {
    let scene: LockScreenView
    let backdrop: NSView
    /// Sweep's sheen and Dissolve's rim. Hidden except while they show.
    let light = LightView()
    /// Dissolve's or Tiles' shader, while it runs.
    var shader: TransitionMask?

    init(frame: CGRect, scene: LockScreenView, backdrop: NSView, desktop: NSView? = nil) {
        self.scene = scene
        self.backdrop = backdrop
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(1 / 255).cgColor
        light.wantsLayer = true
        light.isHidden = true
        for view in [desktop, backdrop, scene, light].compactMap({ $0 }) {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Light only: clicks go to the scene under it.
    final class LightView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The preview's and `render`'s desktop: a few windows on a neutral gradient, and the same picture blurred as the backdrop
/// shows a desktop. A real desktop shows only through a lock's own window. Settings' preview puts two windows on the
/// user's own desktop picture.
enum StandInDesktop {
    static func picture(size: CGSize, scale: CGFloat, wallpaper: CGImage? = nil) -> CGImage? {
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
        if let wallpaper {
            // Filling the screen, as the desktop shows it.
            let fill = max(size.width / CGFloat(wallpaper.width), size.height / CGFloat(wallpaper.height))
            let drawn = CGSize(width: CGFloat(wallpaper.width) * fill, height: CGFloat(wallpaper.height) * fill)
            context.interpolationQuality = .high
            context.draw(wallpaper, in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
        } else if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        }
        context.setFillColor(CGColor(gray: 1, alpha: 0.35))
        context.fill(rect(0, 0, 1, 0.027))
        let windows = wallpaper == nil ? [rect(0.06, 0.12, 0.42, 0.5), rect(0.4, 0.3, 0.5, 0.55), rect(0.12, 0.66, 0.26, 0.26)]
            : [rect(0.08, 0.14, 0.44, 0.52), rect(0.42, 0.34, 0.48, 0.5)]
        for (index, frame) in windows.enumerated() {
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
