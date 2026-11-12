import AppKit
import Metal
import Testing
@testable import Locky

/// settings.json's lock_animation: when the lock comes in and goes out animated, and what it animates. No test locks: the
/// windows here never show, and the pure rules stand for the lock's own choices.
@MainActor
@Suite struct LockTransitionTests {
    /// A style's name, or none. An older Locky's true is Focus and its false none; anything else is Focus.
    @Test func theSettingNamesAStyle() {
        #expect(Settings().lockAnimation == .focus)
        for style in LockTransition.Style.allCases {
            #expect(Settings(["lock_animation": .string(style.rawValue)]).lockAnimation == style)
        }
        #expect(Settings(["lock_animation": .string("none")]).lockAnimation == nil)
        #expect(Settings(["lock_animation": .bool(true)]).lockAnimation == .focus)
        #expect(Settings(["lock_animation": .bool(false)]).lockAnimation == nil)
        #expect(Settings(["lock_animation": .string("swirl")]).lockAnimation == .focus)
        #expect(Settings(["lock_animation": .int(1)]).lockAnimation == .focus)
        // Focus, the default, stores no key; none stores "none".
        var settings = Settings(["lock_animation": .bool(false)])
        settings.lockAnimation = .focus
        #expect(settings["lock_animation"] == .nil)
        settings.lockAnimation = nil
        #expect(settings["lock_animation"] == .string("none"))
        settings.lockAnimation = .tiles
        #expect(settings["lock_animation"] == .string("tiles"))
    }

    /// Reduce Motion: every style fades, in a quarter second coming in.
    @Test(arguments: LockTransition.Style.allCases)
    func reduceMotionFadesEveryStyle(_ style: LockTransition.Style) {
        #expect(LockTransition.length(.lock, style: style, reduceMotion: true) == 0.25)
        // Each way in takes 0.5 to 0.75 s, and the way out no longer.
        let lock = LockTransition.length(.lock, style: style), unlock = LockTransition.length(.unlock, style: style)
        #expect((0.5...0.75).contains(lock) && unlock <= lock)
    }

    /// Lock Now and inactivity animate with the display awake; a sleep, the screen saver, or a sleeping display cover at once.
    @Test func onlyLockNowAndInactivityAnimate() {
        #expect(LockTransition.animatesLock(.user, setting: true, displayAsleep: false))
        #expect(LockTransition.animatesLock(.idle, setting: true, displayAsleep: false))
        for trigger in [LockTransition.Trigger.displaySleep, .screenSaver, .systemSleep] {
            #expect(!LockTransition.animatesLock(trigger, setting: true, displayAsleep: false))
        }
        #expect(!LockTransition.animatesLock(.user, setting: true, displayAsleep: true))
        #expect(!LockTransition.animatesLock(.user, setting: false, displayAsleep: false))
        // AutoLock's reasons; one it does not know never animates.
        #expect(LockTransition.Trigger(autoLock: "idle") == .idle)
        #expect(LockTransition.Trigger(autoLock: "display sleep") == .displaySleep)
        #expect(LockTransition.Trigger(autoLock: "screen saver") == .screenSaver)
        #expect(LockTransition.Trigger(autoLock: "system sleep") == .systemSleep)
        #expect(LockTransition.Trigger(autoLock: "lid") == .systemSleep)
    }

    /// Only a correct password or Touch ID goes out animated: not a hand-over, another end, a lock still coming in, or
    /// Reduce Motion, which fade as before.
    @Test func onlyAnUnlockGoesOutAnimated() {
        #expect(LockTransition.animatesUnlock(unlocked: true, setting: true, handingOver: false, comingIn: false, reduceMotion: false))
        #expect(!LockTransition.animatesUnlock(unlocked: false, setting: true, handingOver: false, comingIn: false, reduceMotion: false))
        #expect(!LockTransition.animatesUnlock(unlocked: true, setting: true, handingOver: true, comingIn: false, reduceMotion: false))
        #expect(!LockTransition.animatesUnlock(unlocked: true, setting: false, handingOver: false, comingIn: false, reduceMotion: false))
        #expect(!LockTransition.animatesUnlock(unlocked: true, setting: true, handingOver: false, comingIn: true, reduceMotion: false))
        #expect(!LockTransition.animatesUnlock(unlocked: true, setting: true, handingOver: false, comingIn: false, reduceMotion: true))
    }

