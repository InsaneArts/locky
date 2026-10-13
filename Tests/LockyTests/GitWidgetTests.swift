import Foundation
import Testing
@testable import Locky

/// The git widget, against real repositories.
@Suite struct GitWidgetTests {
    private func git(_ arguments: [String], in dir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir.path, "-c", "user.name=t", "-c", "user.email=t@t"] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "git \(arguments.joined(separator: " "))")
    }

    /// A repository "secret-repo" on the branch "feature-x" with one commit and one changed file.
    private func repository(in sandbox: Sandbox) throws -> URL {
        let repo = sandbox.root.appending(path: "secret-repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try git(["init", "--quiet", "--initial-branch=feature-x"], in: repo)
        try "a".write(to: repo.appending(path: "file"), atomically: true, encoding: .utf8)
        try git(["add", "file"], in: repo)
        try git(["commit", "--quiet", "-m", "secret subject"], in: repo)
        try "b".write(to: repo.appending(path: "file"), atomically: true, encoding: .utf8)
        return repo
    }

    private func texts(_ node: Node?) -> [String] {
        guard let node else { return [] }
        switch node.kind {
        case .vstack(let children), .hstack(let children), .zstack(let children), .grid(let children): return children.flatMap(texts)
        case .text(let text): return [text]
        default: return []
        }
    }

    /// The texts the widget shows for `repo`, once it has read it.
    private func shown(_ repo: URL, privacy: Bool = false, in sandbox: Sandbox) async throws -> [String] {
        try sandbox.write("themes/g.lua", "return { widgets = { { 'git', opts = { repos = { '\(repo.path)', '/' } } } } }")
        try sandbox.write("init.lua", "locky.setup({ privacy = \(privacy) })")
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        let started = await runtime.start(theme: "g")
        defer { runtime.stop() }
        #expect(started.problems.isEmpty, "\(started.problems)")
        let id = try #require(started.instances.first ?? nil)
        // Both rows: the repository's and the one for "/".
        #expect(await eventually {
            let shown = texts(recorder.views[id] ?? nil)
            return shown.contains("●1") && shown.contains { $0.hasSuffix("not a repository") }
        })
        return texts(recorder.views[id] ?? nil)
    }

    @Test func showsTheRepositoryAndItsBranch() async throws {
        let sandbox = try Sandbox()
        let texts = try await shown(try repository(in: sandbox), in: sandbox)
        #expect(texts.contains("secret-repo") && texts.contains("feature-x") && texts.contains("●1"), "\(texts)")
        #expect(texts.contains { $0.hasPrefix("secret subject · ") } && texts.contains("/: not a repository"), "\(texts)")
    }

    /// Repository and branch names say what you work on: privacy mode shows the counts only.
    @Test func privacyModeShowsCountsOnly() async throws {
        let sandbox = try Sandbox()
        let texts = try await shown(try repository(in: sandbox), privacy: true, in: sandbox)
        #expect(texts == ["●1", "not a repository"], "\(texts)")
    }

    /// A repository's config could run a program each time the widget asks for its status.
    @Test func aRepositoryCannotRunAProgram() async throws {
        let sandbox = try Sandbox()
        let repo = try repository(in: sandbox)
        let marker = sandbox.root.appending(path: "ran")
        let hook = sandbox.root.appending(path: "hook.sh")
        try "#!/bin/sh\ntouch '\(marker.path)'\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try git(["config", "core.fsmonitor", hook.path], in: repo)
        let texts = try await shown(repo, in: sandbox)
        #expect(texts.contains("feature-x"), "\(texts)")
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
}
