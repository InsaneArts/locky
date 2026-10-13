import Foundation

/// Installs, updates, and removes the packages init.lua names with locky.pack.add, after Neovim's vim.pack.
/// Each package is a git clone in RuntimePath.packs. The lockfile pins each one to a commit, so the same
/// dotfiles give the same plugins on every Mac.
///
/// It never touches what it did not install: `clean` removes only folders the lockfile lists, and git runs
/// only inside real clones in the pack folder, never in a repository that encloses one.
struct PackManager {
    enum Action: String {
        /// Clones missing packages and moves each one to its locked commit.
        case sync
        /// Fetches and moves each package to the newest commit of its version (a tag, branch, or commit),
        /// or of the default branch; then rewrites the lockfile. Each one that moved lists its commits and diffstat.
        case update
        /// Fetches each package the lockfile pins and says which ones `update` would move, with their commits and
        /// diffstat. Changes no checkout and no lockfile, and runs no Lua: it is safe in the background.
        case check
        /// Deletes packages Locky installed that init.lua no longer adds.
        case clean
        case list
    }

    struct Spec: Equatable {
        var name: String
        var src: String?
        var version: String?
        var dir: String?
        /// What the user lets it do beyond reading: "system" (run programs) and "files" (change files).
        var allow: [String] = []

        /// "may run programs, may not change files"; a local folder is the user's own code, which needs no grant.
        var grants: String {
            if dir != nil { return "your own folder, no limits" }
            return [("system", "run programs"), ("files", "change files")]
                .map { (allow.contains($0.0) ? "may " : "may not ") + $0.1 }
                .joined(separator: ", ")
        }
    }

    struct Lockfile: Codable, Equatable {
        struct Entry: Codable, Equatable {
            var src: String
            var rev: String
            var version: String?
        }

        var plugins: [String: Entry] = [:]
    }

    struct Report {
        var lines: [String]
        var ok: Bool
        /// `check` only: what it found for each package.
        var updates: [PackUpdate] = []
        var text: String { lines.joined(separator: "\n") }
    }

    let path: RuntimePath
    var git = "/usr/bin/git"
    /// More `-c` settings for every git command. Tests map an https address to a local repository with
    /// url.<path>.insteadOf, since locky.pack.add takes only https://, ssh://, and git@ sources.
    var gitConfig: [String] = []
    /// Seconds a clone or fetch may take; local git commands get a few seconds.
    var networkTimeout: Double = 180

    /// The packages init.lua adds, and any errors in running it.
    func specs() -> (specs: [Spec], problems: [String]) {
        let runtime = LuaRuntime(path: path, delegate: .init(present: { _, _ in }, failed: { _, _, _ in }))
        return runtime.sync {
            do {
                try runtime.boot()
            } catch {
                return ([], ["Lua failed to start: \(error)"])
            }
            let problems = runtime.problemsSoFar
            let list = (try? runtime.call("pack_specs", budget: LuaRuntime.Budget.callback).first?.array) ?? []
            let specs = list.map { Spec(name: $0["name"].string ?? "?", src: $0["src"].string, version: $0["version"].string, dir: $0["dir"].string,
                                     allow: $0["allow"].array?.compactMap(\.string) ?? []) }
            return (specs, problems)
        }
    }

    static func lockedNames(path: RuntimePath) -> [String] {
        (try? readLockfile(path.lockfile))?.plugins.keys.sorted() ?? []
    }

    /// The lockfile, an empty one when there is none, or an error when it exists but cannot be read (for
    /// example with merge-conflict markers): then nothing may overwrite it.
    static func readLockfile(_ url: URL) throws -> Lockfile {
        guard FileManager.default.fileExists(atPath: url.path) else { return Lockfile() }
        return try JSONDecoder().decode(Lockfile.self, from: Data(contentsOf: url))
    }

    func writeLockfile(_ lockfile: Lockfile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try Settings.createFolder(path.config)
        // Through the link: dotfiles managers (stow, home-manager) often make the lockfile a symlink.
        try encoder.encode(lockfile).write(to: path.lockfile.resolvingSymlinksInPath(), options: .atomic)
    }