    private func window() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    /// Off: the scene alone, in an opaque window, as before. On: the backdrop under the scene, hidden while the window is
    /// opaque; coming in, a clear window that still takes the clicks.
    @Test func theShieldIsOpaqueUnlessItComesIn() throws {
        let off = window(), offScene = LockScreenView()
        LockSession.prepare(off, scene: offScene, transitions: false, comingIn: false, reduceTransparency: false)
        #expect(off.contentView === offScene && off.isOpaque)

        let still = window(), stillScene = LockScreenView()
        LockSession.prepare(still, scene: stillScene, transitions: true, comingIn: false, reduceTransparency: false)
        let stage = try #require(still.contentView as? TransitionStage)
        #expect(stage.scene === stillScene && stage.backdrop.isHidden && still.isOpaque)
        #expect(stage.backdrop is NSVisualEffectView)

        let coming = window()
        LockSession.prepare(coming, scene: LockScreenView(), transitions: true, comingIn: true, reduceTransparency: true)
        let comingStage = try #require(coming.contentView as? TransitionStage)
        #expect(!coming.isOpaque && coming.backgroundColor == .clear && !coming.ignoresMouseEvents)
        #expect(!comingStage.backdrop.isHidden)
        // Reduce Transparency: a dim, no blur.
        #expect(!(comingStage.backdrop is NSVisualEffectView))
        // No clear pixel: the stage's background is never fully transparent.
        #expect((comingStage.layer?.backgroundColor?.alpha ?? 0) > 0)
    }

    private func stage() -> TransitionStage {
        let scene = LockScreenView()
        return TransitionStage(frame: CGRect(x: 0, y: 0, width: 800, height: 500), scene: scene, backdrop: LockTransition.backdrop(reduceTransparency: true))
    }

    @Test func comingInOpensAnIrisFromTheMiddle() throws {
        let stage = stage()
        let middle = CGPoint(x: 400, y: 250)
        LockTransition.comeIn(stage, style: .iris, origin: middle, at: CACurrentMediaTime(), reduceMotion: false)
        let mask = try #require(stage.scene.layer?.mask)
        #expect(mask.position == stage.scene.convertToLayer(middle))
        #expect(mask.animation(forKey: "locky.transition.iris") != nil)
        #expect(stage.scene.entrance != nil)
        // Done: no mask, no backdrop, and items show as they always do.
        LockTransition.finishComingIn(stage)
        #expect(stage.scene.layer?.mask == nil && stage.backdrop.isHidden && stage.scene.entrance == nil)
    }

    /// Reduce Motion: the backdrop and the scene fade in together in 0.25 s, whatever the style. No mask, no item moves.
    @Test(arguments: LockTransition.Style.allCases)
    func reduceMotionFadesIn(_ style: LockTransition.Style) throws {
        let stage = stage()
        LockTransition.comeIn(stage, style: style, origin: .zero, at: CACurrentMediaTime(), reduceMotion: true)
        #expect(stage.scene.layer?.mask == nil && stage.scene.entrance == nil && stage.shader == nil)
        #expect(stage.scene.layer?.animation(forKey: "locky.transition.transform") == nil)
        let fade = try #require(stage.scene.layer?.animation(forKey: "locky.transition.opacity"))
        #expect(fade.duration == 0.25)
        #expect(stage.backdrop.layer?.animation(forKey: "locky.transition.opacity")?.duration == 0.25)
    }

    /// The way out opens from the password field's middle.
    @Test func goingOutOpensFromTheField() throws {
        let stage = stage()
        let field = CGPoint(x: 400, y: 420)
        LockTransition.goOut(stage, style: .iris, origin: field, at: CACurrentMediaTime())
        let mask = try #require(stage.scene.layer?.mask)
        #expect(mask.position == stage.scene.convertToLayer(field))
        #expect(stage.backdrop.alphaValue == 0 && !stage.backdrop.isHidden)
    }

