import Foundation
import Testing
@testable import Locky

@Suite struct PackManagerTests {
    @discardableResult
    private func git(_ arguments: [String], in dir: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir.path] + arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "git \(arguments.joined(separator: " "))")
        return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The address the tests give the plugin's repository: locky.pack.add takes only https://, ssh://, and git@ sources,
    /// and git maps this one to the local repository.
    private let address = "https://locky.test/locky-hello"

    private func manager(_ sandbox: Sandbox, _ repo: URL) -> PackManager {
        var manager = PackManager(path: sandbox.path())
        manager.gitConfig = ["url.\(repo.path).insteadOf=\(address)"]
        return manager
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
        try sandbox.write("init.lua", "locky.pack.add({ { src = \"\(address)\", name = \"hello\" } })")
        let manager = manager(sandbox, repo)

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
        try sandbox.write("init.lua", "locky.pack.add({ { src = \"\(address)\", name = \"hello\" } })")
        let manager = manager(sandbox, repo)
        #expect(manager.run(.sync).ok)
        // A require of a package not installed yet stops init.lua before its pack.add line.
        try sandbox.write("init.lua", "require('not_installed_yet').setup({})\nlocky.pack.add({ { src = \"\(address)\", name = \"hello\" } })")
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
        #expect(report.text.contains("not a plugin name"))
    }

    /// Remove Unused lists what it would delete and deletes only what the user confirmed.
    @Test func cleanRemovesOnlyTheConfirmedPlugins() throws {
        let sandbox = try Sandbox()
        let zero = String(repeating: "0", count: 40)
        try #"{"plugins":{"a":{"src":"x","rev":"\#(zero)"},"b":{"src":"x","rev":"\#(zero)"},"kept":{"src":"x","rev":"\#(zero)"}}}"#
            .write(to: sandbox.path().lockfile, atomically: true, encoding: .utf8)
        for name in ["a", "b", "kept"] {
            try FileManager.default.createDirectory(at: sandbox.packs.appending(path: name), withIntermediateDirectories: true)
        }
        try sandbox.write("init.lua", "locky.pack.add({ { src = 'https://example.com/kept.git' } })")
        let manager = PackManager(path: sandbox.path())
        let specs = manager.specs().specs
        #expect(manager.unused(specs, lockfile: try PackManager.readLockfile(sandbox.path().lockfile)) == ["a", "b"])
        #expect(manager.run(.clean, removing: ["a"]).text == "removed a")
        #expect(!FileManager.default.fileExists(atPath: sandbox.packs.appending(path: "a").path))
        #expect(FileManager.default.fileExists(atPath: sandbox.packs.appending(path: "b").path))
        #expect(try PackManager.readLockfile(sandbox.path().lockfile).plugins.keys.sorted() == ["b", "kept"])
    }

    @Test func gitNeverRunsOutsideAClone() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        // A folder with the package's name that is not a clone: git must not act on any enclosing repository.
        try FileManager.default.createDirectory(at: sandbox.packs.appending(path: "hello"), withIntermediateDirectories: true)
        try sandbox.write("init.lua", "locky.pack.add({ { src = \"\(address)\", name = \"hello\" } })")
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

    /// A check that read the lockfile reached every plugin it pins, none at all included. One that failed as a whole did
    /// not: the window then says nothing of when it ran.
    @Test func aCheckSaysWhetherItReadTheLockfile() throws {
        let sandbox = try Sandbox()
        let manager = PackManager(path: sandbox.path())
        let empty = manager.run(.check)
        #expect(empty.ok && empty.readLockfile && empty.updates.isEmpty)
        // Another run holds the plugins.
        let lock = open(sandbox.packs.appending(path: ".locky-pack.lock").path, O_CREAT | O_RDWR, 0o644)
        defer { close(lock) }
        #expect(flock(lock, LOCK_EX) == 0)
        let busy = manager.run(.check)
        #expect(!busy.ok && !busy.readLockfile && busy.text == "Another plugin run is in progress. Try again when it finishes.")
        flock(lock, LOCK_UN)
        try "<<<<<<< HEAD\n{}\n=======\n{}\n>>>>>>> theirs\n".write(to: sandbox.path().lockfile, atomically: true, encoding: .utf8)
        let unreadable = manager.run(.check)
        #expect(!unreadable.ok && !unreadable.readLockfile)
    }

    @Test func specsRefuseOptionLikeValuesAndCaseTwins() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.pack.add({ { src = '--upload-pack=x', name = 'a' } })")
        #expect(PackManager(path: sandbox.path()).specs().problems.first?.contains("must not start with '-'") == true)
        try sandbox.write("init.lua", "locky.pack.add({ 'a/One', 'b/one' })")
        #expect(PackManager(path: sandbox.path()).specs().problems.first?.contains("two packages are named") == true)
    }

    /// A NUL byte that reached git's arguments made Foundation raise an Objective-C exception, which ends the app.
    @Test func specsRefuseControlCharacters() throws {
        let sandbox = try Sandbox()
        for spec in [#"{ src = "a/b\0" }"#, #"{ src = "a/b", version = "main\0" }"#, #"{ src = "a/b", name = "b\n" }"#, #"{ dir = "/tmp/x\0y" }"#] {
            try sandbox.write("init.lua", "locky.pack.add({ \(spec) })")
            let (specs, problems) = PackManager(path: sandbox.path()).specs()
            #expect(specs.isEmpty, "\(spec)")
            #expect(problems.first?.contains("must not contain control characters") == true, "\(spec)")
        }
        // settings.json's packages too: JSON can hold a NUL.
        try sandbox.write("init.lua", "-- nothing")
        try sandbox.write("settings.json", #"{ "packs": [ { "src": "a/b", "version": "main\u0000" } ] }"#)
        let (specs, problems) = PackManager(path: sandbox.path()).specs()
        #expect(specs.isEmpty)
        #expect(problems == ["settings.json packs: [1] spec.version: must not contain control characters"])
    }

    /// A NUL inside an argument makes Process raise; one at the end cuts the argument short.
    @Test func gitNeverRunsWithANulByte() throws {
        let sandbox = try Sandbox()
        let manager = PackManager(path: sandbox.path())
        for argument in ["origin/ma\0in^{commit}", "main\0"] {
            let result = manager.runGit(["-C", sandbox.packs.path, "rev-parse", "--verify", "--quiet", argument])
            #expect(!result.ok)
            #expect(result.error.contains("NUL"))
        }
    }

    // MARK: check

    /// Adds `repo` as the package "hello" at `version` and syncs it.
    private func synced(_ repo: URL, version: String? = nil, in sandbox: Sandbox) throws -> PackManager {
        let pin = version.map { ", version = \"\($0)\"" } ?? ""
        try sandbox.write("init.lua", "locky.pack.add({ { src = \"\(address)\", name = \"hello\"\(pin) } })")
        let manager = manager(sandbox, repo)
        #expect(manager.run(.sync).ok)
        return manager
    }

    /// What check found, without the commits and diffstat.
    private func found(_ manager: PackManager) -> [PackUpdate] {
        manager.checkUpdates().map { update in
            var update = update
            update.changes = []
            return update
        }
    }

    /// Commits a new greeting upstream on `branch` and returns the commit.
    private func commit(_ greeting: String, on branch: String = "main", in repo: URL) throws -> String {
        try git(["checkout", "--quiet", branch], in: repo)
        try "return { greeting = \"\(greeting)\" }".write(to: repo.appending(path: "lua/hello/init.lua"), atomically: true, encoding: .utf8)
        try git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "--quiet", "-am", greeting], in: repo)
        let rev = try git(["rev-parse", "HEAD"], in: repo)
        try git(["checkout", "--quiet", "main"], in: repo)
        return rev
    }

    @Test func checkSaysUpToDate() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        let report = try synced(repo, in: sandbox).run(.check)
        let head = try git(["rev-parse", "HEAD"], in: repo)
        #expect(report.ok)
        #expect(report.text == "hello: up to date")
        #expect(report.updates == [PackUpdate(name: "hello", current: head, latest: head)])
    }

    @Test func checkFindsANewCommitOnTheDefaultBranch() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        let manager = try synced(repo, in: sandbox)
        let old = try git(["rev-parse", "HEAD"], in: repo)
        let new = try commit("hi", in: repo)
        let report = manager.run(.check)
        #expect(report.ok)
        #expect(report.lines.first == "hello: update available \(old.prefix(7)) → \(new.prefix(7))")
        #expect(found(manager) == [PackUpdate(name: "hello", current: old, latest: new)])
    }

    @Test func aPinnedCommitIsNeverAnUpdate() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        let manager = try synced(repo, version: try git(["rev-parse", "HEAD"], in: repo), in: sandbox)
        _ = try commit("hi", in: repo)
        #expect(manager.run(.check).text == "hello: up to date")
    }

    @Test func aBranchFollowsItsOwnCommits() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        try git(["branch", "dev"], in: repo)
        let manager = try synced(repo, version: "dev", in: sandbox)
        let old = try git(["rev-parse", "dev"], in: repo)
        // A commit on the default branch is not one on dev.
        _ = try commit("main only", in: repo)
        #expect(manager.run(.check).text == "hello: up to date")
        let new = try commit("dev only", on: "dev", in: repo)
        #expect(found(manager) == [PackUpdate(name: "hello", current: old, latest: new)])
    }

    @Test func aTagMeansItsCommit() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        let tag = ["-c", "user.name=t", "-c", "user.email=t@t", "tag", "--force", "--annotate", "--message", "v1", "v1"]
        try git(tag, in: repo)
        let manager = try synced(repo, version: "v1", in: sandbox)
        // The annotated tag's own object is not the commit it names.
        #expect(manager.run(.check).text == "hello: up to date")
        let old = try git(["rev-parse", "HEAD"], in: repo)
        let new = try commit("hi", in: repo)
        try git(tag, in: repo)
        #expect(found(manager) == [PackUpdate(name: "hello", current: old, latest: new)])
    }

    @Test func aMissingCloneIsNotInstalledAndStaysMissing() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        let manager = try synced(repo, in: sandbox)
        let clone = sandbox.packs.appending(path: "hello")
        try FileManager.default.removeItem(at: clone)
        let report = manager.run(.check)
        #expect(report.ok)
        #expect(report.text == "hello: not installed")
        #expect(report.updates == [PackUpdate(name: "hello")])
        #expect(!FileManager.default.fileExists(atPath: clone.path))
    }

    /// check reads the lockfile: without one, there is nothing to check, whatever init.lua adds.
    @Test func withoutALockfileThereIsNothingToCheck() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        let manager = try synced(repo, in: sandbox)
        try FileManager.default.removeItem(at: sandbox.path().lockfile)
        let report = manager.run(.check)
        #expect(report.ok)
        #expect(report.text == "No plugins to check.")
        #expect(report.updates.isEmpty)
    }

    @Test func checkMovesNoCheckoutAndNoLockfile() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        let manager = try synced(repo, in: sandbox)
        _ = try commit("hi", in: repo)
        let clone = sandbox.packs.appending(path: "hello")
        let head = try git(["rev-parse", "HEAD"], in: clone)
        let lockfile = try Data(contentsOf: sandbox.path().lockfile)

        #expect(manager.run(.check).text.contains("update available"))
        #expect(try git(["rev-parse", "HEAD"], in: clone) == head)
        #expect(try git(["status", "--porcelain"], in: clone).isEmpty)
        #expect(try git(["remote", "get-url", "origin"], in: clone) == address)
        #expect(try Data(contentsOf: sandbox.path().lockfile) == lockfile)
    }

    /// The daily check runs in the background: it must not run init.lua or any plugin's code.
    @Test func checkRunsNoLua() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        let manager = try synced(repo, in: sandbox)
        let marker = sandbox.root.appending(path: "ran")
        try sandbox.write("init.lua", "io.open('\(marker.path)', 'w'):close() error('init.lua ran')")
        try "io.open('\(marker.path)', 'w'):close()".write(to: sandbox.packs.appending(path: "hello/plugin.lua"), atomically: true, encoding: .utf8)
        let report = manager.run(.check)
        #expect(report.ok)
        #expect(report.text == "hello: up to date")
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    /// What an update brings, before it applies: each commit and the diffstat.
    @Test func checkAndUpdateListTheCommits() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        let manager = try synced(repo, in: sandbox)
        let new = try commit("hi\u{1b}[31m", in: repo)
        let report = manager.run(.check)
        let update = try #require(report.updates.first)
        #expect(update.changes.count == 3, "\(update.changes)")
        #expect(update.changes.first == "  \(new.prefix(7)) hi[31m")
        #expect(update.changes.last?.contains("1 file changed, 1 insertion(+), 1 deletion(-)") == true)
        // The diffstat keeps git's own leading space, its first line too, so its lines line up.
        #expect(update.changes.dropFirst().allSatisfy { $0.hasPrefix("   ") && !$0.hasPrefix("    ") }, "\(update.changes)")
        #expect(report.lines == [update.line] + update.changes)
        // locky pack update prints the same lines as it moves.
        #expect(manager.run(.update).lines == ["updated hello \(update.current!.prefix(7)) → \(new.prefix(7))\n" + update.changes.joined(separator: "\n")])
    }

    /// Update in the window installs the commit the user reviewed, even if upstream moved on since.
    @Test func applyMovesToTheReviewedCommit() throws {
        let sandbox = try Sandbox()
        let repo = try makePlugin(in: sandbox, greeting: "hello")
        let manager = try synced(repo, in: sandbox)
        let reviewed = try commit("hi", in: repo)
        let updates = manager.checkUpdates()
        _ = try commit("later", in: repo)
        _ = manager.run(.check)
        let report = manager.apply(updates)
        #expect(report.ok, "\(report.lines)")
        #expect(try git(["rev-parse", "HEAD"], in: sandbox.packs.appending(path: "hello")) == reviewed)
        #expect(try PackManager.readLockfile(sandbox.path().lockfile).plugins["hello"]?.rev == reviewed)
        // A review that no longer matches the lockfile applies nothing.
        #expect(!manager.apply(updates).ok)
    }

    @Test func onlyEncryptedSourcesAreAccepted() throws {
        let sandbox = try Sandbox()
        for src in ["http://example.com/x.git", "file:///tmp/x", "/tmp/x", "git://example.com/x"] {
            try sandbox.write("init.lua", "locky.pack.add({ '\(src)' })")
            let (specs, problems) = PackManager(path: sandbox.path()).specs()
            #expect(specs.isEmpty, "\(src)")
            #expect(problems.first?.contains("or an https://, ssh://, or git@ address (not http:// or file://") == true, "\(src): \(problems)")
            #expect(PackSpec.problem(source: src) != nil, "\(src)")
        }
        for src in ["someone/x", "https://example.com/x.git", "ssh://git@example.com/x.git", "git@github.com:someone/x.git"] {
            try sandbox.write("init.lua", "locky.pack.add({ '\(src)' })")
            #expect(PackManager(path: sandbox.path()).specs().problems.isEmpty, "\(src)")
            #expect(PackSpec.problem(source: src) == nil, "\(src)")
        }
        // A local folder stays a dir package.
        try sandbox.write("init.lua", "locky.pack.add({ { dir = '/tmp/x' } })")
        #expect(PackManager(path: sandbox.path()).specs().problems.isEmpty)
    }

    /// git itself refuses plain http, so not even a redirect from https reaches it.
    @Test func gitRefusesPlainHttp() throws {
        let sandbox = try Sandbox()
        let result = PackManager(path: sandbox.path()).runGit(["ls-remote", "http://127.0.0.1:9/x.git"])
        #expect(!result.ok)
        #expect(result.error.contains("transport 'http' not allowed"), "\(result.error)")
    }
}