    /// Runs `action`. One line per package; `ok` is false when anything failed. For `clean`, `removing` limits what
    /// it deletes to the packages the user confirmed.
    func run(_ action: Action, removing: [String]? = nil) -> Report {
        let fm = FileManager.default
        try? fm.createDirectory(at: path.packs, withIntermediateDirectories: true)
        // One run at a time, whether it comes from the menu or the command line.
        guard let lock = FolderLock(path.packs.appending(path: ".locky-pack.lock")) else {
            return Report(lines: ["Another plugin run is in progress. Try again when it finishes."], ok: false)
        }
        defer { lock.release() }

        // check reads the lockfile only: it must not run init.lua or plugin code.
        let (specs, problems) = action == .check ? ([], []) : specs()
        var lines = problems.map { "init.lua: \($0)" }
        var ok = problems.isEmpty
        let lockfile: Lockfile
        do {
            lockfile = try Self.readLockfile(path.lockfile)
        } catch {
            lines.append("cannot read \(LuaError.shortenPaths(path.lockfile.path)): \(error.localizedDescription). Fix or delete it; nothing was changed.")
            return Report(lines: lines, ok: false)
        }
        var updated = lockfile
        var checked: [PackUpdate] = []

        switch action {
        case .list:
            if specs.isEmpty { lines.append("No plugins. Add some in init.lua with locky.pack.add({ \"user/repo\" }).") }
            for spec in specs {
                if let dir = spec.dir {
                    lines.append("\(spec.name)  local  \(dir)")
                    continue
                }
                let installed = isClone(path.packs.appending(path: spec.name))
                let rev = lockfile.plugins[spec.name].map { String($0.rev.prefix(7)) } ?? "-"
                lines.append("\(spec.name)  \(installed ? rev : "not installed")  \(spec.src ?? "")\(spec.version.map { "  @\($0)" } ?? "")")
            }
        case .clean:
            // A config that stopped early names fewer packages than it means to: cleaning then would delete
            // packages it still wants.
            guard problems.isEmpty else {
                lines.append("Nothing removed: init.lua has errors, so Locky cannot tell which plugins it still wants.")
                return Report(lines: lines, ok: false)
            }
            // An edited lockfile must not point outside the pack folder.
            for name in lockfile.plugins.keys.sorted() where !Self.isPackageName(name) {
                lines.append("skipped \"\(name)\" in the lockfile: not a plugin name")
            }
            for name in unused(specs, lockfile: lockfile) where removing?.contains(name) ?? true {
                let folder = path.packs.appending(path: name)
                updated.plugins[name] = nil
                guard fm.fileExists(atPath: folder.path) else { continue }
                do {
                    try fm.removeItem(at: folder)
                    lines.append("removed \(name)")
                } catch {
                    ok = false
                    lines.append("\(name): cannot remove: \(error.localizedDescription)")
                }
            }
            if lines.isEmpty { lines.append("Nothing to remove.") }
        case .sync, .update:
            for spec in specs {
                if spec.dir != nil { continue }
                guard let src = spec.src else { continue }
                let (line, success) = install(spec, src: src, update: action == .update, lockfile: &updated)
                lines.append(line)
                if !success { ok = false }
            }
            if specs.isEmpty { lines.append("No plugins to install.") }
        case .check:
            for (name, locked) in lockfile.plugins.sorted(by: { $0.key < $1.key }) where Self.isPackageName(name) {
                let update = check(name, locked: locked)
                checked.append(update)
                lines.append(update.line)
                lines += update.changes
                if update.error != nil { ok = false }
            }
            if checked.isEmpty { lines.append("No plugins to check.") }
        }
        if action != .list, updated != lockfile {
            do {
                try writeLockfile(updated)
            } catch {
                ok = false
                lines.append("cannot write \(LuaError.shortenPaths(path.lockfile.path)): \(error.localizedDescription)")
            }
        }
        return Report(lines: lines, ok: ok, updates: checked)
    }

