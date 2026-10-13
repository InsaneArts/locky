import AppKit
import SwiftUI

/// Every widget Locky has, live: its own, the user's config's, installed plugins', and each theme's. Install adds a
/// plugin from git, as on the Plugins page.
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
                Text("Add a widget to a theme from the theme editor. Install more from a plugin's git repository.")
                    .foregroundStyle(.secondary)
                ForEach(WidgetGroup.groups(shown)) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.title).font(.title3.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 18)], spacing: 20) {
                            ForEach(group.widgets) { widget in
                                WidgetCard(gallery: gallery, widget: widget)
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
            gallery.start(widgets: model.inspection.widgets.map(\.name), settings: model.store.settings, config: model.store.config, revision: model.revision)
        }
        .onDisappear { gallery.stop() }
    }
}
