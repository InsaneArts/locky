import Foundation

/// The app's copy of settings.json. Every change saves at once, as in System Settings. An edit made in
/// another editor shows up here within a moment. While the file has an error, the store does not write it:
/// the window shows the error instead of replacing the file, and Locky goes on with the last settings that read
/// without one, even at launch, so a typo does not turn auto-lock off or the emergency quit back on.
@MainActor @Observable
final class SettingsStore {
    private(set) var settings: Settings
    /// Why settings.json could not be read or written, if it could not.
    private(set) var problem: String?
    let config: URL
    /// Where the last settings that read without an error are kept, outside the config folder (dotfiles do not
    /// carry it). nil keeps none, as in tests.
    let lastGood: URL?
    /// Called after the settings change, from the window or from the file.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var watchers: [FolderWatcher] = []

    static var defaultLastGood: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Locky/settings-last-good.json")
    }

    init(config: URL = RuntimePath.defaultConfig, lastGood: URL? = nil) {
        self.config = config
        self.lastGood = lastGood
        let (loaded, problem) = Settings.load(config: config)
        self.problem = problem
        if problem == nil {
            settings = loaded
        } else {
            settings = lastGood.map { Settings.load(file: $0).settings } ?? Settings()
        }
        if problem == nil { remember(loaded) }
    }

    /// Reloads when anything in the config folder changes, or in the folder a symlinked settings.json points
    /// into: an edit there changes nothing in the config folder.
    func watch() {
        var folders = [config]
        let target = Settings.url(config: config).resolvingSymlinksInPath().deletingLastPathComponent()
        if target.standardizedFileURL != config.standardizedFileURL { folders.append(target) }
        watchers = folders.compactMap { FolderWatcher($0) { [weak self] in self?.reload() } }
    }

    func reload() {
        let (loaded, problem) = Settings.load(config: config)
        self.problem = problem
        guard problem == nil, loaded != settings else { return }
        settings = loaded
        remember(loaded)
        onChange?()
    }

    /// Applies `change` to the file as it is now, and saves. Reading it first keeps an edit made elsewhere that no
    /// event reported (in a symlink's target, say), and never writes over a file with an error.
    func update(_ change: (inout Settings) -> Void) {
        let (current, problem) = Settings.load(config: config)
        self.problem = problem
        guard problem == nil else { return }
        var copy = current
        change(&copy)
        guard copy != current else {
            if current != settings {
                settings = current
                onChange?()
            }
            return
        }
        do {
            try copy.save(config: config)
            // Read back as JSON reads it (a whole 60.0 comes back as 60), so the next file event finds no change.
            let saved = Settings.load(config: config).settings
            settings = saved
            remember(saved)
            onChange?()
        } catch {
            self.problem = "Could not save \(LuaError.shortenPaths(Settings.url(config: config).path)): \(error.localizedDescription)"
        }
    }

    /// Moves the broken file aside (settings.json.broken-<time>) and writes the settings Locky has gone on with:
    /// the last ones that read without an error.
    func resetBrokenFile() throws {
        // The file a symlink points at, so the link, and the dotfiles behind it, stay.
        let url = Settings.url(config: config).resolvingSymlinksInPath()
        let aside = url.appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970))")
        try FileManager.default.moveItem(at: url, to: aside)
        try settings.save(file: url)
        problem = nil
        onChange?()
    }

    private func remember(_ settings: Settings) {
        guard let lastGood else { return }
        try? settings.save(file: lastGood)
    }

    /// The theme the menu picked before settings.json existed lived in UserDefaults; it moves here once.
    func migrateMenuTheme(_ defaults: UserDefaults = .standard) {
        guard let theme = defaults.string(forKey: "theme") else { return }
        if settings["theme"].isNil { update { $0["theme"] = .string(theme) } }
        if problem == nil { defaults.removeObject(forKey: "theme") }
    }
}

/// Calls `onChange` on the main thread soon after a file under `folder` is added, removed, replaced, or
/// written, in place or by an editor's atomic save. FSEvents, so a burst of events comes as one call.
@MainActor
final class FolderWatcher {
    private final class Handler {
        let onChange: @MainActor () -> Void
        init(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    }

    private let handler: Handler
    nonisolated(unsafe) private var stream: FSEventStreamRef?

    init?(_ folder: URL, onChange: @escaping @MainActor () -> Void) {
        handler = Handler(onChange)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(handler).toOpaque(), retain: nil, release: nil,
                                           copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let handler = Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { handler.onChange() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags) else { return nil }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