    /// Dissolve's and Tiles' shader draws only during the transition: the way in's end stops it and takes the mask and
    /// the light away, and the way out's shader stops by itself when its time is up.
    @Test(arguments: [LockTransition.Style.dissolve, .tiles])
    func theShaderStopsWithTheTransition(_ style: LockTransition.Style) throws {
        try #require(MTLCreateSystemDefaultDevice() != nil)
        let stage = stage()
        let start = CACurrentMediaTime()
        LockTransition.comeIn(stage, style: style, origin: CGPoint(x: 400, y: 250), at: start, reduceMotion: false)
        let shader = try #require(stage.shader)
        #expect(shader.isRunning && stage.scene.layer?.mask === shader.layer)
        LockTransition.finishComingIn(stage)
        #expect(!shader.isRunning && stage.shader == nil && stage.scene.layer?.mask == nil)
        #expect(stage.light.isHidden && (stage.light.layer?.sublayers ?? []).isEmpty)

        LockTransition.goOut(stage, style: style, origin: CGPoint(x: 400, y: 420), at: start)
        let out = try #require(stage.shader)
        #expect(out.isRunning)
        out.step(at: start + LockTransition.length(.unlock, style: style) - 0.1)
        #expect(out.isRunning)
        out.step(at: start + LockTransition.length(.unlock, style: style) + 0.01)
        #expect(!out.isRunning)
    }

    /// Each style's model values are the covering state: with every animation gone, as if the way in stalled, the scene
    /// covers the whole stage.
    @Test(arguments: LockTransition.Style.allCases)
    func aStalledWayInStillCovers(_ style: LockTransition.Style) throws {
        let stage = stage()
        // In a window, as `render` draws: the views' layers join the tree there.
        let window = window()
        window.contentView = stage
        stage.scene.layer?.backgroundColor = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        LockTransition.comeIn(stage, style: style, origin: CGPoint(x: 400, y: 250), at: CACurrentMediaTime(), reduceMotion: false)
        stage.shader?.stop()
        func strip(_ layer: CALayer) {
            layer.removeAllAnimations()
            layer.mask.map(strip)
            layer.sublayers?.forEach(strip)
        }
        func strip(_ view: NSView) {
            view.layer.map(strip)
            view.subviews.forEach(strip)
        }
        strip(stage)
        let root = try #require(stage.layer)
        let image = try #require(Render.draw(root, size: stage.bounds.size, at: CACurrentMediaTime()))
        for (x, y) in [(2, 2), (image.width - 3, 2), (image.width / 2, image.height / 2), (2, image.height - 3), (image.width - 3, image.height - 3)] {
            let p = pixel(image, x, y)
            #expect(p.red > 240 && p.green < 15 && p.blue < 15, "\(style) at \(x), \(y): \(p)")
        }
    }

    /// At full size the iris's opaque core passes the farthest corner, from the middle and from a field near the bottom.
    @Test func theIrisCoversTheFarthestCorner() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for origin in [CGPoint(x: 720, y: 450), CGPoint(x: 720, y: 820), CGPoint(x: -500, y: 300)] {
            let iris = LockTransition.iris(from: origin, in: bounds)
            #expect(iris.center == origin)
            let farthest = [CGPoint(x: 0, y: 0), CGPoint(x: 1440, y: 0), CGPoint(x: 0, y: 900), CGPoint(x: 1440, y: 900)]
                .map { hypot($0.x - origin.x, $0.y - origin.y) }.max()!
            #expect(iris.inner >= farthest && iris.outer > iris.inner)
            // The spring need not settle: at 91 % the core covers the screen.
            #expect(iris.inner * 0.91 >= farthest)
        }
    }

    @Test func thePreviewFlagParses() {
        #expect(CLI.GUILaunch.parse(["preview", "--transition"]).transition)
        #expect(CLI.GUILaunch.parse(["preview", "--transition"]).transitionStyle == nil)
        #expect(CLI.GUILaunch.parse(["preview", "--transition", "sweep"]).transitionStyle == .sweep)
        #expect(CLI.GUILaunch.parse(["preview", "--transition", "--theme", "mocha"]).transitionStyle == nil)
        #expect(CLI.GUILaunch.parse(["preview", "--theme", "mocha", "--transition"]).theme == "mocha")
        #expect(!CLI.GUILaunch.parse(["preview"]).transition)
        // Only a preview: a lock never takes it.
        #expect(!CLI.GUILaunch.parse(["lock", "--transition"]).transition)
    }
}

