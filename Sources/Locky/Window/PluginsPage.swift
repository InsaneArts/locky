import AppKit
import SwiftUI

/// Settings › Plugins: the plugins settings.json and init.lua add, each with what it adds and what it may do. Install
/// clones from git and pins the commit, like `locky pack sync`; Update… installs exactly the commit it shows.
struct PluginsPage: View {
    let model: AppModel
    @State private var installing = false
    /// The update the Update sheet shows.
    @State private var reviewing: PackUpdate?
    /// The plugin the Remove alert asks about.
    @State private var removing: Inspection.PackInfo?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// settings.json's plugins in their order, then init.lua's.
    private var packs: [Inspection.PackInfo] {
        model.inspection.packs.filter(\.fromSettings) + model.inspection.packs.filter { !$0.fromSettings }
    }

    /// A run is in progress: the controls that start one wait. The grant switches stay live: a grant writes
    /// settings.json and cannot race git.
    private var isBusy: Bool { model.packRunning != nil }

    /// settings.json reads without an error. While it has one nothing saves to it and a sync cannot see its plugins, so
    /// every control that changes a plugin waits. Check Now changes nothing and stays.
    private var canChange: Bool { model.store.problem == nil }

    /// The last run, when it failed. Its section stays at the top until the next run.
    private var failedRun: (action: PackManager.Action, report: PackManager.Report)? {
        model.packReport.flatMap { $0.report.ok ? nil : $0 }
    }

