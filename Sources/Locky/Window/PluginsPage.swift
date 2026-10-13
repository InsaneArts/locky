import AppKit
import SwiftUI

/// Plugins: the ones added here (settings.json), the ones init.lua adds, and the built-in theme packages,
/// each with what it provides. Install clones from git and pins the commit, like `locky pack sync`.
struct PluginsPage: View {
    @Bindable var model: AppModel
    @State private var installing = false
    @State private var removing: Inspection.PackInfo?
    /// The plugins Remove Unused would delete, while its confirmation shows.
    @State private var unused: [String]?
    @State private var reviewing = false

    private var packs: [Inspection.PackInfo] { model.inspection.packs }

    var body: some View {
        Form {
            Text("A plugin adds themes and widgets.")
                .foregroundStyle(.secondary)
            if let running = model.packRunning {
                Section {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(Self.progress(running))
                    }
                }
            } else if let last = model.packReport {
                Section {
                    DisclosureGroup {
                        Text(last.report.text.isEmpty ? "Nothing to do." : last.report.text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label(last.report.ok ? "\(Self.done(last.action))" : "\(Self.done(last.action)) with problems",
                              systemImage: last.report.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(last.report.ok ? Color.green : Color.orange)
                    }
                }
            }
            Section {
                let added = packs.filter(\.fromSettings)
                if added.isEmpty {
                    Text("No plugins yet. Install one from a git repository: “user/repo” on GitHub, or an https or ssh address.")
                        .foregroundStyle(.secondary)
                }
                ForEach(added) { pack in
                    PluginRow(model: model, pack: pack, removable: true) { removing = pack }
                }
            } header: {
                Text("Installed Here")
            }
            if packs.contains(where: { !$0.fromSettings }) {
                Section {
                    ForEach(packs.filter { !$0.fromSettings }) { pack in
                        PluginRow(model: model, pack: pack, removable: false) {}
                    }
                } header: {
                    Text("From init.lua")
                } footer: {
                    Text("init.lua adds these with locky.pack.add. Change them there.")
                }
            }
            Section {
                BuiltInRow(model: model, folder: RuntimePath.builtInRuntime, title: "Core")
                ForEach(RuntimePath.builtInPackages, id: \.self) { folder in
                    BuiltInRow(model: model, folder: folder, title: Provides.themeNames(model: model, folder: folder) ?? folder.lastPathComponent)
                }
            } header: {
                Text("Built In")
            }
        }
        .formStyle(.grouped)
        .scrollingPageWidth()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Check for Updates", systemImage: "arrow.clockwise") { model.checkForUpdates() }
                    .help(model.lastUpdateCheck.map { "Last checked \($0.formatted(.relative(presentation: .named)))" } ?? "Fetch every plugin and compare it with the pinned commit")
                Button("Update All…", systemImage: "arrow.down.circle") { model.checkForUpdates { reviewing = true } }
                    .help("See what each plugin's newest version changes, then install it")
                Button("Install Plugin…", systemImage: "plus") { installing = true }
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Remove Unused…") { unused = unusedPlugins() }
                        .help("Delete installed plugins that neither init.lua nor this window adds")
                }
                .menuIndicator(.hidden)
            }
        }
        .disabled(model.packRunning != nil)
        .sheet(isPresented: $installing) { InstallSheet(model: model) }
        .sheet(isPresented: $reviewing) { UpdateSheet(model: model) }
        .confirmationDialog(unused?.isEmpty == false ? "Remove unused plugins?" : "No unused plugins",
                            isPresented: Binding(get: { unused != nil }, set: { if !$0 { unused = nil } }), presenting: unused) { names in
            if !names.isEmpty {
                Button("Remove", role: .destructive) { model.runPack(.clean, work: { $0.run(.clean, removing: names) }) }
            }
        } message: { names in
            Text(names.isEmpty ? "Every installed plugin is in use."
                 : "Locky deletes these folders in \(LuaError.shortenPaths(RuntimePath.defaultPacks.path)):\n" + names.joined(separator: "\n"))
        }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { pack in
            Button("Remove", role: .destructive) { remove(pack) }
        } message: { pack in
            Text(pack.alsoInConfig ? "init.lua also adds it, so it stays installed." : "Locky deletes its folder and stops using its themes and widgets.")
        }
    }

    private func remove(_ pack: Inspection.PackInfo) {
        model.store.update { settings in
            settings.packs.removeAll { PackSpec.name(of: $0)?.lowercased() == pack.name.lowercased() }
        }
        if !pack.alsoInConfig { model.runPack(.clean, work: { $0.run(.clean, removing: [pack.name]) }) }
    }

    /// The installed plugins that neither init.lua nor this window adds: what Remove Unused deletes.
    private func unusedPlugins() -> [String] {
        let path = RuntimePath.standard(config: model.store.config)
        let specs = packs.map { PackManager.Spec(name: $0.name, src: $0.src, dir: $0.dir?.path) }
        let lockfile = (try? PackManager.readLockfile(path.lockfile)) ?? PackManager.Lockfile()
        return PackManager(path: path).unused(specs, lockfile: lockfile)
            .filter { FileManager.default.fileExists(atPath: path.packs.appending(path: $0).path) }
    }

    static func progress(_ action: PackManager.Action) -> String {
        switch action {
        case .sync: "Installing…"
        case .update: "Updating plugins…"
        case .clean: "Removing unused plugins…"
        case .check: "Checking for updates…"
        default: "Working…"
        }
    }

    static func done(_ action: PackManager.Action) -> String {
        switch action {
        case .sync: "Installed"
        case .update: "Updated"
        case .clean: "Removed unused plugins"
        case .check: "Checked for updates"
        default: "Done"
        }
    }
}