    /// What `clean` removes: the packages the lockfile lists that `specs` no longer add, other than a
    /// { dir = ... } package kept in the pack folder.
    func unused(_ specs: [Spec], lockfile: Lockfile) -> [String] {
        let wanted = Set(specs.filter { $0.dir == nil }.map { $0.name.lowercased() })
        let local = Set(specs.compactMap(\.dir).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
        return lockfile.plugins.keys.sorted().filter { name in
            Self.isPackageName(name) && !wanted.contains(name.lowercased())
                && !local.contains(path.packs.appending(path: name).resolvingSymlinksInPath().path)
        }
    }

    /// `check`'s result for each package, for the window. A busy run and an unreadable lockfile appear only in
    /// run(.check)'s lines.
    func checkUpdates() -> [PackUpdate] {
        run(.check).updates
    }

    /// Moves each package to the commit `check` found for it, and no other: what the user reviewed is what
    /// installs. Runs no Lua.
    func apply(_ updates: [PackUpdate]) -> Report {
        guard let lock = FolderLock(path.packs.appending(path: ".locky-pack.lock")) else {
            return Report(lines: ["Another plugin run is in progress. Try again when it finishes."], ok: false)
        }
        defer { lock.release() }
        var lockfile: Lockfile
        do {
            lockfile = try Self.readLockfile(path.lockfile)
        } catch {
            return Report(lines: ["cannot read \(LuaError.shortenPaths(path.lockfile.path)): \(error.localizedDescription). Fix or delete it; nothing was changed."], ok: false)
        }
        var lines: [String] = [], ok = true
        for update in updates {
            let dir = path.packs.appending(path: update.name)
            guard Self.isPackageName(update.name), let latest = update.latest, Self.isRevision(latest), isClone(dir),
                  let entry = lockfile.plugins[update.name], entry.rev == update.current else {
                lines.append("\(update.name): changed since the check; check again")
                ok = false
                continue
            }
            let checkout = runGit(["-C", dir.path, "checkout", "--quiet", "--detach", "--end-of-options", latest])
            guard checkout.ok else {
                lines.append("\(update.name): cannot check out \(latest.prefix(7)): \(checkout.error)")
                ok = false
                continue
            }
            lockfile.plugins[update.name]?.rev = latest
            lines.append("updated \(update.name) \(entry.rev.prefix(7)) → \(latest.prefix(7))")
        }
        do {
            try writeLockfile(lockfile)
        } catch {
            ok = false
            lines.append("cannot write \(LuaError.shortenPaths(path.lockfile.path)): \(error.localizedDescription)")
        }
        return Report(lines: lines, ok: ok)
    }

    /// A real git clone: a folder (not a symlink) with its own .git.
    private func isClone(_ dir: URL) -> Bool {
        let values = try? dir.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
            && FileManager.default.fileExists(atPath: dir.appending(path: ".git").path)
    }

    private func install(_ spec: Spec, src: String, update: Bool, lockfile: inout Lockfile) -> (String, Bool) {
        let dir = path.packs.appending(path: spec.name)
        let fresh = !FileManager.default.fileExists(atPath: dir.path)
        if fresh {
            let clone = runGit(["clone", "--quiet", "--filter=blob:none", "--", src, dir.path], timeout: networkTimeout)
            guard clone.ok else { return ("\(spec.name): clone failed: \(clone.error)", false) }
        } else if !isClone(dir) {
            return ("\(spec.name): \(LuaError.shortenPaths(dir.path)) exists but is not a git clone Locky made; move it away or rename the plugin", false)
        }

        // init.lua may have changed the source since the clone.
        var fetched = false
        let origin = self.origin(dir)
        if origin != src {
            guard runGit(["-C", dir.path, "remote", "set-url", "origin", "--", src]).ok else {
                return ("\(spec.name): cannot point it at \(src)", false)
            }
            guard fetch(dir) else { return ("\(spec.name): fetch from \(src) failed", false) }
            fetched = true
        }

        let pinned = lockfile.plugins[spec.name].flatMap { $0.src == src && $0.version == spec.version ? $0.rev : nil }
        let locked = pinned.flatMap { Self.isRevision($0) ? $0 : nil }
        let before = runGit(["-C", dir.path, "rev-parse", "HEAD"]).output
        if !fetched, update || (locked != nil && !hasCommit(locked!, in: dir)) {
            guard fetch(dir) else { return ("\(spec.name): fetch failed", false) }
            fetched = true
        }
        let target: String
        if let locked, !update {
            target = locked
        } else if let version = spec.version {
            // A branch follows origin; a tag or commit is used as it is. A version made after the clone
            // needs a fetch first.
            if !fetched, !hasCommit("origin/\(version)", in: dir), !hasCommit(version, in: dir) {
                guard fetch(dir) else { return ("\(spec.name): fetch failed", false) }
            }
            target = hasCommit("origin/\(version)", in: dir) ? "origin/\(version)" : version
        } else {
            target = "origin/HEAD"
        }
        let checkout = runGit(["-C", dir.path, "checkout", "--quiet", "--detach", "--end-of-options", target])
        guard checkout.ok else { return ("\(spec.name): cannot check out \(target): \(checkout.error)", false) }
        let rev = runGit(["-C", dir.path, "rev-parse", "HEAD"]).output
        lockfile.plugins[spec.name] = Lockfile.Entry(src: src, rev: rev, version: spec.version)
        if fresh { return ("installed \(spec.name) at \(rev.prefix(7))", true) }
        if before != rev {
            return ((["updated \(spec.name) \(before.prefix(7)) → \(rev.prefix(7))"] + changes(in: dir, from: before, to: rev)).joined(separator: "\n"), true)
        }
        return ("\(spec.name) is up to date (\(rev.prefix(7)))", true)
    }

    /// Fetches a package the lockfile pins and finds the commit `update` would move it to, with the commits and the
    /// diffstat between, without moving it.
    private func check(_ name: String, locked: Lockfile.Entry) -> PackUpdate {
        let dir = path.packs.appending(path: name)
        guard isClone(dir) else { return PackUpdate(name: name) }
        var result = PackUpdate(name: name, current: locked.rev)
        // The clone still fetches from another source; sync moves it to the locked one.
        guard origin(dir) == locked.src else {
            result.error = "its source is now \(locked.src); run `locky pack sync`"
            return result
        }
        guard fetch(dir) else {
            result.error = "fetch failed"
            return result
        }
        // As update resolves it: a branch follows origin; a tag or a commit is used as it is.
        let target = locked.version.map { hasCommit("origin/\($0)", in: dir) ? "origin/\($0)" : $0 } ?? "origin/HEAD"
        let latest = runGit(["-C", dir.path, "rev-parse", "--verify", "--quiet", "--end-of-options", "\(target)^{commit}"])
        guard latest.ok else {
            result.error = "cannot find \(locked.version ?? "the default branch") upstream"
            return result
        }
        result.latest = latest.output
        if latest.output != locked.rev { result.changes = changes(in: dir, from: locked.rev, to: latest.output) }
        return result
    }

    /// The commits from `old` to `new`, one line each, and the diffstat, indented. A commit message may hold
    /// terminal escapes: control characters are dropped.
    private func changes(in dir: URL, from old: String, to new: String) -> [String] {
        guard Self.isRevision(old), Self.isRevision(new) else { return [] }
        let log = runGit(["-C", dir.path, "log", "--oneline", "--no-decorate", "--end-of-options", "\(old)..\(new)"]).output
        let stat = runGit(["-C", dir.path, "diff", "--stat", "--end-of-options", old, new], timeout: networkTimeout).output
        let clean = { (line: Substring) in "  " + String(String.UnicodeScalarView(line.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })) }
        return (log.split(separator: "\n") + stat.split(separator: "\n")).map(clean)
    }

