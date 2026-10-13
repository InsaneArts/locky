import AppKit
import SwiftUI

/// Every widget, live, for the window's pictures of them: one Lua runtime runs the default theme with each widget
/// placed once in each of its families (once at its own size without any), and each card draws the family it
/// shows. It runs while a gallery shows.
@MainActor @Observable
final class WidgetGallery {
    private(set) var style = LockyStyle()
    private(set) var cardRadius = 22.0
    /// Each placement's instance and card style, by key (see `key`).
    private var instances: [String: (id: Int, card: String?)] = [:]
    private var nodes: [Int: Node] = [:]
    private var errors: [Int: String] = [:]
    @ObservationIgnored private var runtime: LuaRuntime?
    @ObservationIgnored private var running: [String] = []

    static func key(_ widget: String, _ family: String?) -> String { "\(widget)#\(family ?? "")" }

    /// Starts again when the widget list or the config changes; nothing happens when it is the same.
    func start(widgets: [Inspection.WidgetInfo], settings: Settings, config: URL, revision: Int) {
        let placements = widgets.flatMap { widget in
            widget.families.isEmpty ? [(widget.name, String?.none)] : widget.families.map { (widget.name, Optional($0)) }
        }
        let key = placements.map { Self.key($0.0, $0.1) } + [String(revision)]
        guard key != running else { return }
        stop()
        running = key
        var settings = settings
        // A plain background: the gallery draws its own behind each card.
        settings.setThemeEdit("default", "background", .table(["color": .string("#000000")]))
        settings.setThemeEdit("default", "widgets", .array(placements.map { name, family in
            var entry: [String: LuaValue] = ["widget": .string(name)]
            if let family { entry["family"] = .string(family) }
            return .table(entry)
        }))
        let runtime = LuaRuntime(path: .standard(config: config), settings: settings, delegate: LuaRuntime.Delegate(
            present: { [weak self] id, node in Task { @MainActor in self?.nodes[id] = node; self?.errors[id] = nil } },
            failed: { [weak self] id, message, _ in Task { @MainActor in self?.errors[id] = message } }
        ))
        self.runtime = runtime
        Task {
            let started = await runtime.start(theme: "default")
            guard self.runtime === runtime else { return }
            style = LockyStyle(palette: started.theme.palette, font: started.theme.font, scale: 1, hour24: started.hour24)
            cardRadius = started.theme.card.radius
            var list: [String: (Int, String?)] = [:]
            for (placement, id) in zip(started.theme.widgets, started.instances) {
                let key = Self.key(placement.widget, placement.family)
                if let id, list[key] == nil { list[key] = (id, placement.card) }
            }
            instances = list
        }
    }

    func stop() {
        runtime?.stop()
        runtime = nil
        running = []
        instances = [:]
        nodes = [:]
        errors = [:]
    }

    enum Shown {
        case loading
        case node(Node, card: String?)
        case empty
        case failed(String)
    }

    func shown(_ widget: String, family: String? = nil) -> Shown {
        guard let instance = instances[Self.key(widget, family)] else {
            return runtime == nil || instances.isEmpty ? .loading : .failed("Did not start")
        }
        if let error = errors[instance.id] { return .failed(error) }
        if let node = nodes[instance.id] { return .node(node, card: instance.card) }
        return .empty
    }
}

/// A widget's picture: its live view in one family, on a desktop-like background, scaled down to fit.
struct WidgetPicture: View {
    let gallery: WidgetGallery
    let widget: String
    var family: String?

