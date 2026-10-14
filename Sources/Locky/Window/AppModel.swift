import AppKit
import Foundation

/// The windows' state: the theme open in Customize, settings.json, and what booting Lua says about the config.
@MainActor @Observable
final class AppModel {
    /// A window, or a pane of the Settings window.
    enum Section: String, CaseIterable, Identifiable {
        /// The Themes window.
        case themes
        /// The Settings window's panes: General, Plugins, Lua Config.
        case settings, plugins, config
        /// The Welcome window.
        case welcome

        static let panes: [Section] = [.settings, .plugins, .config]

        /// A `Locky window` argument. The old names keep working.
        init?(argument: String) {
            switch argument {
            case "dashboard", "widgets": self = .themes
            default: self.init(rawValue: argument)
            }
        }

        var id: String { rawValue }

        var title: String {
            switch self {
            case .themes: "Themes"
            case .settings: "General"
            case .plugins: "Plugins"
            case .config: "Lua Config"
            case .welcome: "Welcome to Locky"
            }
        }

        var symbol: String {
            switch self {
            case .themes: "paintpalette"
            case .settings: "gearshape"
            case .plugins: "puzzlepiece.extension"
            case .config: "curlybraces"
            case .welcome: "hand.wave"
            }
        }
    }

    /// Opened behind other windows for screenshots: previews keep running although hidden.
    var screenshots = false
    /// The theme open in Customize; nil shows the gallery.
    private(set) var editingTheme: String?
    /// Add Widget's sheet: the Customize toolbar, Edit › Add Widget…, and `Locky window widgets` ask for it. It reads false
    /// for the length of a lock, so the sheet never comes up behind the lock screen; one asked for before the lock comes
    /// back after it.
    var addingWidget: Bool {
        get { askedForAddWidget && !locked }
        set { askedForAddWidget = newValue }
    }
    private var askedForAddWidget = false
    /// File › Import Theme… asks the gallery to show the file importer.
    var importing = false
    /// A Customize command from the main menu that needs the editor; the editor runs it and sets this back to nil.
    enum EditorRequest: Equatable { case duplicate, export, revert }
    var editorRequest: EditorRequest?
    let store: SettingsStore
    private(set) var inspection = Inspection()
    /// Bumped whenever the config folder or settings.json changes: views that read files read them again.
    private(set) var revision = 0

    /// A package run in progress, and the last one's report.
    private(set) var packRunning: PackManager.Action?
    private(set) var packReport: (action: PackManager.Action, report: PackManager.Report)?
    /// The plugins a run in progress works on, so each row knows its own spinner.
    private(set) var packTargets: Set<String> = []
    /// The last update check's results, and when it ran. A check that failed as a whole reached no plugin: it leaves no
    /// time, so nothing says when it ran or that the plugins are up to date.
    private(set) var updates: [PackUpdate] = []
    private(set) var lastUpdateCheck: Date?
    /// Packages with a newer commit upstream than the one pinned.
    var available: [PackUpdate] { updates.filter { $0.error == nil && $0.current != nil && $0.latest != nil && $0.current != $0.latest } }

    /// The editors and terminals on this Mac, found once when the Config page first needs them.
    private(set) var editors: (editors: [Editor], terminals: [Terminal])?

    /// Why the Lock Now shortcut could not be registered, such as another app holding it.
    var shortcutProblem: String?
    /// Open at login, read again whenever Locky becomes active (back from System Settings).
    private(set) var loginItem = LoginItem.status
    /// True for the length of a lock (AppDelegate sets it). Nothing is read on didBecomeActive then.
    var locked = false

    /// What the window asks the app to do.
    @ObservationIgnored var lockNow: () -> Void = {}
    /// Settings records a new shortcut (true) or stops (false).
    @ObservationIgnored var recordingShortcut: (Bool) -> Void = { _ in }
    @ObservationIgnored var preview: (_ theme: String?) -> Void = { _ in }
    /// Opens a window or a Settings pane (AppDelegate sets it): the gallery's "Open Settings" uses it.
    @ObservationIgnored var openWindow: (Section) -> Void = { _ in }

    /// A `customizeInUse` that waits for the first read of the config: whether it also opens Add Widget.
    @ObservationIgnored private var pendingCustomize: Bool?
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var watchers: [FolderWatcher] = []
    @ObservationIgnored nonisolated(unsafe) private var activation: NSObjectProtocol?