    var body: some View {
        Group {
            if !model.inspection.loaded {
                // Until the config is read, so "No Plugins" never flashes.
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if packs.isEmpty, failedRun == nil, canChange {
                ContentUnavailableView {
                    Label("No Plugins", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("Plugins add themes and widgets from git repositories.")
                } actions: {
                    Button("Install Plugin…") { installing = true }
                        .disabled(isBusy)
                }
            } else {
                VStack(spacing: 0) {
                    form
                    Divider()
                    HStack {
                        Spacer()
                        Button("Install Plugin…") { installing = true }
                            .disabled(isBusy || !canChange)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
        .sheet(isPresented: $installing) { InstallSheet(model: model) }
        .sheet(item: $reviewing) { UpdateSheet(model: model, update: $0) }
        .alert(removing.map { "Remove “\($0.name)”?" } ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
               presenting: removing) { pack in
            Button("Cancel", role: .cancel) {}
            // Plain, not destructive: the person chose Remove… on purpose.
            Button("Remove") { remove(pack) }
                .keyboardShortcut(.defaultAction)
                // A run can start while the alert is open, such as the daily check.
                .disabled(isBusy || !canChange)
        } message: { pack in
            Text(Self.removal(pack))
        }
    }

    private var form: some View {
        Form {
            if !canChange {
                Section {
                    HStack(spacing: 8) {
                        WarningLabel("settings.json has an error, so plugins can't change.")
                        // General shows the error and restores the last good settings.
                        Button("Show General") { model.openWindow(.settings) }
                            .buttonStyle(.link)
                    }
                }
            }
            if let failedRun {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        WarningLabel(Self.failure(failedRun.action))
                            .font(.body.weight(.semibold))
                        Text(Self.failureReport(failedRun.action, failedRun.report))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                            .textSelection(.enabled)
                    }
                }
            }
            ForEach(packs) { pack in
                PluginSection(pack: pack, allow: allowed(pack), summary: Provides.summary(model: model, folder: pack.folder),
                              theme: Provides.themes(model: model, folder: pack.folder).first,
                              update: model.available.first { $0.name == pack.name }, isRunning: isRunning(pack), isBusy: isBusy,
                              canChange: canChange,
                              install: { model.runPack(.sync, targets: [pack.name]) }, review: { reviewing = $0 },
                              remove: { removing = pack }, grant: { grant($0, $1, to: pack) })
            }
            if packs.contains(where: { $0.dir == nil }) {
                Section {
                    // Its label dims itself, as the grant switches' do.
                    Toggle(isOn: model.store.bool("update_check", default: true)) {
                        Text("Check for updates daily").foregroundStyle(canChange ? HierarchicalShapeStyle.primary : .secondary)
                    }
                    .disabled(!canChange)
                } footer: {
                    updateStatus
                }
            }
        }
        .formStyle(.grouped)
        // A plugin or the failure coming or going fades and moves the rows below, so the row being watched does not jump.
        .animation(Motion.rows(reduceMotion), value: packs.map(\.name))
        .animation(Motion.rows(reduceMotion), value: failedRun != nil)
        .animation(Motion.rows(reduceMotion), value: canChange)
    }

    /// The update section's footer: what the last check this session found, and Check Now.
    private var updateStatus: some View {
        HStack(spacing: 8) {
            if model.packRunning == .check {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for updates…")
            } else if let checked = model.lastUpdateCheck {
                let upToDate = Self.upToDate(model.updates)
                TimelineView(.everyMinute) { _ in
                    Text(upToDate ? "Up to date · checked \(Self.ago(checked))" : "Checked \(Self.ago(checked))")
                }
            }
            Spacer(minLength: 8)
            Button("Check Now") { model.checkForUpdates() }
                .buttonStyle(.link)
                .disabled(isBusy)
        }
    }

    /// Whether every plugin the last check found is at its newest commit, also once Update… has installed the last one
    /// it found. A check that failed for one plugin never reads as up to date, whatever runs after it: its results stay
    /// until the next check. One that failed as a whole leaves no time (AppModel), so the footer says nothing of it.
    static func upToDate(_ updates: [PackUpdate]) -> Bool {
        updates.allSatisfy { $0.error == nil && $0.latest != nil && $0.current == $0.latest }
    }

    /// Whether a run works on `pack` now: the plugins it names, and for a sync, every git plugin not installed yet.
    private func isRunning(_ pack: Inspection.PackInfo) -> Bool {
        guard let running = model.packRunning else { return false }
        return model.packTargets.contains(pack.name) || (running == .sync && !pack.installed && pack.dir == nil)
    }

    /// What `pack` may do. For settings.json's, its entry as the file has it now: the config is read again only after
    /// a write, and a switch must not flip back until then.
    private func allowed(_ pack: Inspection.PackInfo) -> [String] {
        guard pack.fromSettings,
              let spec = model.store.settings.packs.first(where: { PackSpec.name(of: $0)?.lowercased() == pack.name.lowercased() })
        else { return pack.allow }
        return spec["allow"].array?.compactMap(\.string) ?? []
    }

    /// Writes one grant to the plugin's settings.json entry.
    private func grant(_ capability: String, _ allowed: Bool, to pack: Inspection.PackInfo) {
        model.store.update { settings in
            settings.packs = settings.packs.map { spec in
                PackSpec.name(of: spec)?.lowercased() == pack.name.lowercased() ? PackSpec.allowing(capability, allowed, in: spec) : spec
            }
        }
    }

    private func remove(_ pack: Inspection.PackInfo) {
        // runPack ignores a second run: the entry would go and the folder stay.
        guard model.packRunning == nil else { return }
        model.store.update { settings in
            settings.packs.removeAll { PackSpec.name(of: $0)?.lowercased() == pack.name.lowercased() }
        }
        // Nothing saves while settings.json has an error: the plugin stays in it, so its folder stays too.
        guard model.store.problem == nil, Self.deletesFolder(pack) else { return }
        let name = pack.name
        model.runPack(.clean, targets: [name], work: { $0.run(.clean, removing: [name]) })
    }

    /// Whether Remove deletes the plugin's folder: only a clone Locky made, and only when init.lua does not add the
    /// plugin too. A local folder is the person's own code: a clean could still match its name in the lockfile.
    static func deletesFolder(_ pack: Inspection.PackInfo) -> Bool { !pack.alsoInConfig && pack.dir == nil }

    /// The failure section's title for a run of `action`.
    static func failure(_ action: PackManager.Action) -> String {
        switch action {
        case .sync: "Couldn't install plugins"
        case .update: "Couldn't update plugins"
        case .clean: "Couldn't remove the plugin"
        case .check: "Couldn't check for updates"
        case .list: "Couldn't list plugins"
        }
    }

    /// The failure section's report. A check lists each plugin's commits and diffstat, which can push the plugin that
    /// failed below the 8 lines shown, so a failed check shows only the plugins it could not check.
    static func failureReport(_ action: PackManager.Action, _ report: PackManager.Report) -> String {
        let failed = action == .check ? report.updates.filter { $0.error != nil }.map(\.line) : []
        return failed.isEmpty ? report.text : failed.joined(separator: "\n")
    }

    /// Where a plugin comes from, for its row: "someone/locky-stars" on GitHub, the address on another host, the folder
    /// of a local one; then its pinned version, and "init.lua" for one init.lua adds.
    static func source(_ pack: Inspection.PackInfo) -> String {
        var parts: [String] = []
        if let dir = pack.dir {
            parts.append(LuaError.shortenPaths(dir.path))
        } else if let src = pack.src {
            let github = "https://github.com/"
            if src.hasPrefix(github) {
                let path = src.dropFirst(github.count)
                parts.append(String(path.hasSuffix(".git") ? path.dropLast(4) : path))
            } else {
                parts.append(src)
            }
        }
        if let version = pack.version { parts.append(version) }
        if !pack.fromSettings { parts.append("init.lua") }
        return parts.joined(separator: " · ")
    }

    /// The Remove alert's message: what happens to the folder, as `deletesFolder` decides it.
    static func removal(_ pack: Inspection.PackInfo) -> String {
        if pack.alsoInConfig { return "init.lua also adds it, so it stays installed." }
        return deletesFolder(pack) ? "Locky deletes its folder. Its themes and widgets stop showing."
            : "Locky keeps its folder. Its themes and widgets stop showing."
    }

    /// "just now" within a minute, else "2 minutes ago", in English like the rest of the window.
    private static func ago(_ date: Date) -> String {
        Date.now.timeIntervalSince(date) < 60 ? "just now"
            : date.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US")))
    }
}

/// One plugin: what it is and adds, its one action, its More menu, and for a git plugin what it may do beyond reading
/// files. It takes values, so another plugin's change leaves it as it is.
private struct PluginSection: View {
    let pack: Inspection.PackInfo
    /// What it may do: "system" (run programs) and "files" (change files).
    let allow: [String]
    /// "Widget: Stars Count", or nil when it adds nothing.
    let summary: String?
    /// Its first theme, whose thumbnail is its icon.
    let theme: Inspection.ThemeInfo?
    /// The new commit the last check found for it.
    let update: PackUpdate?
    /// A run works on it now: a spinner takes its button's place.
    let isRunning: Bool
    /// A run is in progress: the controls that start one wait.
    let isBusy: Bool
    /// False while settings.json has an error: nothing about the plugin can change, its grants included.
    let canChange: Bool
    let install: () -> Void
    let review: (PackUpdate) -> Void
    let remove: () -> Void
    let grant: (_ capability: String, _ allowed: Bool) -> Void

    /// Its grants can change: init.lua's plugins show the grants init.lua gives them, and nothing saves while
    /// settings.json has an error.
    private var canGrant: Bool { pack.fromSettings && canChange }

    var body: some View {
        Section {
            header
            // A local folder is the person's own code: it gets no grants.
            if pack.dir == nil {
                // A grouped form draws a disabled switch's label at full contrast, so the labels dim themselves.
                let title = canGrant ? HierarchicalShapeStyle.primary : .secondary
                Group {
                    Toggle(isOn: allows("system")) {
                        Text("Run programs").foregroundStyle(title)
                    }
                    Toggle(isOn: allows("files")) {
                        Text("Change files").foregroundStyle(title)
                        Text("Gives as much access as running programs.").foregroundStyle(canGrant ? HierarchicalShapeStyle.secondary : .tertiary)
                    }
                }
                .disabled(!canGrant)
                .help(pack.fromSettings ? "" : "Set allow = { … } for it in init.lua")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name)
                    .font(.headline)
                Text(PluginsPage.source(pack))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(pack.commit.map { "Pinned to commit \($0.prefix(7))" } ?? "")
                if pack.installed, let summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(summary)
                }
            }
            Spacer(minLength: 8)
            control
                .controlSize(.small)
            Menu { menuItems } label: { Image(systemName: "ellipsis") }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Show in Finder, open the repository, or remove")
                .accessibilityLabel("More")
        }
        .padding(.vertical, 2)
        .contextMenu { menuItems }
    }

    /// Its first theme's thumbnail, as an app's icon shows the app, else a puzzle piece. VoiceOver skips it: the name
    /// says it.
    private var icon: some View {
        Group {
            if let theme, let image = ThemeThumbnails.image(for: theme) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.gradient)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.thumbnail, style: .continuous))
        .hairline(cornerRadius: Design.Radius.thumbnail, lineWidth: 0.5)
        .accessibilityHidden(true)
    }

