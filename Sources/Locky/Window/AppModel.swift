import AppKit
import Foundation

/// The Locky window's state: which page shows, settings.json, and what booting Lua says about the config.
@MainActor @Observable
final class AppModel {
    enum Section: String, CaseIterable, Identifiable {
        case dashboard, themes, plugins, config, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .themes: "Themes"
            case .plugins: "Plugins"
            case .config: "Config"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .dashboard: "square.grid.2x2"
            case .themes: "paintpalette"
            case .plugins: "puzzlepiece.extension"
            case .config: "curlybraces"
            case .settings: "gearshape"
            }
        }
    }

    var section: Section = .dashboard
    /// The theme the Themes page shows.
    var selectedTheme: String?
    let store: SettingsStore
    private(set) var inspection = Inspection()
    /// Bumped whenever the config folder or settings.json changes: views that read files read them again.
    private(set) var revision = 0

    /// A package run in progress, and the last one's report.
    private(set) var packRunning: PackManager.Action?
    private(set) var packReport: (action: PackManager.Action, report: PackManager.Report)?

    /// What the window asks the app to do.
    @ObservationIgnored var lockNow: () -> Void = {}
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

    /// Reads the config again in the background. Calls that arrive while one runs fold into the next.
    func refresh() {
        refreshing?.cancel()
        let config = store.config
        refreshing = Task {
            let result = await Inspection.load(config: config)
            guard !Task.isCancelled else { return }
            inspection = result
            revision += 1
            if selectedTheme == nil || result.theme(selectedTheme!) == nil { selectedTheme = activeTheme }
        }
    }

    /// Runs `locky pack <action>` in the background, one run at a time, then reads the config again.
    func runPack(_ action: PackManager.Action, then done: ((PackManager.Report) -> Void)? = nil) {
        guard packRunning == nil else { return }
        packRunning = action
        let config = store.config
        Task {
            let report = await Task.detached { PackManager(path: .standard(config: config)).run(action) }.value
            packRunning = nil
            packReport = (action, report)
            refresh()
            done?(report)
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
