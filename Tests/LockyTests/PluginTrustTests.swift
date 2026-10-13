import Foundation
import Testing
@testable import Locky

/// What a plugin may change once init.lua has run, and what it may do without the user's grant.
@Suite struct PluginTrustTests {
    private func runtime(_ sandbox: Sandbox) -> LuaRuntime {
        LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
    }

    private func config(_ runtime: LuaRuntime) throws -> LuaValue {
        try runtime.sync { try runtime.call("config", budget: 1) }.first ?? .nil
    }

    // MARK: locky.config

    @Test func initLuaStillSetsOptions() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ privacy = true }) locky.config.message = 'hi'")
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        #expect(try config(runtime)["privacy"] == .bool(true))
        #expect(try config(runtime)["message"] == .string("hi"))
    }

    /// A plugin script turning privacy off would show the names the user hid.
    @Test func pluginScriptsCannotChangeTheConfig() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ privacy = true, widgets = { clock = { format = 'HH:mm' } } })")
        try sandbox.write("plugin/a.lua", "locky.config.privacy = false")
        try sandbox.write("plugin/b.lua", "locky.setup({ privacy = false })")
        try sandbox.write("plugin/c.lua", "locky.config = { privacy = false }")
        try sandbox.write("plugin/d.lua", "rawset(locky, 'config', { privacy = false })")
        try sandbox.write("plugin/e.lua", "locky.config.widgets.clock.format = 'h'")
        let runtime = runtime(sandbox)
        let problems = runtime.bootForTest()
        #expect(problems.count == 5, "\(problems)")
        for (file, line) in zip(["a", "b", "c", "d", "e"], problems) {
            #expect(line.contains("plugin/\(file).lua:1: locky.config is read-only once init.lua has run: set options in init.lua"), "\(line)")
        }
        #expect(try config(runtime)["privacy"] == .bool(true))
        #expect(try runtime.eval("return locky.sys.user().name, locky.config.widgets.clock.format") == [.string("user"), .string("HH:mm")])
    }

    @Test func theConfigStillReadsLikeATable() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ palette = { accent = '#ff0000' }, widgets = { x = { list = { 1, 2, 3 } } } })")
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        #expect(try runtime.eval("""
            local keys = {}
            for k in pairs(locky.config.palette) do keys[#keys + 1] = k end
            local list = locky.config.widgets.x.list
            return #keys, next(locky.config.palette), #list, list[3], locky.tbl.islist(list), locky.tbl.deep_extend('force', {}, locky.config).palette.accent
            """) == [.int(1), .string("accent"), .int(3), .int(3), .bool(true), .string("#ff0000")])
    }

    /// settings.json still applies after init.lua, so the window's values keep winning.
    @Test func settingsJsonStillApplies() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ theme = 'from-init' })")
        try Settings(["theme": .string("from-settings")]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        #expect(try config(runtime)["theme"] == .string("from-settings"))
    }

    /// Built-in widgets and themes read the config and never write it: every built-in theme loads without a problem.
    @Test func builtInThemesNeverWriteTheConfig() async throws {
        let sandbox = try Sandbox()
        let runtime = LuaRuntime(path: sandbox.path(packages: true), delegate: Recorder().delegate)
        #expect(runtime.bootForTest().isEmpty)
        let names = try runtime.sync { try runtime.call("theme_names", budget: 1) }.first?.array?.compactMap(\.string) ?? []
        #expect(names.count > 10)
        for name in names {
            let theme = LuaRuntime(path: sandbox.path(packages: true), delegate: Recorder().delegate)
            let started = await theme.start(theme: name)
            theme.stop()
            #expect(!started.problems.contains { $0.contains("read-only") }, "\(name): \(started.problems)")
        }
    }
}