    /// The one control: a spinner while a run works on it, else Install, else Update… when a new commit waits.
    @ViewBuilder private var control: some View {
        if isRunning {
            ProgressView()
        } else if !pack.installed, pack.dir == nil {
            Button("Install", action: install)
                .disabled(isBusy || !canChange)
        } else if let update {
            Button("Update…") { review(update) }
                .disabled(isBusy || !canChange)
        }
    }

    /// The More menu's items, which a right-click on the row shows too.
    @ViewBuilder private var menuItems: some View {
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([pack.folder]) }
            .disabled(!pack.installed)
        if let src = pack.src, let url = URL(string: src), url.scheme?.hasPrefix("http") == true {
            Button("Open Repository") { NSWorkspace.shared.open(url) }
        }
        if pack.fromSettings {
            Divider()
            Button("Remove…", action: remove)
                .disabled(isBusy || !canChange)
        }
    }

    private func allows(_ capability: String) -> Binding<Bool> {
        Binding(get: { allow.contains(capability) }, set: { grant(capability, $0) })
    }
}

/// What a plugin folder adds, for its row.
@MainActor
enum Provides {
    /// The themes in `folder`.
    static func themes(model: AppModel, folder: URL) -> [Inspection.ThemeInfo] {
        let root = folder.resolvingSymlinksInPath().path + "/"
        return model.inspection.themes.filter { ($0.directory?.resolvingSymlinksInPath().path ?? "").appending("/").hasPrefix(root) }
    }

