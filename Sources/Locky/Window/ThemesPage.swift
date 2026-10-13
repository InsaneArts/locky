import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Every theme in a list to search, and the selected one in the editor: its live preview is a canvas where widgets
/// are clicked to change them and dragged to move them, and the panel beside it changes what is selected. Changes
/// save to settings.json at once and the preview follows.
struct ThemesPage: View {
    @Bindable var model: AppModel
    /// The theme being edited; a new one per theme, so one theme's layout is never saved as another's.
    @State private var editing: ThemeEditing?
    @State private var selection: EditorItem?
    /// settings.json with a change still being made, such as a slider being dragged: the preview shows it first.
    @State private var draft: Settings?
    @AppStorage("themeEditorGrid") private var grid = false
    @Environment(\.undoManager) private var undoManager
    @State private var search = ""
    @State private var adding = false
    /// A theme file Import Theme read, until the import is confirmed.
    @State private var importing: ThemeFile?
    @State private var problem: (title: String, message: String)?

    var body: some View {
        HStack(spacing: 0) {
            list
            Divider()
            if let id = model.selectedTheme, let info = model.inspection.theme(id) {
                HStack(spacing: 0) {
                    stage(info)
                    Divider()
                    Group {
                        if let editing, editing.theme.id == info.id {
                            ThemeEditor(model: model, editing: editing, selection: $selection, draft: $draft, adding: $adding)
                        } else {
                            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: 300)
                }
                // Read again when Lua files change: init.lua may give the theme other widgets or options.
                .task(id: "\(info.id)-\(model.inspection.sources)") {
                    let next = ThemeEditing(theme: info, model: model)
                    next.undoManager = undoManager
                    await next.load()
                    // A newer load replaced this one.
                    guard !Task.isCancelled else { return }
                    editing = next
                }
                .onChange(of: info.id) {
                    selection = nil
                    draft = nil
                }
                // A change in progress belongs to what was selected.
                .onChange(of: selection) { draft = nil }
            } else {
                ContentUnavailableView(model.inspection.loaded ? "No Themes" : "Loading Themes…", systemImage: "paintpalette")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The themes whose name, id, or description has the search text.
    private var shown: [Inspection.ThemeInfo] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.inspection.themes }
        return model.inspection.themes.filter { info in
            [info.name, info.id, info.description ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $search, prompt: Text("Search Themes"))
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(shown) { info in
                            Button { model.selectedTheme = info.id } label: {
                                ThemeRow(info: info, selected: info.id == model.selectedTheme, active: info.id == model.activeTheme)
                            }
                            .buttonStyle(.plain)
                            .id(info.id)
                        }
                    }
                    .padding(6)
                }
                // The selected theme in view: after the page opens on it, the list loads, or a search ends.
                .onChange(of: shown.count, initial: true) { proxy.scrollTo(model.selectedTheme, anchor: .center) }
                .onChange(of: model.selectedTheme) { proxy.scrollTo(model.selectedTheme) }
            }
            Divider()
            Button("Import Theme…", systemImage: "square.and.arrow.down", action: chooseImport)
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .help("Add a theme someone exported from Locky")
        }
        .frame(width: 190)
        .alert(importing.map { "Import “\($0.name)”?" } ?? "", isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } })) {
            Button("Import") { if let importing { install(importing) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let importing {
                Text("""
                It is made from \(model.inspection.theme(importing.base)?.name ?? importing.base), with its own changes. A theme \
                is a Lua file, which could run code: Locky imports only themes made with Export Theme…, and writes the \
                file again from the settings it holds, so no code from it runs.
                """)
            }
        }
        .alert(problem?.title ?? "", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") {}
        } message: {
            Text(problem?.message ?? "")
        }
    }

    /// Reads a theme file the user picks; the import waits for their yes.
    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [ThemeFile.type]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= ThemeFile.maxSize, let text = try? String(contentsOf: url, encoding: .utf8), let file = ThemeFile.parse(text) else {
            problem = ("Can't Import This File", """
            Locky imports themes made with Export Theme…. A theme written in Lua goes in \
            \(LuaError.shortenPaths(model.store.config.path))/themes/ instead; see docs/themes.md.
            """)
            return
        }
        guard ThemeFile.isBuiltIn(file.base) else {
            problem = ("Can't Import This Theme", "It is made from “\(file.base)”, which is not one of Locky's themes.")
            return
        }
        let foreign = file.foreignWidgets(model.inspection.widgets)
        guard foreign.isEmpty else {
            problem = ("Can't Import This Theme", """
            It uses widgets that do not come with Locky: \(foreign.joined(separator: ", ")). A theme file sets a widget's \
            options, and a plugin's widget could run them as commands, so Locky imports only themes with its own widgets.
            """)
            return
        }
        importing = file
    }

    /// Adds the theme to the config's themes folder, and opens it in the editor.
    private func install(_ file: ThemeFile) {
        let id = ThemeFile.id(for: file.name, taken: ThemeFile.takenIDs(model.inspection.themes, settings: model.store.settings, config: model.store.config))
        Task {
            do {
                try await file.install(as: id, config: model.store.config)
                model.selectedTheme = id
                model.refresh()
            } catch {
                problem = ("Can't Import This Theme", (error as? LuaError)?.message ?? error.localizedDescription)
            }
        }
    }

    private func stage(_ info: Inspection.ThemeInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = info.error {
                ContentUnavailableView("This Theme Does Not Load", systemImage: "exclamationmark.triangle", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ThemePreview(theme: info.id, settings: draft ?? model.store.settings, sources: model.inspection.sources,
                             config: model.store.config, alwaysLive: model.screenshots, canvas: canvas(for: info))
                    .aspectRatio(1.6, contentMode: .fit)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Icons alone where the labels do not fit, as in a narrow window.
                ViewThatFits(in: .horizontal) {
                    tools.labelStyle(.titleAndIcon)
                    tools.labelStyle(.iconOnly)
                }
                Text(selection == nil ? "Click a widget to change it, and drag it to move it."
                     : "Drag it, or press the arrow keys, to move it. Delete removes a widget.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Preview", systemImage: "play.rectangle") { model.preview(info.id) }
                    .help("Show this theme full size in a window")
            }
        }
        .sheet(isPresented: $adding) {
            WidgetGallerySheet(model: model, theme: info) { name, family in
                if let editing { selection = .widget(editing.add(name, family: family)) }
            }
        }
    }

    /// The canvas's buttons: the grid, Add Widget, and the password field, which has no row of its own to click.
    private var tools: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $grid) { Label("Grid", systemImage: "grid") }
                .toggleStyle(.button)
                .help("Show a grid, and snap what you drag to its lines")
            Button("Add Widget…", systemImage: "plus") { adding = true }
                .help("Add a widget to this theme")
            Button("Password Field", systemImage: "character.cursor.ibeam") { selection = .passwordField }
                .help("Select the password field, to move it")
            Spacer(minLength: 0)
        }
        .disabled(editing?.layout == nil)
    }

    /// The editor's canvas over the preview, once the theme's layout is in: what is selected, the grid, and where
    /// clicks and drags go.
    private func canvas(for info: Inspection.ThemeInfo) -> ThemePreview.Canvas? {
        guard let editing, editing.theme.id == info.id, editing.layout != nil else { return nil }
        return ThemePreview.Canvas(selection: selection, grid: grid, name: { editing.name(of: $0) }, select: { selection = $0 },
                                   move: { editing.move($0, anchor: $1, offset: $2) },
                                   nudge: { editing.nudge($0, by: $1, byGrid: $2) },
                                   remove: { index in
                                       draft = nil
                                       selection = nil
                                       editing.remove(index)
                                   })
    }
}

