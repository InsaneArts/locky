import Foundation
import Testing
@testable import Locky

@Suite struct PackManagerTests {
    private func git(_ arguments: [String], in dir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "git \(arguments.joined(separator: " "))")
    }

    /// A git repository holding a tiny Locky plugin.
    private func makePlugin(in sandbox: Sandbox, greeting: String) throws -> URL {
        let repo = sandbox.root.appending(path: "upstream/locky-hello")
        try FileManager.default.createDirectory(at: repo.appending(path: "lua/hello"), withIntermediateDirectories: true)
        try "return { greeting = \"\(greeting)\" }".write(to: repo.appending(path: "lua/hello/init.lua"), atomically: true, encoding: .utf8)
        try git(["init", "--quiet", "--initial-branch=main"], in: repo)
        try git(["-c", "user.name=t", "-c", "user.email=t@t", "add", "."], in: repo)
        try git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "--quiet", "-m", greeting], in: repo)
        return repo
    }

    @Test func installsLocksUpdatesAndCleans() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        try sandbox.write("init.lua", "locky.pack.add({ { src = \"\(repo.path)\", name = \"hello\" } })")
        let manager = PackManager(path: sandbox.path())

        #expect(manager.run(.sync).text.contains("installed hello"))
        let first = try PackManager.readLockfile(sandbox.path().lockfile).plugins["hello"]?.rev
        #expect(first?.count == 40)

        // The package is on the runtime path: require finds it.
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        #expect(runtime.bootForTest().isEmpty)
        #expect(try runtime.eval("return require('hello').greeting") == [.string("hello")])

        // A new upstream commit: sync keeps the locked one, update moves to it.
        try "return { greeting = \"hi\" }".write(to: repo.appending(path: "lua/hello/init.lua"), atomically: true, encoding: .utf8)
        try git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "--quiet", "-am", "hi"], in: repo)
        #expect(manager.run(.sync).text.contains("up to date"))
        #expect(manager.run(.update).text.contains("updated hello"))
        let second = try PackManager.readLockfile(sandbox.path().lockfile).plugins["hello"]?.rev
        #expect(second != nil && second != first)

        // Dropped from init.lua: clean removes it.
        try sandbox.write("init.lua", "-- no packages")
        #expect(manager.run(.clean).text.contains("removed hello"))
        #expect(!FileManager.default.fileExists(atPath: sandbox.packs.appending(path: "hello").path))
        #expect(try PackManager.readLockfile(sandbox.path().lockfile).plugins.isEmpty)
    }

    @Test func specsAcceptShorthandAndLocalFolders() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", """
            locky.pack.add({ "someone/locky-weather", { src = "https://example.com/x.git", version = "v1.2.0" }, { dir = "~/code/my-plugin" } })
            """)
        let (specs, problems) = PackManager(path: sandbox.path()).specs()
        #expect(problems.isEmpty)
        #expect(specs == [
            PackManager.Spec(name: "locky-weather", src: "https://github.com/someone/locky-weather"),
            PackManager.Spec(name: "x", src: "https://example.com/x.git", version: "v1.2.0"),
            PackManager.Spec(name: "my-plugin", dir: FileManager.default.homeDirectoryForCurrentUser.path + "/code/my-plugin"),
        ])
    }

    @Test func duplicateNamesAreAnError() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.pack.add({ 'a/same', 'b/same' })")
        let (_, problems) = PackManager(path: sandbox.path()).specs()
        #expect(problems.first?.contains("two packages are named \"same\"") == true)
    }

    @Test func cleanRefusesWhenInitLuaFails() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        try sandbox.write("init.lua", "locky.pack.add({ { src = \"\(repo.path)\", name = \"hello\" } })")
        let manager = PackManager(path: sandbox.path())
        #expect(manager.run(.sync).ok)
        // A require of a package not installed yet stops init.lua before its pack.add line.
        try sandbox.write("init.lua", "require('not_installed_yet').setup({})\nlocky.pack.add({ { src = \"\(repo.path)\", name = \"hello\" } })")
        let report = manager.run(.clean)
        #expect(!report.ok)
        #expect(report.text.contains("Nothing removed"))
        #expect(FileManager.default.fileExists(atPath: sandbox.packs.appending(path: "hello/.git").path))
    }

    @Test func cleanRemovesOnlyWhatLockyInstalled() throws {
        let sandbox = try Sandbox()
        let fm = FileManager.default
        // A hand-made folder, and a local plugin kept in the pack folder and still added by init.lua.
        try fm.createDirectory(at: sandbox.packs.appending(path: "mine"), withIntermediateDirectories: true)
        try fm.createDirectory(at: sandbox.packs.appending(path: "devplug/lua"), withIntermediateDirectories: true)
        try sandbox.write("init.lua", "locky.pack.add({ { dir = \"\(sandbox.packs.appending(path: "devplug").path)\" } })")
        // An edited lockfile that names a path outside the pack folder.
        try #"{"plugins":{"../escape":{"src":"x","rev":"0000000000000000000000000000000000000000"}}}"#
            .write(to: sandbox.path().lockfile, atomically: true, encoding: .utf8)
        let report = PackManager(path: sandbox.path()).run(.clean)
        #expect(fm.fileExists(atPath: sandbox.packs.appending(path: "mine").path))
        #expect(fm.fileExists(atPath: sandbox.packs.appending(path: "devplug").path))
        #expect(report.text.contains("not a package name"))
    }

    @Test func gitNeverRunsOutsideAClone() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        // A folder with the package's name that is not a clone: git must not act on any enclosing repository.
        try FileManager.default.createDirectory(at: sandbox.packs.appending(path: "hello"), withIntermediateDirectories: true)
        try sandbox.write("init.lua", "locky.pack.add({ { src = \"\(repo.path)\", name = \"hello\" } })")
        let report = PackManager(path: sandbox.path()).run(.sync)
        #expect(!report.ok)
        #expect(report.text.contains("is not a git clone"))
    }

    @Test func anUnreadableLockfileIsLeftAlone() throws {
        let sandbox = try Sandbox()
        let conflicted = "<<<<<<< HEAD\n{}\n=======\n{}\n>>>>>>> theirs\n"
        try conflicted.write(to: sandbox.path().lockfile, atomically: true, encoding: .utf8)
        try sandbox.write("init.lua", "-- nothing")
        let report = PackManager(path: sandbox.path()).run(.sync)
        #expect(!report.ok)
        #expect(try String(contentsOf: sandbox.path().lockfile, encoding: .utf8) == conflicted)
    }

    @Test func specsRefuseOptionLikeValuesAndCaseTwins() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.pack.add({ { src = '--upload-pack=x', name = 'a' } })")
        #expect(PackManager(path: sandbox.path()).specs().problems.first?.contains("must not start with '-'") == true)
        try sandbox.write("init.lua", "locky.pack.add({ 'a/One', 'b/one' })")
        #expect(PackManager(path: sandbox.path()).specs().problems.first?.contains("two packages are named") == true)
    }
}
