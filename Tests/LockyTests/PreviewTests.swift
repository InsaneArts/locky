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
                // Not the same as the second widget was: an identical one would take over its instance, and its view.
                .table(["widget": .string("w"), "opts": .table(["label": .string("z")])]),
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

    /// Lua keeps the second widget's instance while the first comes back: that instance keeps its view, and the new
    /// one does not take it for being the same widget.
    @Test func aKeptInstanceKeepsItsViewWhenAWidgetComesBackBeforeIt() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { widgets = { { 'w', opts = { label = 'a' } }, { 'w', opts = { label = 'b' } } } }")
        try sandbox.write("plugin/w.lua", "locky.widget.define('w', { render = function(self) return locky.ui.text(self.opts.label) end })")
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var options = LockSession.Options(theme: "t", container: container)
        options.path = sandbox.path()
        let session = LockSession(mode: .embedded, options: options)
        session.begin()
        defer { session.end("test") }
        let screen = try #require(container.subviews.first as? LockScreenView)
        #expect(await wait { screen.widgets.count == 2 && screen.widgets[1].model.node != nil })
        let second = screen.widgets[1]
        let onlySecond = Settings(["themes": .table(["t": .table(["widgets": .array([.table(["ref": .int(2), "widget": .string("w")])])])])])
        #expect(await session.reload(settings: onlySecond))
        #expect(screen.widgets.count == 1 && screen.widgets[0] === second)
        #expect(await session.reload(settings: Settings()))
        #expect(screen.widgets.count == 2 && screen.widgets[1] === second && screen.widgets[0] !== second)
        #expect(second.model.node?.kind == .text("b"))
        #expect(await wait { screen.widgets[0].model.node?.kind == .text("a") })
    }

    /// Settings Lua leaves out, or a theme that does not load, are not what the editor edits: the screen says so.
    @Test func theScreenSaysWhenItShowsTheThemeAsEdited() async throws {
        let sandbox = try sandbox()
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var options = LockSession.Options(theme: "t", container: container)
        options.path = sandbox.path()
        let session = LockSession(mode: .embedded, options: options)
        session.begin()
        defer { session.end("test") }
        #expect(await wait { session.shows(theme: "t") })
        let bad = Settings(["themes": .table(["t": .table(["widgets": .array([.table(["widget": .string("w"), "anchor": .string("middle")])])])])])
        #expect(await session.reload(settings: bad))
        #expect(!session.shows(theme: "t"))
        #expect(await session.reload(settings: Settings()))
        #expect(session.shows(theme: "t"))

        try sandbox.write("themes/broken.lua", "return { background = { shader = 'nowhere' } }")
        let other = NSView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var fallback = LockSession.Options(theme: "broken", container: other)
        fallback.path = sandbox.path()
        let shown = LockSession(mode: .embedded, options: fallback)
        shown.begin()
        defer { shown.end("test") }
        #expect(await wait { (other.subviews.first as? LockScreenView)?.background != nil })
        #expect(!shown.shows(theme: "broken"))
    }

    /// A background picked while another still loads: the one picked last stays, whichever loads first.
    @Test func theLastBackgroundPickedStays() async throws {
        final class Slow: NSView, BackgroundLoading { var isLoaded = false }
        let screen = LockScreenView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let first = NSView(), slow = Slow(), last = NSView()
        screen.background = first
        screen.replaceBackground(with: slow)
        #expect(screen.latestBackground === slow)
        screen.replaceBackground(with: last)
        #expect(screen.latestBackground === last && slow.superview == nil)
        #expect(await wait { screen.background === last })
        slow.isLoaded = true
        try await Task.sleep(for: .milliseconds(500))
        #expect(screen.background === last && first.superview == nil)
    }

    /// A config folder in a dotfiles repo, linked into place: its files count, and a change to one shows.
    @Test func theFingerprintFollowsSymlinks() throws {
        let sandbox = try Sandbox()
        let real = sandbox.root.appending(path: "dotfiles/locky")
        try FileManager.default.createDirectory(at: real.appending(path: "plugin"), withIntermediateDirectories: true)
        try "print(1)".write(to: real.appending(path: "init.lua"), atomically: true, encoding: .utf8)
        let linked = sandbox.root.appending(path: "linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: real)
        let path = RuntimePath(config: linked, packs: sandbox.packs, roots: [linked])
        let before = path.fingerprint()
        #expect(path.fingerprint() == before)
        try "print(2) -- and more".write(to: real.appending(path: "init.lua"), atomically: true, encoding: .utf8)
        let after = path.fingerprint()
        #expect(after != before)
        // settings.json does not count: the window writes it on every change.
        try "{}".write(to: real.appending(path: "settings.json"), atomically: true, encoding: .utf8)
        #expect(path.fingerprint() == after)
    }

    /// A widget placed where the password field is (a dialog drawn around it) stays under it.
    @Test func widgetsStayUnderThePasswordField() {
        let screen = LockScreenView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let field = NSView()
        screen.auth = (field, Theme.Auth())
        let placement = Theme.Placement(widget: "w", anchor: .center, offset: .zero, size: nil, align: nil, card: nil, allDisplays: false, known: true)
        let widget = WidgetHost(placement: placement, theme: .fallback, style: LockyStyle(), showsErrors: true)
        screen.add(widget)
        let order = screen.subviews
        #expect((order.firstIndex(of: widget) ?? 99) < (order.firstIndex(of: field) ?? -1))
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
        // Touch ID's status line, as the Welcome's unlock line follows it.
        var touchID = base
        touchID.settings["touch_id"] = .bool(false)
        #expect(base.needsRestart(for: touchID))
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
