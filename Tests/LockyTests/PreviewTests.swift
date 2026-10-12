import AppKit
import Foundation
import Testing
@testable import Locky

@MainActor
@Suite struct PreviewReloadTests {
    private func sandbox() throws -> Sandbox {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { background = { color = '#101010' }, widgets = { { 'w', anchor = 'top' }, { 'w', anchor = 'bottom' } } }")
        try sandbox.write("plugin/w.lua", "locky.widget.define('w', { render = function(self) return locky.ui.text(self.opts.label or 'w') end })")
        return sandbox
    }

    /// `eventually`, on the main actor, where the screen lives.
    private func wait(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        return condition()
    }

    @Test func anEditKeepsEachWidgetsViewAndTheBackgroundsView() async throws {
        let sandbox = try sandbox()
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var options = LockSession.Options(theme: "t", container: container)
        options.path = sandbox.path()
        let session = LockSession(mode: .embedded, options: options)
        session.begin()
        defer { session.end("test") }
        let screen = try #require(container.subviews.first as? LockScreenView)
        #expect(await wait { screen.widgets.count == 2 })
        let views = screen.widgets
        let background = screen.background
        let edit = Settings(["themes": .table(["t": .table([
            "widgets": .array([
                .table(["ref": .int(1), "widget": .string("w"), "anchor": .string("top-left"), "offset": .array([.int(30), .int(30)])]),
                .table(["ref": .int(2), "widget": .string("w"), "opts": .table(["label": .string("x")])]),
                .table(["widget": .string("w")]),
            ]),
            "background": .table(["color": .string("#202020")]),
            "auth": .table(["anchor": .string("top")]),
        ])])])
        #expect(await session.reload(settings: edit))
        #expect(screen.widgets.count == 3)
        // The moved widget and the one with a new option keep their views; the new one gets its own.
        #expect(screen.widgets[0] === views[0] && screen.widgets[1] === views[1] && screen.widgets[2] !== views[1])
        #expect(screen.widgets[0].placement.anchor == .topLeft && screen.widgets[0].placement.offset == CGPoint(x: 30, y: 30))
        #expect(screen.widgets[1].placement.options["label"] == .string("x"))
        // Another color goes into the same view, and the password field moves.
        #expect(screen.background === background)
        #expect(screen.auth?.spec.anchor == .top)

        // Back to the theme as it was: the added widget goes.
        #expect(await session.reload(settings: Settings()))
        #expect(screen.widgets.count == 2 && screen.widgets[0] === views[0])
        #expect(screen.widgets[0].placement.anchor == .top)
    }

    @Test func onlyTheThemesOwnChangesReloadInPlace() {
        let base = ThemePreviewView.Key(theme: "t", settings: Settings(["theme": .string("t")]), sources: 5)
        var edited = base
        edited.settings.setThemeEdit("t", "widgets", .array([]))
        #expect(!base.needsRestart(for: edited) && base.edit != edited.edit)
        var another = base
        another.settings.setThemeEdit("u", "widgets", .array([]))
        #expect(!base.needsRestart(for: another) && base.edit == another.edit)
        var privacy = base
        privacy.settings["privacy"] = .bool(true)
        #expect(base.needsRestart(for: privacy))
        var theme = base
        theme.theme = "u"
        #expect(base.needsRestart(for: theme))
        var files = base
        files.sources = 6
        #expect(base.needsRestart(for: files))
        // The first reading of the files, and settings the screen does not show, change nothing.
        var unread = base
        unread.sources = 0
        #expect(!unread.needsRestart(for: base))
        var shortcut = base
        shortcut.settings["shortcut"] = .table(["key": .int(37)])
        #expect(!base.needsRestart(for: shortcut))
    }
}