    /// The source the clone fetches from, as its config says it, without url.<base>.insteadOf applied.
    private func origin(_ dir: URL) -> String {
        runGit(["-C", dir.path, "config", "--get", "remote.origin.url"]).output
    }

    /// Fetches tags and branches, drops branches deleted upstream, and follows a renamed default branch.
    private func fetch(_ dir: URL) -> Bool {
        guard runGit(["-C", dir.path, "fetch", "--quiet", "--tags", "--force", "--prune", "origin"], timeout: networkTimeout).ok else {
            return false
        }
        _ = runGit(["-C", dir.path, "remote", "set-head", "origin", "--auto"], timeout: networkTimeout)
        return true
    }

    private func hasCommit(_ ref: String, in dir: URL) -> Bool {
        runGit(["-C", dir.path, "rev-parse", "--verify", "--quiet", "--end-of-options", "\(ref)^{commit}"]).ok
    }

    /// What locky.pack.add accepts as a name: letters, digits, "_", "-", and ".", never "." or "..".
    static func isPackageName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_-.".contains($0)) }
    }

    /// A full commit id: what a lockfile may pin. Anything else is ignored, so an edited lockfile cannot
    /// pass git an option.
    static func isRevision(_ value: String) -> Bool {
        (value.count == 40 || value.count == 64) && value.allSatisfy(\.isHexDigit)
    }

    /// Not private: the tests call it.
    func runGit(_ arguments: [String], timeout: Double = 30) -> (ok: Bool, output: String, error: String) {
        // Process raises an Objective-C exception for a NUL inside an argument, which would end the app (and a
        // lock with it), and cuts the argument short at a NUL at its end.
        guard !arguments.contains(where: { $0.contains("\0") }) else {
            return (false, "", "a git argument contains a NUL byte")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        // Give up on a connection that stalls, instead of waiting forever.
        // Never plain http or git://, not even through a redirect from https.
        process.arguments = ["-c", "http.lowSpeedLimit=1000", "-c", "http.lowSpeedTime=30", "-c", "core.askPass=",
                             "-c", "protocol.http.allow=never", "-c", "protocol.git.allow=never"]
            + gitConfig.flatMap { ["-c", $0] } + arguments
        var environment = ProcessInfo.processInfo.environment
        // Never wait for a password nobody will type, in a terminal or a helper.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = ""
        environment["SSH_ASKPASS"] = ""
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=15"
        // Never look above the pack folder for a repository: a folder without .git must not make git act on
        // an enclosing one, such as a dotfiles repository in the home folder.
        environment["GIT_CEILING_DIRECTORIES"] = path.packs.path
        process.environment = environment
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (false, "", "cannot run git: \(error.localizedDescription)")
        }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        // Read both pipes at once: a full stderr pipe would otherwise stall git and this read forever. On a thread
        // of its own: callers block a thread of Swift's pool, and with enough of them blocked, a block queued on a
        // global queue may never start.
        nonisolated(unsafe) var errors = Data()
        let stderrDone = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            errors = err.fileHandleForReading.readDataToEndOfFile()
            stderrDone.signal()
        }
        let output = out.fileHandleForReading.readDataToEndOfFile()
        stderrDone.wait()
        process.waitUntilExit()
        deadline.cancel()
        let trim = { (data: Data) in String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        if process.terminationReason == .uncaughtSignal {
            return (false, trim(output), "git took longer than \(Int(timeout)) s and was stopped")
        }
        return (process.terminationStatus == 0, trim(output), trim(errors))
    }
}

/// What `locky pack check` found for one package from git.
struct PackUpdate: Equatable {
    var name: String
    /// The locked commit; nil when the package is not installed or not locked.
    var current: String?
    /// The commit its version (or the default branch) names upstream, after a fetch.
    var latest: String?
    /// Why the check failed.
    var error: String?
    /// For an update: its commits, one line each, then its diffstat, indented.
    var changes: [String] = []

    /// "name: up to date", "name: update available abc1234 → def5678", "name: not installed", or the error.
    var line: String {
        if let error { return "\(name): \(error)" }
        guard let current, let latest else { return "\(name): not installed" }
        return current == latest ? "\(name): up to date" : "\(name): update available \(current.prefix(7)) → \(latest.prefix(7))"
    }
}

/// An exclusive lock on a file, held while a package run works. nil only when another run holds it: a
/// lock file that cannot be created does not block the run.
private final class FolderLock {
    private let descriptor: Int32

    init?(_ url: URL) {
        descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        if descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            return nil
        }
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
