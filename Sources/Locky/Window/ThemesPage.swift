import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Every theme as a card, and the selected one in the editor: its live preview is a canvas where widgets are
/// clicked to change them and dragged to move them, and the panel beside it changes what is selected. Changes save to
/// settings.json at once and the preview follows.
struct ThemesPage: View {
    @Bindable var model: AppModel
    /// The theme being edited; a new one per theme, so one theme's layout is never saved as another's.
    @State private var editing: ThemeEditing?
    @State private var selection: EditorItem?
    /// settings.json with a change still being made, such as a slider being dragged: the preview shows it first.
    @State private var draft: Settings?
    @AppStorage("themeEditorGrid") private var grid = false

    var body: some View {
        VStack(spacing: 0) {
            strip
            Divider()
            if let id = model.selectedTheme, let info = model.inspection.theme(id) {
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
                    .frame(width: 340)
                }
                // Read again when Lua files change: init.lua may give the theme other widgets or options.
                .task(id: "\(info.id)-\(model.inspection.sources)") {
                    let next = ThemeEditing(theme: info, model: model)
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

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(model.inspection.themes) { info in
                        Button { model.selectedTheme = info.id } label: {
                            ThemeCard(info: info, selected: info.id == model.selectedTheme, active: info.id == model.activeTheme)
                        }
                        .buttonStyle(.plain)
                        .id(info.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.never)
            // The selected card in view: after the page opens on a theme, or the list loads.
            .onChange(of: model.inspection.themes.count, initial: true) { proxy.scrollTo(model.selectedTheme, anchor: .center) }
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
                HStack(spacing: 12) {
                    Toggle(isOn: $grid) { Label("Grid", systemImage: "grid") }
                        .toggleStyle(.button)
                        .help("Show a grid, and snap what you drag to its lines")
                    Text(selection == nil ? "Click a widget to change it, and drag it to move it."
                         : "Drag it to move it. Click outside it to see the whole theme.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Preview", systemImage: "play.rectangle") { model.preview(info.id) }
                    .help("Show this theme full size in a window")
            }
            ToolbarItem(placement: .primaryAction) {
                if info.id == model.activeTheme {
                    Label("In Use", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                        .help("Locky locks with this theme")
                } else {
                    Button("Use This Theme") { model.store.update { $0["theme"] = .string(info.id) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(info.error != nil)
                        .help("Lock with this theme from now on")
                }
            }
        }
    }

    /// The editor's canvas over the preview, once the theme's layout is in: what is selected, the grid, and where
    /// clicks and drags go.
    private func canvas(for info: Inspection.ThemeInfo) -> ThemePreview.Canvas? {
        guard let editing, editing.theme.id == info.id, editing.layout != nil else { return nil }
        return ThemePreview.Canvas(selection: selection, grid: grid, name: { editing.name(of: $0) }, select: { selection = $0 },
                                   move: { editing.move($0, anchor: $1, offset: $2) })
    }
}

/// A theme's thumbnail (its preview image, or its palette) and name.
private struct ThemeCard: View {
    let info: Inspection.ThemeInfo
    let selected: Bool
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
                .frame(width: 168, height: 105)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .font(.system(size: 17))
                            .padding(6)
                    }
                }
            Text(info.name)
                .font(.callout.weight(selected ? .semibold : .regular))
                .lineLimit(1)
        }
        .frame(width: 168)
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
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(color("fg", "#ffffff"))
                Circle().fill(color("accent", "#0a84ff")).frame(width: 8).offset(y: 30)
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

/// A small colored label, such as "In Use".
struct Tag: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}
