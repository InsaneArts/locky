import AppKit
import Testing
@testable import Locky

/// `locky render`: a theme's lock screen drawn off the screen, its shader too.
@MainActor
@Suite struct RenderTests {
    /// The color of the pixel at (x, y) from the top left, as 0...255 values.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (red: Int, green: Int, blue: Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    /// A shader's frame fills the screen, the right way up: red at the top, blue at the bottom, at twice the points.
    @Test func aShaderThemeDraws() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("shaders/halves.metal", """
            float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
                return uv.y > 0.5 ? float4(1, 0, 0, 1) : float4(0, 0, 1, 1);
            }
            """)
        try sandbox.write("themes/halves.lua", """
            return { name = "Halves", background = { shader = "halves" }, widgets = {} }
            """)
        let image = try await Render.image(theme: "halves", size: CGSize(width: 400, height: 250), appearance: nil, config: sandbox.config)
        #expect(image.width == 800 && image.height == 500)
        let top = pixel(image, 20, 20), bottom = pixel(image, 20, 480)
        #expect(top.red > 200 && top.blue < 50, "top: \(top)")
        #expect(bottom.blue > 200 && bottom.red < 50, "bottom: \(bottom)")
    }

    /// A shader color that is no palette role and no hex (a typo, or a role the theme does not define) draws black,
    /// as a missing color does: it must not crash the lock.
    @Test func aShaderColorThatIsNoColorDrawsBlack() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("shaders/first.metal", """
            float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) { return float4(locky_color(p, 1), 1); }
            """)
        try sandbox.write("themes/typo.lua", """
            return { name = "Typo", palette = { bg = "#ffffff" }, background = { shader = "first", colors = { "bg", "accent2" } }, widgets = {} }
            """)
        let image = try await Render.image(theme: "typo", size: CGSize(width: 200, height: 120), appearance: nil, config: sandbox.config)
        // A corner: at this size the password field covers the middle.
        let corner = pixel(image, 10, 10)
        #expect(corner.red < 20 && corner.green < 20 && corner.blue < 20, "corner: \(corner)")
    }

    @Test func anUnknownThemeFails() async throws {
        let sandbox = try Sandbox()
        await #expect(throws: Render.Failure.self) {
            try await Render.image(theme: "nothing-by-this-name", size: CGSize(width: 200, height: 120), appearance: nil, config: sandbox.config)
        }
    }

    /// --widget: that widget alone, in the middle of the theme; a widget nobody defined fails.
    @Test func aWidgetDrawsAloneInTheMiddle() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/square.lua", """
            locky.widget.define("square", { render = function() return locky.ui.rect({ width = 40, height = 40, color = "#00ff00" }) end })
            """)
        try sandbox.write("themes/plain.lua", """
            return { name = "Plain", background = { color = "#000000" }, widgets = { { "square", anchor = "top-left" } } }
            """)
        let image = try await Render.image(theme: "plain", widget: "square", size: CGSize(width: 400, height: 250), appearance: nil, config: sandbox.config)
        let middle = pixel(image, 400, 250), corner = pixel(image, 20, 20)
        #expect(middle.green > 200 && middle.red < 50, "middle: \(middle)")
        #expect(corner.green < 50, "the theme's own placement is gone: \(corner)")
        await #expect(throws: Render.Failure.self) {
            try await Render.image(theme: "plain", widget: "circle", size: CGSize(width: 200, height: 120), appearance: nil, config: sandbox.config)
        }
    }

    /// A widget that draws nothing until its data comes (network, processes, weather) is drawn with it, not blank.
    @Test func aWidgetWaitingForDataDrawsOnceItComes() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/later.lua", """
            locky.widget.define("later", {
              init = function(self) self:after(0.4, function(self) self:set({ ready = true }) end) end,
              render = function(self)
                if not self.state.ready then return nil end
                return locky.ui.rect({ width = 40, height = 40, color = "#00ff00" })
              end,
            })
            """)
        try sandbox.write("themes/plain.lua", """
            return { name = "Plain", background = { color = "#000000" }, widgets = { { "later", anchor = "center" } } }
            """)
        let image = try await Render.image(theme: "plain", size: CGSize(width: 400, height: 250), appearance: nil, config: sandbox.config)
        let middle = pixel(image, 400, 250)
        #expect(middle.green > 200 && middle.red < 50, "middle: \(middle)")
    }
}