    /// "Themes: Stormy · Widgets: Stars Count, Stars Graph" in the names people read, with "Theme:" and "Widget:" for
    /// one; nil when `folder` adds nothing.
    static func summary(model: AppModel, folder: URL) -> String? {
        let root = folder.resolvingSymlinksInPath().path + "/"
        let themes = themes(model: model, folder: folder).map(\.name)
        let widgets = model.inspection.widgets.filter { ($0.file?.resolvingSymlinksInPath().path ?? "").hasPrefix(root) }
            .map { EditorPlacement.title($0.name) }
        var parts: [String] = []
        if !themes.isEmpty { parts.append((themes.count == 1 ? "Theme: " : "Themes: ") + themes.joined(separator: ", ")) }
        if !widgets.isEmpty { parts.append((widgets.count == 1 ? "Widget: " : "Widgets: ") + widgets.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Spec checks shared by the install sheet and removal: the same rules locky.pack.add applies.
enum PackSpec {
    /// The folder name a spec installs to, as locky.pack.add names it: its name, the last path part of its folder,
    /// or the last path part of its repository without a trailing ".git".
    static func name(of spec: LuaValue) -> String? {
        if let name = spec["name"].string { return name }
        if let dir = spec["dir"].string { return dir.split(separator: "/").last.map(String.init) }
        guard let source = spec.string ?? spec["src"].string, let last = source.split(separator: "/").last.map(String.init) else { return nil }
        return last.hasSuffix(".git") ? String(last.dropLast(4)) : last
    }

    /// `spec` with `capability` ("system" or "files") allowed or not. A "user/repo" spec becomes { src = ... }.
    static func allowing(_ capability: String, _ allowed: Bool, in spec: LuaValue) -> LuaValue {
        var table = spec.string.map { ["src": LuaValue.string($0)] } ?? spec.table ?? [:]
        var allow = table["allow"]?.array?.compactMap(\.string) ?? []
        allow.removeAll { $0 == capability }
        if allowed { allow.append(capability) }
        table["allow"] = allow.isEmpty ? nil : .array(allow.map(LuaValue.string))
        return .table(table)
    }

    /// Why `text` is not a source locky.pack.add takes, or nil when it is.
    static func problem(source text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return "Enter a repository." }
        if value.hasPrefix("-") { return "A source cannot start with “-”." }
        if value.contains(where: \.isWhitespace) { return "A source has no spaces." }
        let shorthand = value.range(of: #"^[\w.-]+/[\w.-]+$"#, options: .regularExpression) != nil
        let url = value.hasPrefix("https://") || value.hasPrefix("git@") || value.hasPrefix("ssh://")
        return shorthand || url ? nil : "Use “user/repo” for GitHub, or an https://, ssh://, or git@ address."
    }
}

/// Install Plugin: a repository, and a version if wanted. Install adds it to settings.json and clones it.
struct InstallSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""
    @State private var version = ""
    @FocusState private var focus: Field?

    enum Field { case source, version }

    private var problem: String? { PackSpec.problem(source: source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install Plugin").font(.headline)
            Form {
                TextField("Repository", text: $source, prompt: Text("someone/locky-weather"))
                    .focused($focus, equals: .source)
                TextField("Version", text: $version, prompt: Text("Latest"))
                    .focused($focus, equals: .version)
                    .help("A tag, branch, or commit")
            }
            .formStyle(.columns)
            // Once Repository is left, never while it is typed in.
            if !source.isEmpty, focus != .source, let problem {
                WarningLabel(problem)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("A plugin runs as you and can read your files. Install plugins only from people you trust.", systemImage: "hand.raised")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Install", action: install)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil || model.packRunning != nil || model.store.problem != nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .defaultFocus($focus, .source)
    }

    private func install() {
        let src = source.trimmingCharacters(in: .whitespaces)
        let pinned = version.trimmingCharacters(in: .whitespaces)
        let spec: LuaValue = pinned.isEmpty ? .string(src) : .table(["src": .string(src), "version": .string(pinned)])
        let name = PackSpec.name(of: spec)?.lowercased()
        model.store.update { settings in
            settings.packs.removeAll { PackSpec.name(of: $0)?.lowercased() == name }
            settings.packs.append(spec)
        }
        model.runPack(.sync)
        dismiss()
    }
}

/// Update: what one plugin's new commit changes, from the check that found it. Update installs exactly that commit.
struct UpdateSheet: View {
    let model: AppModel
    let update: PackUpdate
    @Environment(\.dismiss) private var dismiss
    /// The log's height, so the well fits it between 120 and 320 points.
    @State private var logHeight: CGFloat = 0

    /// The commits and the diffstat as git prints them, without the indent `locky pack check` adds.
    private var log: String {
        update.changes.map { $0.hasPrefix("  ") ? String($0.dropFirst(2)) : $0 }.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update \(update.name)").font(.headline)
            Text("\(update.current?.prefix(7) ?? "") → \(update.latest?.prefix(7) ?? "")")
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
            // Unwrapped, as git prints it for 80 columns: a long line scrolls sideways, so the diffstat keeps its columns.
            ScrollView([.vertical, .horizontal]) {
                Text(log)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { logHeight = $0 }
            }
            .defaultScrollAnchor(.topLeading)
            .frame(height: min(max(logHeight, 120), 320))
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Design.Radius.tile, style: .continuous))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Update") {
                    model.applyUpdates([update])
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.packRunning != nil)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

/// For `.sheet(item:)`: one plugin has one update.
extension PackUpdate: Identifiable {
    var id: String { name }
}