    init(store: SettingsStore) {
        self.store = store
        // A lock activates Locky at its start and at every keyboard reclaim: a slow answer about login items must not
        // hold the main thread then, which runs the guard's heartbeat.
        activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.locked else { return }
                self.loginItem = LoginItem.status
            }
        }
    }

    deinit {
        if let activation { NotificationCenter.default.removeObserver(activation) }
    }

    func setLoginItem(_ on: Bool) throws {
        defer { loginItem = LoginItem.status }
        try LoginItem.set(on)
    }

    /// Opens Customize for `id`, in place of a `customizeInUse` that still waits. Callers never animate it: Customize swaps
    /// at once from any input.
    func customize(_ id: String) {
        editingTheme = id
        pendingCustomize = nil
    }

    /// Ends Customize, and a `customizeInUse` that still waits, so the next open shows the gallery.
    func finishEditing() {
        editingTheme = nil
        addingWidget = false
        editorRequest = nil
        pendingCustomize = nil
    }

    /// Customize for the theme in use, with Add Widget open or not. It waits for the first read of the config: until then
    /// `activeTheme` cannot know init.lua's theme. `Locky window widgets` uses it.
    func customizeInUse(addingWidget: Bool) {
        guard inspection.loaded else {
            pendingCustomize = addingWidget
            return
        }
        customize(activeTheme)
        self.addingWidget = addingWidget
    }

    /// The theme a lock uses when no schedule picks one: settings.json's, else init.lua's, else Aurora.
    var usualTheme: String { store.settings["theme"].string ?? inspection.base["theme"].string ?? "default" }
    /// The theme a lock uses now. settings.json comes first, so a change shows on the frame it is made; the next read of
    /// the config agrees, since settings.json wins over init.lua there too.
    var activeTheme: String { store.settings.schedule?.theme(at: .now, dark: isDark) ?? usualTheme }

    /// Makes `id` the theme a lock uses now. Under a schedule whose current slot names a theme, that slot changes.
    /// Choosing init.lua's own theme stores no key, so the click is its own reset.
    func use(_ id: String) {
        let dark = isDark
        store.update { settings in
            if var schedule = settings.schedule, schedule.theme(at: .now, dark: dark) != nil {
                schedule.setTheme(id, at: .now, dark: dark)
                settings.schedule = schedule
            } else {
                settings.setLuaValue("theme", .string(id), base: inspection.base["theme"])
            }
        }
    }

    /// Whether Export Theme… can write a file for `id`: only a theme built on one of Locky's own loads on another Mac.
    func canExport(_ id: String) -> Bool {
        ThemeFile.isBuiltIn(ThemeFile.made(from: id, edit: store.settings["themes"][id], name: id, config: store.config).base)
    }

    /// Writes `file` to the config's themes folder under a free id, reads the config again, and returns the id. Duplicate
    /// and Import both use it.
    func install(_ file: ThemeFile) async throws -> String {
        let id = ThemeFile.id(for: file.name, taken: ThemeFile.takenIDs(inspection.themes, settings: store.settings, config: store.config))
        try await file.install(as: id, config: store.config)
        refresh()
        return id
    }

    /// Whether `id` is the person's own theme, which Move to Trash may take: a theme that the last read of the config
    /// lists, with a file in the config folder's themes/. A plugin can add any id to that list, so the id must also be a
    /// plain file name (no "/" and no leading "."): then it never leads out of themes/.
    func canTrash(_ id: String) -> Bool {
        !id.isEmpty && !id.contains("/") && !id.hasPrefix(".") && inspection.theme(id) != nil
            && FileManager.default.fileExists(atPath: ThemeFile.file(id, config: store.config).path)
    }

    /// Why Move to Trash left a theme where it was, in words for its alert.
    struct TrashError: LocalizedError {
        let errorDescription: String?
    }

    /// Moves the person's own theme to the Trash; the Trash is the undo. settings.json's theme, and a schedule slot, that
    /// named it go back to the usual theme. Its changes in settings.json's themes stay, so Put Back restores them.
    /// `remove` moves the file (tests pass one that deletes).
    func trash(_ id: String, using remove: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        guard canTrash(id) else { throw TrashError(errorDescription: "Only your own themes can move to the Trash.") }
        // Nothing can save settings.json while it has an error, so it would still name a theme that is gone.
        guard Settings.load(config: store.config).problem == nil else {
            throw TrashError(errorDescription: "settings.json has an error. Fix it in Settings › General first.")
        }
        try remove(ThemeFile.file(id, config: store.config))
        store.update { settings in
            if settings["theme"].string == id { settings["theme"] = .nil }
            // The typed schedule writes the whole table again, so it is written only when a slot named the theme.
            if let schedule = settings.schedule {
                var forgotten = schedule
                forgotten.forget(id)
                if forgotten != schedule { settings.schedule = forgotten }
            }
        }
        if editingTheme == id { finishEditing() }
        refresh()
    }

    private var isDark: Bool { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    /// Reads the config again in the background. A burst of calls (a save, then the file events it causes)
    /// reads once, after the burst; a call while a read runs folds into the next.
    func refresh() {
        refreshing?.cancel()
        let config = store.config
        refreshing = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            var result = await Inspection.load(config: config, settings: store.settings)
            guard !Task.isCancelled else { return }
            if let problem = store.problem { result.problems.insert(problem, at: 0) }
            inspection = result
            revision += 1
            // A customizeInUse waited for this read, and customize() ends the wait. During a lock nothing opens: the
            // refresh after the unlock runs it.
            if let adding = pendingCustomize, !locked {
                customize(activeTheme)
                addingWidget = adding
            }
            // The theme open in Customize does not exist, such as a file deleted in Finder.
            if let editingTheme, result.theme(editingTheme) == nil { finishEditing() }
        }
    }

    /// Runs `locky pack <action>` (or `work`, which reports as `action`) in the background, one run at a time, then
    /// reads the config again, unless it was a check: that changes nothing, and reading the config runs plugin code.
    /// `targets` names the plugins the run works on; none means all of them.
    func runPack(_ action: PackManager.Action, targets: Set<String> = [], work: (@Sendable (PackManager) -> PackManager.Report)? = nil,
                 then done: ((PackManager.Report) -> Void)? = nil) {
        guard packRunning == nil else { return }
        packRunning = action
        packTargets = targets
        let config = store.config
        Task {
            let report = await Self.run(action, config: config, work: work)
            packRunning = nil
            packTargets = []
            packReport = (action, report)
            // What was checked no longer holds: the plugins an update moved are up to date, and a removed one has
            // no update. A new check gives the rest again.
            switch action {
            case .update where report.ok: updates = Self.remaining(updates, after: targets)
            case .clean: updates.removeAll { !FileManager.default.fileExists(atPath: RuntimePath.defaultPacks.appending(path: $0.name).path) }
            default: break
            }
            if action != .check { refresh() }
            done?(report)
        }
    }

    /// The run itself, off the main actor: git and the file system take seconds.
    @concurrent nonisolated private static func run(_ action: PackManager.Action, config: URL,
                                                    work: (@Sendable (PackManager) -> PackManager.Report)?) async -> PackManager.Report {
        let manager = PackManager(path: .standard(config: config))
        return work?(manager) ?? manager.run(action)
    }

    /// The updates an update run leaves: none when it named no plugin (it updated them all), else the plugins it did not name.
    nonisolated static func remaining(_ updates: [PackUpdate], after targets: Set<String>) -> [PackUpdate] {
        targets.isEmpty ? [] : updates.filter { !targets.contains($0.name) }
    }

    /// Moves each plugin to the commit the user reviewed in `updates`.
    func applyUpdates(_ updates: [PackUpdate]) {
        runPack(.update, targets: Set(updates.map(\.name)), work: { $0.apply(updates) })
    }

    /// Fetches every plugin the lockfile pins and compares it with the pinned commit; changes nothing and runs no Lua.
    func checkForUpdates() {
        runPack(.check, then: { [weak self] report in
            self?.updates = report.updates
            self?.lastUpdateCheck = report.readLockfile ? Date() : nil
        })
    }

    func findEditors() async {
        guard editors == nil else { return }
        editors = await Editors.installed()
    }

    /// The editor settings.json names, else the app macOS opens .lua files with, else the first one found.
    var editor: Editor? {
        guard let list = editors?.editors else { return nil }
        return list.first { $0.id == store.settings["editor"].string } ?? list.first { $0.id == "default" } ?? list.first
    }

    /// The terminal for terminal editors: settings.json's, else Terminal.
    var terminal: Terminal? {
        guard let list = editors?.terminals else { return nil }
        return list.first { $0.id == store.settings["terminal"].string } ?? list.first { $0.id == "com.apple.Terminal" } ?? list.first
    }

    /// Opens `file` (at `line`) in the chosen editor; an error goes to the log and comes back.
    @discardableResult
    func open(_ file: URL, line: Int? = nil) -> String? {
        guard let editor else { return "No editor found" }
        do {
            try Editors.open(file, line: line, editor: editor, terminal: terminal)
            return nil
        } catch {
            LogFile.shared.write(level: "warn", message: "opening \(file.lastPathComponent) in \(editor.name): \(error.localizedDescription)", source: "editor")
            return error.localizedDescription
        }
    }

    /// While the window is open: follow init.lua, plugin, and package changes.
    func startWatching() {
        guard watchers.isEmpty else { return }
        watchers = [store.config, RuntimePath.defaultPacks].compactMap { FolderWatcher($0) { [weak self] in self?.refresh() } }
    }

    func stopWatching() {
        watchers = []
    }
}

extension String {
    /// "after 5 min idle" → "After 5 min idle".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
