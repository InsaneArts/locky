import AppKit
import Foundation

/// The Locky window's state: which page shows, settings.json, and what booting Lua says about the config.
@MainActor @Observable
final class AppModel {
    enum Section: String, CaseIterable, Identifiable {
        case dashboard, themes, widgets, plugins, config, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .themes: "Themes"
            case .widgets: "Widgets"
            case .plugins: "Plugins"
            case .config: "Config"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .dashboard: "square.grid.2x2"
            case .themes: "paintpalette"
            case .widgets: "square.on.square"
            case .plugins: "puzzlepiece.extension"
            case .config: "curlybraces"
            case .settings: "gearshape"
            }
        }
    }

    var section: Section = .dashboard
    /// Opened behind other windows for screenshots: previews keep running although hidden.
    var screenshots = false
    /// The theme the Themes page shows.
    var selectedTheme: String?
    let store: SettingsStore
    private(set) var inspection = Inspection()
    /// Bumped whenever the config folder or settings.json changes: views that read files read them again.
    private(set) var revision = 0

    /// A package run in progress, and the last one's report.
    private(set) var packRunning: PackManager.Action?
    private(set) var packReport: (action: PackManager.Action, report: PackManager.Report)?
    /// The last update check's results, and when it ran.
    private(set) var updates: [PackUpdate] = []
    private(set) var lastUpdateCheck: Date?
    /// Packages with a newer commit upstream than the one pinned.
    var available: [PackUpdate] { updates.filter { $0.error == nil && $0.current != nil && $0.latest != nil && $0.current != $0.latest } }

    /// The editors and terminals on this Mac, found once when the Config page first needs them.
    private(set) var editors: (editors: [Editor], terminals: [Terminal])?

    /// Why the Lock Now shortcut could not be registered, such as another app holding it.
    var shortcutProblem: String?

    /// What the window asks the app to do.
    @ObservationIgnored var lockNow: () -> Void = {}
    /// Settings records a new shortcut (true) or stops (false).
    @ObservationIgnored var recordingShortcut: (Bool) -> Void = { _ in }
    @ObservationIgnored var preview: (_ theme: String?) -> Void = { _ in }

    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var watchers: [FolderWatcher] = []

    init(store: SettingsStore) {
        self.store = store
    }

    /// The theme a lock uses now: the schedule's, else settings.json's, else init.lua's.
    var activeTheme: String {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return store.settings.schedule?.theme(at: Date(), dark: dark) ?? inspection.config["theme"].string ?? store.settings["theme"].string ?? "default"
    }

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
            if selectedTheme == nil || result.theme(selectedTheme!) == nil { selectedTheme = activeTheme }
        }
    }

    /// Runs `locky pack <action>` (or `work`, which reports as `action`) in the background, one run at a time, then
    /// reads the config again, unless it was a check: that changes nothing, and reading the config runs plugin code.
    func runPack(_ action: PackManager.Action, work: (@Sendable (PackManager) -> PackManager.Report)? = nil,
                 then done: ((PackManager.Report) -> Void)? = nil) {
        guard packRunning == nil else { return }
        packRunning = action
        let config = store.config
        Task {
            let report = await Task.detached {
                let manager = PackManager(path: .standard(config: config))
                return work?(manager) ?? manager.run(action)
            }.value
            packRunning = nil
            packReport = (action, report)
            // What was checked no longer holds: Update All brought every plugin up to date, and a removed one has
            // no update. A new check gives the rest again.
            switch action {
            case .update where report.ok: updates = []
            case .clean: updates.removeAll { !FileManager.default.fileExists(atPath: RuntimePath.defaultPacks.appending(path: $0.name).path) }
            default: break
            }
            if action != .check { refresh() }
            done?(report)
        }
    }

    /// Moves each plugin to the commit the user reviewed in `updates`.
    func applyUpdates(_ updates: [PackUpdate]) {
        runPack(.update, work: { $0.apply(updates) })
    }

    /// Fetches every plugin the lockfile pins and compares it with the pinned commit; changes nothing and runs no Lua.
    func checkForUpdates(then done: (() -> Void)? = nil) {
        runPack(.check, then: { [weak self] report in
            self?.updates = report.updates
            self?.lastUpdateCheck = Date()
            done?()
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