/// A pixel of `image`, from the top left.
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (red: Int, green: Int, blue: Int) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
}

/// `render --transition`: one frame of the way in or out, over the stand-in desktop.
@MainActor
@Suite struct TransitionRenderTests {
    /// In every style, the desktop shows before the way in and after the way out, and the scene covers the screen after
    /// the way in and before the way out.
    @Test(arguments: LockTransition.Style.allCases)
    func framesShowTheDesktopThenTheScene(_ style: LockTransition.Style) async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/red.lua", "return { name = 'Red', background = { color = '#ff0000' }, palette = { bg = '#ff0000' }, widgets = {} }")
        func frame(_ direction: LockTransition.Direction, _ progress: Double) async throws -> [(red: Int, green: Int, blue: Int)] {
            let image = try await Render.image(theme: "red", size: CGSize(width: 400, height: 250), appearance: nil, config: sandbox.config,
                                               transition: (direction, progress), style: style)
            #expect(image.width == 800)
            // The corners, the last places most styles reach, and the top middle, away from the password field.
            return [(4, 4), (795, 4), (4, 495), (795, 495), (400, 60)].map { pixel(image, $0.0, $0.1) }
        }
        let red = { (p: (red: Int, green: Int, blue: Int)) in p.red > 230 && p.green < 30 && p.blue < 30 }
        #expect(try await frame(.lock, 0).allSatisfy { !red($0) })
        #expect(try await frame(.lock, 1).allSatisfy(red))
        #expect(try await frame(.unlock, 0).allSatisfy(red))
        #expect(try await frame(.unlock, 1).allSatisfy { !red($0) })
    }
}

/// Hiding the Dock and the menu bar as a lock starts reports new screen parameters with the same displays: the
/// shields stay, and so does their way in. Another display, or one that moved or changed size, gets new shields.
@Suite struct DisplayChangeTests {
    private let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let external = CGRect(x: 1728, y: 0, width: 2560, height: 1440)

    @Test func theSameDisplaysKeepTheirShields() {
        #expect(!LockSession.displaysChanged(windows: [laptop, external], screens: [laptop, external]))
    }

    @Test func anotherDisplayOrAMovedOneGetsNewShields() {
        #expect(LockSession.displaysChanged(windows: [laptop], screens: [laptop, external]))
        #expect(LockSession.displaysChanged(windows: [laptop, external], screens: [laptop]))
        #expect(LockSession.displaysChanged(windows: [laptop], screens: [CGRect(x: 0, y: 0, width: 1512, height: 982)]))
        #expect(LockSession.displaysChanged(windows: [laptop, external], screens: [external, laptop]))
    }
}

/// Settings' preview of the lock animation plays only in the key window while it shows, and never with Reduce Motion.
@MainActor
@Suite struct TransitionPreviewTests {
    @Test func itPlaysOnlyInTheKeyWindow() {
        #expect(TransitionPreviewView.plays(isKey: true, visible: true, reduceMotion: false))
        #expect(!TransitionPreviewView.plays(isKey: false, visible: true, reduceMotion: false))
        #expect(!TransitionPreviewView.plays(isKey: true, visible: false, reduceMotion: false))
        #expect(!TransitionPreviewView.plays(isKey: true, visible: true, reduceMotion: true))
    }

    /// Out of a window, or in one that is not key, no screen runs: nothing loads Lua or draws.
    @Test func itRunsNothingOutOfTheKeyWindow() throws {
        let sandbox = try Sandbox()
        let view = TransitionPreviewView(frame: CGRect(x: 0, y: 0, width: 260, height: 162.5))
        let key = TransitionPreviewView.Key(theme: "default", settings: Settings(), config: sandbox.config)
        view.show(key, settings: Settings())
        #expect(!view.isRunning)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = view
        view.show(key, settings: Settings())
        #expect(!window.isKeyWindow && !view.isRunning)
        view.stop()
        #expect(!view.isRunning)
    }
}
