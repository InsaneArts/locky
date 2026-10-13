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

    // MARK: Grants

    /// A third-party plugin "evil": a folder in the pack folder holding `files`, added by init.lua with `allow`.
    private func thirdParty(_ files: [String: String], allow: String = "", in sandbox: Sandbox) throws {
        for (relative, text) in files {
            let url = sandbox.packs.appending(path: "evil/\(relative)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let grant = allow.isEmpty ? "" : ", allow = { \(allow) }"
        try sandbox.write("init.lua", "locky.pack.add({ { src = 'https://example.com/evil.git', name = 'evil'\(grant) } })")
    }

    private func target(_ sandbox: Sandbox) -> String { sandbox.root.appending(path: "target.txt").path }

    @Test func aPluginNeedsAGrantToRunPrograms() throws {
        let sandbox = try Sandbox()
        try thirdParty(["plugin/evil.lua": "locky.system({ 'true' })"], in: sandbox)
        let problems = runtime(sandbox).bootForTest()
        #expect(problems.count == 1)
        #expect(problems.first?.contains("""
            plugin/evil.lua:1: locky.system: plugin "evil" may not run programs. To allow it, turn on Run programs for it on \
            the Plugins page, or add allow = { "system" } to its locky.pack.add entry in init.lua
            """) == true, "\(problems)")

        try thirdParty(["plugin/evil.lua": "locky.system({ 'true' })"], allow: "'system'", in: sandbox)
        #expect(runtime(sandbox).bootForTest().isEmpty)
    }

    @Test func aPluginNeedsAGrantToChangeFiles() throws {
        let sandbox = try Sandbox()
        let path = target(sandbox)
        try "x".write(toFile: path, atomically: true, encoding: .utf8)
        try thirdParty(["lua/evil.lua": """
            return {
              read = function(p) local f = io.open(p) local text = f:read("a") f:close() return text end,
              write = function(p) return io.open(p, "w") end,
              append = function(p) return io.open(p, "a+") end,
              remove = function(p) return os.remove(p) end,
              rename = function(p) return os.rename(p, p .. ".moved") end,
              tmpname = function() return os.tmpname() end,
              output = function(p) return io.output(p) end,
            }
            """], in: sandbox)
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        // Reading stays open to every plugin.
        #expect(try runtime.eval("return require('evil').read('\(path)')") == [.string("x")])
        for call in ["write", "append", "remove", "rename", "tmpname", "output"] {
            let result = try runtime.eval("return pcall(require('evil').\(call), '\(path)')")
            #expect(result.first == .bool(false), "\(call)")
            #expect(result.last?.string?.contains("plugin \"evil\" may not change files") == true, "\(call): \(result)")
        }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "x")

        try thirdParty(["lua/evil.lua": "return { write = function(p) local f = io.open(p, 'w') f:write('y') f:close() end }"],
                       allow: "'files'", in: sandbox)
        let granted = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        #expect(granted.bootForTest().isEmpty)
        _ = try granted.eval("require('evil').write('\(path)')")
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "y")
    }

    /// settings.json's packages (the Plugins page) grant the same way.
    @Test func settingsJsonGrants() throws {
        let sandbox = try Sandbox()
        try thirdParty(["plugin/evil.lua": "locky.system({ 'true' })"], in: sandbox)
        try sandbox.write("init.lua", "")
        try Settings(["packs": .array([.table(["src": .string("https://example.com/evil.git"), "name": .string("evil"),
                                               "allow": .array([.string("system")])])])]).save(config: sandbox.config)
        #expect(runtime(sandbox).bootForTest().isEmpty)
        try Settings(["packs": .array([.table(["src": .string("https://example.com/evil.git"), "allow": .array([.string("root")])])])])
            .save(config: sandbox.config)
        #expect(runtime(sandbox).bootForTest().first?.contains("spec.allow: expected \"system\" or \"files\", got root") == true)
    }

    /// Ways to leave the plugin's own frame off the stack: a tail call, a coroutine, a callback, and code loaded from
    /// a string, under a file name of the user's.
    @Test func aPluginCannotHideFromTheStack() async throws {
        let sandbox = try Sandbox()
        let path = target(sandbox)
        let config = sandbox.config.appending(path: "init.lua").path
        try thirdParty(["lua/evil.lua": """
            return {
              tail = function(p) return io.open(p, "w") end,
              coroutine = function(p) return coroutine.wrap(io.open)(p, "w") end,
              nested = function(p) return coroutine.wrap(function() return coroutine.wrap(io.open)(p, "w") end)() end,
              loaded = function(p) return load("return io.open(...)", "@\(config)")(p, "w") end,
              later = function(p) locky.defer(function() return io.open(p, "w") end) end,
            }
            """], in: sandbox)
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        for call in ["tail", "coroutine", "nested", "loaded"] {
            let result = try runtime.eval("local ok, e = pcall(require('evil').\(call), '\(path)') return ok, tostring(e)")
            #expect(result.first == .bool(false), "\(call): \(result)")
            #expect(result.last?.string?.contains("may not change files") == true, "\(call): \(result)")
        }
        _ = try runtime.eval("require('evil').later('\(path)')")
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: path))
        // Code the user loads from a string is not trusted either.
        #expect(try runtime.eval("return pcall(load('return os.remove(...)'), '\(path)')").first == .bool(false))
        runtime.stop()
    }

    @Test func aPluginCannotAddPluginsOrGrantItself() throws {
        let sandbox = try Sandbox()
        try thirdParty(["lua/evil.lua": "locky.pack.add({ { dir = '/tmp/x', allow = { 'system' } } }) return {}"], in: sandbox)
        try sandbox.write("init.lua", "locky.pack.add({ { src = 'https://example.com/evil.git', name = 'evil' } }) require('evil')")
        let problems = runtime(sandbox).bootForTest()
        #expect(problems.first?.contains("locky.pack.add: only init.lua and your own config may add plugins") == true, "\(problems)")
    }

    /// The user's config folder and Locky's own code need no grant: the weather widget writes its cache, git runs.
    @Test func yourOwnCodeNeedsNoGrant() throws {
        let sandbox = try Sandbox()
        let path = target(sandbox)
        try sandbox.write("plugin/mine.lua", "local f = io.open('\(path)', 'w') f:write('mine') f:close() locky.system({ 'true' })")
        #expect(runtime(sandbox).bootForTest().isEmpty)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "mine")
    }

    @Test func pluginFolderIsFoundByItsRealPath() throws {
        let sandbox = try Sandbox()
        let packs = sandbox.packs
        #expect(LuaRuntime.plugin(of: packs.appending(path: "evil/plugin/x.lua").path, packs: packs) == "evil")
        #expect(LuaRuntime.plugin(of: sandbox.config.appending(path: "../packs/evil/x.lua").path, packs: packs) == "evil")
        #expect(LuaRuntime.plugin(of: sandbox.config.appending(path: "init.lua").path, packs: packs) == nil)
        #expect(LuaRuntime.plugin(of: "eval", packs: packs) == nil)
    }

    @Test func checkAndHealthListGrants() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.pack.add({ { src = 'https://example.com/a.git', allow = { 'system' } }, 'b/c', { dir = '~/code/mine' } })")
        let specs = PackManager(path: sandbox.path()).specs().specs
        #expect(specs.map(\.grants) == ["may run programs, may not change files", "may not run programs, may not change files", "your own folder, no limits"])
    }

    /// The Plugins page's checkboxes write the plugin's settings.json entry.
    @Test func togglesWriteTheSettingsEntry() {
        let granted = PackSpec.allowing("system", true, in: .string("a/b"))
        #expect(granted == .table(["src": .string("a/b"), "allow": .array([.string("system")])]))
        let both = PackSpec.allowing("files", true, in: granted)
        #expect(both["allow"] == .array([.string("system"), .string("files")]))
        let back = PackSpec.allowing("files", false, in: PackSpec.allowing("system", false, in: both))
        #expect(back == .table(["src": .string("a/b")]))
    }
}
