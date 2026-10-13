import AppKit
import SwiftUI

/// Every widget Locky has, live: its own, the user's config's, installed plugins', and each theme's. A click on a
/// card adds the widget to a theme. Install adds a plugin from git, as on the Plugins page.
struct WidgetsPage: View {
    @Bindable var model: AppModel
    @State private var gallery = WidgetGallery()
    @State private var search = ""
    @State private var installing = false

    private var shown: [Inspection.WidgetInfo] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return model.inspection.widgets }
        return model.inspection.widgets.filter { $0.name.lowercased().contains(query) || ($0.description ?? "").lowercased().contains(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                Text("Click a widget to add it to a theme. Install Plugin… adds more.")
                    .foregroundStyle(.secondary)
                ForEach(WidgetGroup.groups(shown)) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.title).font(.title3.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 22)], spacing: 26) {
                            ForEach(group.widgets) { widget in
                                WidgetCard(gallery: gallery, widget: widget, showsSource: group.title != "Locky") { family in
                                    AddToTheme.menu(widget.name, family: family, model: model)
                                }
                                    .contextMenu {
                                        if let file = widget.file {
                                            Button("Open in Editor") { model.open(file) }
                                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search Widgets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Install Plugin…", systemImage: "plus") { installing = true }
                    .disabled(model.packRunning != nil)
            }
        }
        .sheet(isPresented: $installing) { InstallSheet(model: model) }
        .task(id: model.revision) {
            gallery.start(widgets: model.inspection.widgets, settings: model.store.settings, config: model.store.config, revision: model.revision)
        }
        .onDisappear { gallery.stop() }
    }
}

/// A click on a widget card: a menu to add the widget to the active theme, or, under Add to, to another one.
@MainActor
enum AddToTheme {
    static func menu(_ widget: String, family: String? = nil, model: AppModel) {
        let themes = model.inspection.themes.filter { $0.error == nil }
        let menu = NSMenu()
        if let active = themes.first(where: { $0.id == model.activeTheme }) {
            menu.addItem(ActionItem("Add to \(active.name)") { Task { await add(widget, family: family, to: active, model: model) } })
        }
        let others = NSMenu()
        for theme in themes where theme.id != model.activeTheme {
            others.addItem(ActionItem(theme.name) { Task { await add(widget, family: family, to: theme, model: model) } })
        }
        let item = NSMenuItem(title: "Add to", action: nil, keyEquivalent: "")
        item.submenu = others
        menu.addItem(item)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Adds the widget to `theme` as the theme editor's Add Widget does (settings.json's themes.<id>.widgets), then
    /// shows that theme on the Themes page. Returns the widget's place in the list, or nil when the theme's layout
    /// does not load.
    @discardableResult
    static func add(_ widget: String, family: String? = nil, to theme: Inspection.ThemeInfo, model: AppModel) async -> Int? {
        let editing = ThemeEditing(theme: theme, model: model)
        await editing.load()
        guard editing.layout != nil else { return nil }
        let index = editing.add(widget, family: family)
        model.selectedTheme = theme.id
        model.section = .themes
        return index
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let action_: () -> Void

    init(_ title: String, _ action: @escaping () -> Void) {
        action_ = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { action_() }
}
