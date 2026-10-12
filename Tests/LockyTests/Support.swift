import Foundation
import Testing
@testable import Locky

/// A config folder of its own for each test, so no test reads the user's ~/.config/locky.
final class Sandbox {
    let root: URL
    var config: URL { root.appending(path: "config") }
    var packs: URL { root.appending(path: "packs") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "locky-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packs, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes `text` to config/<relative>.
    func write(_ relative: String, _ text: String) throws {
        let url = config.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The runtime path with this config folder, the built-in runtime, and (optionally) the built-in packages.
    func path(packages: Bool = false) -> RuntimePath {
        RuntimePath(config: config, packs: packs, roots: [config, RuntimePath.builtInRuntime] + (packages ? RuntimePath.builtInPackages : []))
    }
}

/// Collects what a runtime reports, from its queue.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _views: [Int: Node?] = [:]
    private var _failures: [Int: (String, Bool)] = [:]

    var views: [Int: Node?] { lock.withLock { _views } }
    var failures: [Int: (message: String, disabled: Bool)] { lock.withLock { _failures.mapValues { ($0.0, $0.1) } } }

    var delegate: LuaRuntime.Delegate {
        LuaRuntime.Delegate(
            present: { id, node in self.lock.withLock { self._views[id] = node } },
            failed: { id, message, disabled in self.lock.withLock { self._failures[id] = (message, disabled) } }
        )
    }
}

/// Polls `condition` until it holds or `timeout` passes.
func eventually(timeout: Double = 3, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

extension LuaRuntime {
    /// Boots with `init.lua` and returns the problems.
    func bootForTest() -> [String] {
        sync {
            try? boot()
            return problemsSoFar
        }
    }

    /// Runs Lua source in the runtime's state and returns its results.
    func eval(_ source: String, budget: Double = 1) throws -> [LuaValue] {
        try sync { try evaluate(source, budget: budget) }
    }
}