private struct PluginRow: View {
    let model: AppModel
    let pack: Inspection.PackInfo
    let removable: Bool
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pack.dir == nil ? "shippingbox.fill" : "folder.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background((pack.installed ? Color.blue : Color.gray).gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(pack.name).font(.body.weight(.semibold))
                }
                Text(source).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(Provides.text(model: model, folder: pack.folder)).font(.callout).foregroundStyle(.secondary)
                if pack.dir == nil {
                    HStack(spacing: 14) {
                        grant("system", "Run programs")
                        grant("files", "Change files")
                    }
                    .controlSize(.small)
                    .disabled(!removable)
                    .help(removable ? "What this plugin may do besides reading your files" : "Set allow = { ... } in its locky.pack.add entry in init.lua")
                }
            }
            Spacer(minLength: 0)
            if !pack.installed, pack.dir == nil {
                Button("Install") { model.runPack(.sync) }
            }
            Menu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([pack.folder]) }
                    .disabled(!pack.installed)
                if let src = pack.src, let url = URL(string: src), url.scheme?.hasPrefix("http") == true {
                    Button("Open Repository") { NSWorkspace.shared.open(url) }
                }
                if removable {
                    Divider()
                    Button("Remove…", role: .destructive, action: remove)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 3)
    }

    /// A checkbox for one capability, written to the plugin's settings.json entry.
    private func grant(_ capability: String, _ title: String) -> some View {
        Toggle(title, isOn: Binding(get: { pack.allow.contains(capability) }, set: { allowed in
            model.store.update { settings in
                settings.packs = settings.packs.map { spec in
                    PackSpec.name(of: spec)?.lowercased() == pack.name.lowercased() ? PackSpec.allowing(capability, allowed, in: spec) : spec
                }
            }
        }))
        .toggleStyle(.checkbox)
    }

    private var source: String {
        if let dir = pack.dir { return LuaError.shortenPaths(dir.path) }
        var text = pack.src ?? "?"
        if let version = pack.version { text += " @ \(version)" }
        if let commit = pack.commit { text += " · \(commit.prefix(7))" }
        return text
    }
}

private struct BuiltInRow: View {
    let model: AppModel
    let folder: URL
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 48, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(Provides.text(model: model, folder: folder)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 1)
    }

    /// The plugin's first theme as it looks, like an app's icon in a list; a symbol for one without themes.
    @ViewBuilder private var icon: some View {
        let root = folder.resolvingSymlinksInPath().path + "/"
        if let theme = model.inspection.themes.first(where: { ($0.directory?.resolvingSymlinksInPath().path ?? "").appending("/").hasPrefix(root) }),
           let image = ThemeThumbnails.image(for: theme) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.gradient)
        }
    }
}

/// "Themes: Mocha · Widgets: mocha.clock, mocha.bar": what a plugin folder provides.
enum Provides {
    /// The display names of the themes in `folder`, such as "Mocha", or nil when it has none.
    @MainActor
    static func themeNames(model: AppModel, folder: URL) -> String? {
        let root = folder.resolvingSymlinksInPath().path + "/"
        let names = model.inspection.themes.filter { ($0.directory?.resolvingSymlinksInPath().path ?? "").appending("/").hasPrefix(root) }.map(\.name)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    @MainActor
    static func text(model: AppModel, folder: URL) -> String {
        let root = folder.resolvingSymlinksInPath().path + "/"
        let themes = model.inspection.themes.filter { ($0.directory?.resolvingSymlinksInPath().path ?? "").appending("/").hasPrefix(root) }
        let widgets = model.inspection.widgets.filter { ($0.file?.resolvingSymlinksInPath().path ?? "").hasPrefix(root) }
        var parts: [String] = []
        if !themes.isEmpty { parts.append("Themes: " + themes.map(\.name).joined(separator: ", ")) }
        if !widgets.isEmpty { parts.append("Widgets: " + widgets.map(\.name).joined(separator: ", ")) }
        return parts.isEmpty ? "No themes or widgets yet" : parts.joined(separator: " · ")
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

struct InstallSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""
    @State private var version = ""

    private var problem: String? { PackSpec.problem(source: source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install a Plugin").font(.title3.weight(.semibold))
            Text("A plugin adds themes and widgets. Locky clones it with git into ~/.local/share/locky/pack and pins the commit in locky-pack-lock.json, next to init.lua.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Repository", text: $source, prompt: Text("user/repo or https://…"))
                TextField("Version", text: $version, prompt: Text("Optional: a tag, branch, or commit"))
            }
            .formStyle(.columns)
            if !source.isEmpty, let problem {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout)
            }
            Label("A plugin runs as you and can read your files. It runs programs or changes files only if you allow it on this page. Install plugins from people you trust.", systemImage: "hand.raised")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Install") { install() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: 480)
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

/// What Update All installs, before it does: each plugin's new commits and diffstat, from the check that just ran.
/// Update installs exactly those commits.
struct UpdateSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Kept from when the sheet opened: a check that runs meanwhile must not change what Update installs.
    @State private var updates: [PackUpdate] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(updates.isEmpty ? "Every Plugin Is Up to Date" : "Update Plugins").font(.title3.weight(.semibold))
            if !updates.isEmpty {
                Text("Read what changes before you install it. A plugin runs as you.")
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(updates, id: \.name) { update in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(update.name)  \(update.current?.prefix(7) ?? "") → \(update.latest?.prefix(7) ?? "")")
                                    .font(.body.weight(.semibold))
                                Text(update.changes.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 360)
            }
            HStack {
                Spacer()
                if updates.isEmpty {
                    Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Update") {
                        model.applyUpdates(updates)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { updates = model.available }
    }
}
