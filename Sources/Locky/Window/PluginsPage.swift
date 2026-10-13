import AppKit
import SwiftUI

/// Plugins: the ones added here (settings.json), the ones init.lua adds, and the built-in theme packages,
/// each with what it provides. Install clones from git and pins the commit, like `locky pack sync`.
struct PluginsPage: View {
    @Bindable var model: AppModel
    @State private var installing = false
    @State private var removing: Inspection.PackInfo?

    private var packs: [Inspection.PackInfo] { model.inspection.packs }

    var body: some View {
        Form {
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
                    Text("No plugins yet. Install one from a git repository: “user/repo” on GitHub, or any git URL.")
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
                    BuiltInRow(model: model, folder: folder, title: folder.lastPathComponent)
                }
            } header: {
                Text("Built In")
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Remove Unused", systemImage: "trash") { model.runPack(.clean) }
                    .help("Delete installed plugins that neither init.lua nor this window adds")
                Button("Check for Updates", systemImage: "arrow.clockwise") { model.checkForUpdates() }
                    .help(model.lastUpdateCheck.map { "Last checked \($0.formatted(.relative(presentation: .named)))" } ?? "Fetch every plugin and compare it with the pinned commit")
                Button("Update All", systemImage: "arrow.down.circle") { model.runPack(.update) }
                    .help("Fetch every plugin's newest version and pin it")
                Button("Install Plugin…", systemImage: "plus") { installing = true }
            }
        }
        .disabled(model.packRunning != nil)
        .sheet(isPresented: $installing) { InstallSheet(model: model) }
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
        if !pack.alsoInConfig { model.runPack(.clean) }
    }

    static func progress(_ action: PackManager.Action) -> String {
        switch action {
        case .sync: "Installing…"
        case .update: "Updating every plugin…"
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
                    if !pack.installed { Tag("Not Installed", color: .orange) }
                    if let update = model.available.first(where: { $0.name == pack.name }), let latest = update.latest {
                        Tag("Update: \(latest.prefix(7))", color: .blue)
                    }
                    if pack.dir != nil { Tag("Local", color: .purple) }
                    if pack.alsoInConfig { Tag("Also in init.lua", color: .secondary) }
                }
                Text(source).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(Provides.text(model: model, folder: pack.folder)).font(.callout).foregroundStyle(.secondary)
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
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(Provides.text(model: model, folder: folder)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 1)
    }
}

/// "Themes: Mocha · Widgets: mocha.clock, mocha.bar": what a package folder provides.
enum Provides {
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

    /// Why `text` is not a source locky.pack.add takes, or nil when it is.
    static func problem(source text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return "Enter a repository." }
        if value.hasPrefix("-") { return "A source cannot start with “-”." }
        if value.contains(where: \.isWhitespace) { return "A source has no spaces." }
        let shorthand = value.range(of: #"^[\w.-]+/[\w.-]+$"#, options: .regularExpression) != nil
        let url = value.hasPrefix("https://") || value.hasPrefix("git@") || value.hasPrefix("ssh://") || value.hasPrefix("file://")
        return shorthand || url ? nil : "Use “user/repo” for GitHub, or a git URL."
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
            Text("Locky clones it with git into ~/.local/share/locky/pack and pins the commit in locky-pack-lock.json, next to init.lua.")
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
            Label("A plugin runs Lua code on your lock screen. Install plugins from people you trust.", systemImage: "hand.raised")
                .font(.callout)
                .foregroundStyle(.secondary)
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
