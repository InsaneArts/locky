import AppKit
import Testing
@testable import Locky

/// settings.json's lock_animation: when the lock comes in and goes out animated, and what it animates. No test locks: the
/// windows here never show, and the pure rules stand for the lock's own choices.
@MainActor
@Suite struct LockTransitionTests {
    @Test func theSettingIsOnUnlessFalse() {
        #expect(Settings().lockAnimation)
        #expect(Settings(["lock_animation": .bool(true)]).lockAnimation)
        #expect(!Settings(["lock_animation": .bool(false)]).lockAnimation)
        // Not a bool: the default.
        #expect(Settings(["lock_animation": .string("no")]).lockAnimation)
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
        LockTransition.comeIn(backdrop: stage.backdrop, scene: stage.scene, origin: middle, at: CACurrentMediaTime(), reduceMotion: false)
        let mask = try #require(stage.scene.layer?.mask)
        #expect(mask.position == stage.scene.convertToLayer(middle))
        #expect(mask.animation(forKey: "locky.transition.iris") != nil)
        #expect(stage.scene.entrance != nil)
        // Done: no mask, no backdrop, and items show as they always do.
        LockTransition.finishComingIn(backdrop: stage.backdrop, scene: stage.scene)
        #expect(stage.scene.layer?.mask == nil && stage.backdrop.isHidden && stage.scene.entrance == nil)
    }

    /// Reduce Motion: the backdrop and the scene fade in together in 0.25 s. No iris, no item moves.
    @Test func reduceMotionFadesInWithoutTheIris() throws {
        let stage = stage()
        LockTransition.comeIn(backdrop: stage.backdrop, scene: stage.scene, origin: .zero, at: CACurrentMediaTime(), reduceMotion: true)
        #expect(stage.scene.layer?.mask == nil && stage.scene.entrance == nil)
        let fade = try #require(stage.scene.layer?.animation(forKey: "locky.transition.opacity"))
        #expect(fade.duration == 0.25)
        #expect(stage.backdrop.layer?.animation(forKey: "locky.transition.opacity")?.duration == 0.25)
        #expect(LockTransition.length(.lock, reduceMotion: true) == 0.25)
    }

    /// The way out opens from the password field's middle.
    @Test func goingOutOpensFromTheField() throws {
        let stage = stage()
        let field = CGPoint(x: 400, y: 420)
        LockTransition.goOut(backdrop: stage.backdrop, scene: stage.scene, origin: field, at: CACurrentMediaTime())
        let mask = try #require(stage.scene.layer?.mask)
        #expect(mask.position == stage.scene.convertToLayer(field))
        #expect(stage.backdrop.alphaValue == 0 && !stage.backdrop.isHidden)
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
        #expect(CLI.GUILaunch.parse(["preview", "--theme", "mocha", "--transition"]).theme == "mocha")
        #expect(!CLI.GUILaunch.parse(["preview"]).transition)
        // Only a preview: a lock never takes it.
        #expect(!CLI.GUILaunch.parse(["lock", "--transition"]).transition)
    }
}

/// `render --transition`: one frame of the way in or out, over the stand-in desktop.
@MainActor
@Suite struct TransitionRenderTests {
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (red: Int, green: Int, blue: Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    @Test func framesShowTheDesktopThenTheScene() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/red.lua", "return { name = 'Red', background = { color = '#ff0000' }, palette = { bg = '#ff0000' }, widgets = {} }")
        func frame(_ direction: LockTransition.Direction, _ progress: Double) async throws -> (red: Int, green: Int, blue: Int) {
            let image = try await Render.image(theme: "red", size: CGSize(width: 400, height: 250), appearance: nil, config: sandbox.config,
                                               transition: (direction, progress))
            #expect(image.width == 800)
            // A corner: the last place the iris reaches.
            return pixel(image, 4, 4)
        }
        let red = { (p: (red: Int, green: Int, blue: Int)) in p.red > 230 && p.green < 30 && p.blue < 30 }
        #expect(!red(try await frame(.lock, 0)))
        #expect(red(try await frame(.lock, 1)))
        #expect(red(try await frame(.unlock, 0)))
        #expect(!red(try await frame(.unlock, 1)))
    }
}
