import Foundation
import Testing
@testable import Locky

@Suite struct SettingsTests {
    private func runtime(_ sandbox: Sandbox) -> LuaRuntime {
        LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
    }

    private func config(_ runtime: LuaRuntime) throws -> LuaValue {
        try runtime.sync { try runtime.call("config", budget: 1) }.first ?? .nil
    }

    @Test func settingsWinOverInitLuaKeyByKey() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ theme = 'from-init', auto_unlock = 30, privacy = false })")
        try Settings(["theme": .string("from-settings"), "privacy": .bool(true)]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        let config = try config(runtime)
        #expect(config["theme"] == .string("from-settings"))
        #expect(config["privacy"] == .bool(true))
        // A key settings.json leaves out keeps init.lua's value.
        #expect(config["auto_unlock"] == .int(30))
    }

    @Test func valuesOfTheWrongTypeAreSkippedAndReported() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ theme = 'from-init' })")
        try sandbox.write("settings.json", #"{ "theme": 5, "hour24": true }"#)
        let runtime = runtime(sandbox)
        let problems = runtime.bootForTest()
        #expect(problems == ["settings.json theme: expected a string, got number"])
        let config = try config(runtime)
        #expect(config["theme"] == .string("from-init"))
        #expect(config["hour24"] == .bool(true))
    }

    @Test func aBrokenFileIsAProblemNotEmptySettingsToOverwrite() throws {
        let sandbox = try Sandbox()
        try sandbox.write("settings.json", "{ \"theme\": ")
        let (settings, problem) = Settings.load(config: sandbox.config)
        #expect(settings == Settings())
        #expect(problem?.contains("not valid JSON") == true)
        #expect(runtime(sandbox).bootForTest().first?.contains("settings.json is not valid JSON") == true)

        try sandbox.write("settings.json", "[1, 2]")
        #expect(Settings.load(config: sandbox.config).problem?.contains("JSON object") == true)
        // No file is no problem.
        try FileManager.default.removeItem(at: Settings.url(config: sandbox.config))
        #expect(Settings.load(config: sandbox.config).problem == nil)
    }

    @Test func savingKeepsKeysThisVersionDoesNotKnow() throws {
        let sandbox = try Sandbox()
        try sandbox.write("settings.json", #"{ "from_the_future": { "a": [1, 2.5, "x"] }, "theme": "old" }"#)
        var settings = Settings.load(config: sandbox.config).settings
        settings["theme"] = .string("new")
        try settings.save(config: sandbox.config)
        let saved = Settings.load(config: sandbox.config).settings
        #expect(saved["from_the_future"]["a"] == .array([.int(1), .double(2.5), .string("x")]))
        #expect(saved["theme"] == .string("new"))
        // Setting nil removes the key.
        settings["theme"] = .nil
        try settings.save(config: sandbox.config)
        #expect(Settings.load(config: sandbox.config).settings.values.keys.sorted() == ["from_the_future"])
    }

    @Test func aSymlinkedFileKeepsItsLink() throws {
        let sandbox = try Sandbox()
        let dotfiles = sandbox.root.appending(path: "dotfiles/settings.json")
        try FileManager.default.createDirectory(at: dotfiles.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: dotfiles, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: Settings.url(config: sandbox.config), withDestinationURL: dotfiles)
        try Settings(["theme": .string("linked")]).save(config: sandbox.config)
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: Settings.url(config: sandbox.config).path)
        #expect(link == dotfiles.path)
        #expect(try String(contentsOf: dotfiles, encoding: .utf8).contains("linked"))
    }

    @Test func packagesFromSettingsLoadBeforeInitLuaRequiresThem() throws {
        let sandbox = try Sandbox()
        let package = sandbox.root.appending(path: "my-plugin")
        try FileManager.default.createDirectory(at: package.appending(path: "lua"), withIntermediateDirectories: true)
        try "return { hello = 'from the plugin' }".write(to: package.appending(path: "lua/myplugin.lua"), atomically: true, encoding: .utf8)
        try Settings(["packs": .array([.table(["dir": .string(package.path)])])]).save(config: sandbox.config)
        // init.lua adds the same package too; settings.json's comes first, and that is not an error.
        try sandbox.write("init.lua", """
        locky.pack.add({ { dir = "\(package.path)" } })
        locky.setup({ message = require("myplugin").hello })
        """)
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        #expect(try config(runtime)["message"] == .string("from the plugin"))
        let specs = try runtime.sync { try runtime.call("pack_specs", budget: 1) }.first?.array ?? []
        #expect(specs.count == 1)
        #expect(specs.first?["from"] == .string("settings"))
        #expect(specs.first?["in_config"] == .bool(true))
    }

    @Test func aBadPackageEntryIsReportedAndTheOthersStillLoad() throws {
        let sandbox = try Sandbox()
        try Settings(["packs": .array([.int(5), .string("someone/locky-weather")])]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        let problems = runtime.bootForTest()
        #expect(problems.count == 1)
        #expect(problems.first == "settings.json packs: [1] spec: expected table, got number")
        let specs = try runtime.sync { try runtime.call("pack_specs", budget: 1) }.first?.array ?? []
        #expect(specs.map { $0["name"] } == [.string("locky-weather")])
    }
}
