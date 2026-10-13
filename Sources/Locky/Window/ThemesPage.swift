import AppKit
import SwiftUI

/// The Themes window's page: the gallery, or Customize for the theme `model.editingTheme` names. In Customize the live
/// preview is a canvas where widgets are clicked to change them and dragged to move them, and the panel beside it
/// changes what is selected. Changes save to settings.json at once and the preview follows.
struct ThemesPage: View {
    @Bindable var model: AppModel
    /// The theme being edited; a new one per theme, so one theme's layout is never saved as another's.
    @State private var editing: ThemeEditing?
    @State private var selection: EditorItem?
    /// settings.json with a change still being made, such as a slider being dragged: the preview shows it first.
    @State private var draft: Settings?
    @AppStorage("themeEditorGrid") private var grid = false
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if let id = model.editingTheme, let info = model.inspection.theme(id) {
            editor(info)
                .navigationTitle(info.name)
        } else if model.editingTheme != nil {
            // Read before it shows: a theme just duplicated or imported, or the first read of the config.
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Themes")
        } else {
            ThemeGallery(model: model)
                .navigationTitle("Themes")
        }
    }

    private func editor(_ info: Inspection.ThemeInfo) -> some View {
        HStack(spacing: 0) {
            stage(info)
            Divider()
            Group {
                if let editing, editing.theme.id == info.id {
                    ThemeEditor(model: model, editing: editing, selection: $selection, draft: $draft)
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
    }

    private func stage(_ info: Inspection.ThemeInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = info.error {
                ContentUnavailableView("This Theme Does Not Load", systemImage: "exclamationmark.triangle", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ThemePreview(theme: info.id, settings: draft ?? model.store.settings, sources: model.inspection.sources,
                             config: model.store.config, alwaysLive: model.screenshots, canvas: canvas(for: info), info: info)
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
        .sheet(isPresented: Binding(get: { model.addingWidget }, set: { model.addingWidget = $0 })) {
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
            Button("Add Widget…", systemImage: "plus") { model.addingWidget = true }
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