    /// A deep blue, like macOS's own desktop pictures, so glass cards read as they do on a lock screen.
    static let backdrop = LinearGradient(
        colors: [Color(red: 0.16, green: 0.24, blue: 0.48), Color(red: 0.09, green: 0.10, blue: 0.27), Color(red: 0.20, green: 0.10, blue: 0.30)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        ZStack {
            Self.backdrop
            switch gallery.shown(widget, family: family) {
            case .loading:
                ProgressView().controlSize(.small)
            case .node(let node, let card):
                let size = family.flatMap(WidgetChrome<EmptyView>.size)
                Fitted {
                    WidgetChrome(card: card.map { Theme.Card(style: $0, radius: gallery.cardRadius) }, family: family, fills: size != nil) {
                        NodeView(node: node)
                    }
                    .frame(width: size?.width, height: size?.height)
                }
                .padding(18)
                .environment(\.lockyStyle, gallery.style)
                .foregroundStyle(gallery.style.color("fg"))
            case .empty:
                Text("Shows nothing until it is set up").font(.caption).foregroundStyle(.white.opacity(0.6))
            case .failed:
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.white.opacity(0.5))
            }
        }
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// Content at its own size, scaled down to fit the space it gets, never up.
private struct Fitted<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var size = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let scale = size.width > 0 && size.height > 0 ? min(1, proxy.size.width / size.width, proxy.size.height / size.height) : 1
            content
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// Add Widget: every widget, live, to add to `theme`.
struct WidgetGallerySheet: View {
    let model: AppModel
    /// The theme being customized, which the widget goes to.
    let theme: Inspection.ThemeInfo
    let add: (_ widget: String, _ family: String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var gallery = WidgetGallery()

    private var shown: [Inspection.WidgetInfo] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return model.inspection.widgets }
        return model.inspection.widgets.filter { $0.name.lowercased().contains(query) || ($0.description ?? "").lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add a Widget").font(.headline)
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
            }
            .padding(16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: .sectionHeaders) {
                    ForEach(WidgetGroup.groups(shown)) { group in
                        Section {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18)], spacing: 22) {
                                ForEach(group.widgets) { widget in
                                    WidgetCard(gallery: gallery, widget: widget) { family in
                                        add(widget.name, family)
                                        dismiss()
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        } header: {
                            Text(group.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 6)
                                .background(.bar)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            Divider()
            HStack {
                Text("Click a widget to add it at the center. Drag it where you want it.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 940, height: 700)
        .task(id: model.revision) {
            gallery.start(widgets: model.inspection.widgets, settings: model.store.settings, config: model.store.config, revision: model.revision)
        }
        .onDisappear { gallery.stop() }
    }
}

/// A widget in a gallery, as in macOS's widget gallery: its live picture in the size picked below it, its name,
/// and what it shows. A click on the picture adds the widget in that size.
struct WidgetCard: View {
    let gallery: WidgetGallery
    let widget: Inspection.WidgetInfo
    /// Where it comes from, under the name; the Locky group leaves it out, since every one there is built in.
    var showsSource = true
    let add: (_ family: String?) -> Void
    @State private var family: String?
    @State private var hovered = false

    /// The family a card shows first: small, as Apple's galleries do, else the first the widget has.
    static func first(_ widget: Inspection.WidgetInfo) -> String? {
        widget.families.contains("small") ? "small" : widget.families.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { add(family) } label: {
                WidgetPicture(gallery: gallery, widget: widget.name, family: family)
                    .frame(height: 210)
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .font(.system(size: 22))
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                            .padding(8)
                            .opacity(hovered ? 1 : 0)
                    }
                    .scaleEffect(hovered ? 1.01 : 1)
                    .shadow(color: .black.opacity(hovered ? 0.22 : 0.1), radius: hovered ? 10 : 4, y: hovered ? 4 : 2)
            }
            .buttonStyle(.plain)
            .onHover { inside in withAnimation(.smooth(duration: 0.18)) { hovered = inside } }
            .help("Add \(EditorPlacement.title(widget.name))\(family.map { " (\(FamilyPicker.name($0)))" } ?? "")")
            if widget.families.count > 1 {
                FamilyPicker(families: widget.families, selection: $family)
                    .frame(maxWidth: .infinity)
            } else {
                // The picker's height, so the cards in a row line up.
                Color.clear.frame(height: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(EditorPlacement.title(widget.name)).font(.headline).lineLimit(1)
                Text(widget.description ?? (showsSource ? widget.source ?? "" : ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, 2)
        }
        .onAppear { if family == nil { family = Self.first(widget) } }
    }
}

/// Apple's widget sizes as a row of small outlines in each size's proportions, the picked one filled.
struct FamilyPicker: View {
    let families: [String]
    @Binding var selection: String?

    static func name(_ family: String) -> String {
        switch family {
        case "circular": "Circular"
        case "rectangular": "Rectangular"
        case "inline": "Inline"
        case "small": "Small"
        case "medium": "Medium"
        case "large": "Large"
        default: family.capitalized
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(families, id: \.self) { family in
                Button { withAnimation(.smooth(duration: 0.2)) { selection = family } } label: {
                    glyph(family, picked: selection == family)
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Self.name(family))
                .accessibilityLabel(Self.name(family))
                .accessibilityAddTraits(selection == family ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }

    @ViewBuilder private func glyph(_ family: String, picked: Bool) -> some View {
        let color = picked ? Color.accentColor : Color.secondary
        let shape: AnyShape = switch family {
        case "circular": AnyShape(Circle())
        case "inline": AnyShape(Capsule())
        default: AnyShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
        }
        let size: CGSize = switch family {
        case "circular": CGSize(width: 11, height: 11)
        case "rectangular": CGSize(width: 15, height: 8)
        case "inline": CGSize(width: 15, height: 3)
        case "small": CGSize(width: 10, height: 10)
        case "medium": CGSize(width: 16, height: 9)
        default: CGSize(width: 13, height: 14)
        }
        ZStack {
            if picked {
                Capsule().fill(Color.accentColor.opacity(0.16))
            }
            shape.fill(color.opacity(picked ? 0.9 : 0)).overlay(shape.stroke(color, lineWidth: 1.4))
                .frame(width: size.width, height: size.height)
        }
    }
}

/// Widgets grouped by where they come from: Locky's own, the user's config, installed plugins, then each built-in
/// theme's.
struct WidgetGroup: Identifiable {
    var id: String { title }
    var title: String
    var widgets: [Inspection.WidgetInfo]

    static func groups(_ widgets: [Inspection.WidgetInfo]) -> [WidgetGroup] {
        let packages = RuntimePath.resources.appending(path: "packages").path + "/"
        var core: [Inspection.WidgetInfo] = [], config: [Inspection.WidgetInfo] = [], installed: [Inspection.WidgetInfo] = []
        var themes: [String: [Inspection.WidgetInfo]] = [:]
        for widget in widgets {
            let path = widget.file?.path ?? ""
            if path.hasPrefix(RuntimePath.builtInRuntime.path) { core.append(widget) }
            else if path.hasPrefix(RuntimePath.defaultConfig.path) { config.append(widget) }
            else if path.hasPrefix(packages) { themes[folder(of: path), default: []].append(widget) }
            else { installed.append(widget) }
        }
        var list = [WidgetGroup(title: "Locky", widgets: core), WidgetGroup(title: "Your Config", widgets: config),
                    WidgetGroup(title: "Installed", widgets: installed)]
        for name in themes.keys.sorted() {
            list.append(WidgetGroup(title: "\(EditorPlacement.title(name)) Theme", widgets: themes[name]!))
        }
        return list.filter { !$0.widgets.isEmpty }
    }

    /// The package a widget file is in: the folder before its plugin folder, else the short path.
    private static func folder(of path: String) -> String {
        let parts = path.split(separator: "/")
        if let plugin = parts.lastIndex(of: "plugin"), plugin > 0 { return String(parts[plugin - 1]) }
        return LuaError.shortenPaths(path)
    }
}
