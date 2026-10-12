import Foundation

/// The app's copy of settings.json. Every change saves at once, as in System Settings. An edit made in
/// another editor shows up here within a moment. While the file has an error, the store does not write it:
/// the window shows the error instead of replacing the file.
@MainActor @Observable
final class SettingsStore {
    private(set) var settings: Settings
    /// Why settings.json could not be read or written, if it could not.
    private(set) var problem: String?
    let config: URL
    /// Called after the settings change, from the window or from the file.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var watcher: FolderWatcher?

    init(config: URL = RuntimePath.defaultConfig) {
        self.config = config
        let (settings, problem) = Settings.load(config: config)
        self.settings = settings
        self.problem = problem
    }

    /// Reloads when anything in the config folder changes.
    func watch() {
        watcher = FolderWatcher(config) { [weak self] in self?.reload() }
    }

    func reload() {
        let (loaded, problem) = Settings.load(config: config)
        self.problem = problem
        guard problem == nil, loaded != settings else { return }
        settings = loaded
        onChange?()
    }

    /// Applies `change` and saves. Nothing is saved while the file has an error.
    func update(_ change: (inout Settings) -> Void) {
        guard problem == nil else { return }
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        do {
            try copy.save(config: config)
            settings = copy
            onChange?()
        } catch {
            problem = "Could not save \(LuaError.shortenPaths(Settings.url(config: config).path)): \(error.localizedDescription)"
        }
    }

    /// Moves the broken file aside (settings.json.broken-<time>) and starts from empty settings.
    func resetBrokenFile() throws {
        let url = Settings.url(config: config)
        let aside = url.appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970))")
        try FileManager.default.moveItem(at: url, to: aside)
        problem = nil
        settings = Settings()
        onChange?()
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