/// A theme in the list: its thumbnail (its preview image, or its palette), its name, and whether a lock uses it.
private struct ThemeRow: View {
    let info: Inspection.ThemeInfo
    let selected: Bool
    let active: Bool

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: 64, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(info.name)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                if active {
                    Text("In Use").font(.caption).foregroundStyle(.green)
                } else if info.error != nil {
                    Text("Does not load").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .background(selected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = ThemeThumbnails.image(for: info) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            let color = { (role: String, fallback: String) in Color(hex: info.palette[role] ?? fallback) ?? .black }
            ZStack {
                LinearGradient(colors: [color("bg", "#000000"), color("surface", "#1c1c1e")], startPoint: .top, endPoint: .bottom)
                Text("12:00")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(color("fg", "#ffffff"))
                Circle().fill(color("accent", "#0a84ff")).frame(width: 4).offset(y: 11)
            }
        }
    }
}

/// Theme thumbnails: a theme's own preview.png or preview.jpg, else the one Locky ships for a built-in theme.
@MainActor
enum ThemeThumbnails {
    private static var cache: [String: NSImage?] = [:]

    static func image(for info: Inspection.ThemeInfo) -> NSImage? {
        if let cached = cache[info.id] { return cached }
        var candidates: [URL] = []
        if let directory = info.directory {
            candidates += ["preview.png", "preview.jpg"].map { directory.appending(path: $0) }
        }
        candidates += ["png", "jpg"].map { RuntimePath.resources.appending(path: "thumbnails/\(info.id).\($0)") }
        let image = candidates.lazy.compactMap { NSImage(contentsOf: $0) }.first
        cache[info.id] = image
        return image
    }
}
