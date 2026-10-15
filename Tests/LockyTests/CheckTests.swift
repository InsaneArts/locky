import Foundation
import Testing
@testable import Locky

/// `locky check --widget`: the widget alone in a theme, so its init and render run even when no theme places it.
@Suite struct CheckTests {
    @Test func aWidgetNoThemePlacesIsChecked() throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/broken.lua", """
            locky.widget.define("broken", { render = function() error("no data") end })
            """)
        try sandbox.write("plugin/fine.lua", """
            locky.widget.define("fine", { render = function() return locky.ui.text("hi") end })
            """)
        let fine = CLI.checkReport(theme: nil, widget: "fine", config: sandbox.config)
        #expect(fine.ok, "\(fine.text)")
        #expect(fine.text.contains("fine: ok") && !fine.text.contains("clock:"))
        let broken = CLI.checkReport(theme: nil, widget: "broken", config: sandbox.config)
        #expect(!broken.ok)
        #expect(broken.text.contains("broken: FAILED") && broken.text.contains("no data"), "\(broken.text)")
    }
}
