import AppKit
import SwiftUI

/// Every widget, live, for the window's pictures of them: one Lua runtime runs the default theme with each widget
/// placed once, and each card draws its widget's latest view. It runs while a gallery shows.
@MainActor @Observable
final class WidgetGallery {
    private(set) var style = LockyStyle()
    private(set) var cardRadius = 22.0
    /// Each widget's instance and card style, by name.
    private var instances: [String: (id: Int, card: String?)] = [:]
    private var nodes: [Int: Node] = [:]
    private var errors: [Int: String] = [:]
    @ObservationIgnored private var runtime: LuaRuntime?
    @ObservationIgnored private var running: [String] = []

    /// Starts again when the widget list or the config changes; nothing happens when it is the same.
    func start(widgets: [String], settings: Settings, config: URL, revision: Int) {
        let key = widgets + [String(revision)]
        guard key != running else { return }
        stop()
        running = key
        var settings = settings
        // A plain background: the gallery draws its own behind each card.
        settings.setThemeEdit("default", "background", .table(["color": .string("#000000")]))
        settings.setThemeEdit("default", "widgets", .array(widgets.map { .table(["widget": .string($0)]) }))
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
                if let id, list[placement.widget] == nil { list[placement.widget] = (id, placement.card) }
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

    func shown(_ widget: String) -> Shown {
        guard let instance = instances[widget] else { return runtime == nil || instances.isEmpty ? .loading : .failed("Did not start") }
        if let error = errors[instance.id] { return .failed(error) }
        if let node = nodes[instance.id] { return .node(node, card: instance.card) }
        return .empty
    }
}

/// A widget's picture: its live view on the gallery's background, scaled down to fit.
struct WidgetPicture: View {
    let gallery: WidgetGallery
    let widget: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#1b2233") ?? .black, Color(hex: "#07090f") ?? .black], startPoint: .top, endPoint: .bottom)
            switch gallery.shown(widget) {
            case .loading:
                ProgressView().controlSize(.small)
            case .node(let node, let card):
                Fitted {
                    NodeView(node: node)
                        .padding(card == nil || card == "none" ? 0 : 16)
                        .background {
                            if let card, card != "none" {
                                RoundedRectangle(cornerRadius: gallery.cardRadius, style: .continuous).fill(Color.white.opacity(0.1))
                            }
                        }
                }
                .padding(14)
                .environment(\.lockyStyle, gallery.style)
                .foregroundStyle(gallery.style.color("fg"))
            case .empty:
                Text("Shows nothing until it is set up").font(.caption).foregroundStyle(.white.opacity(0.5))
            case .failed:
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.white.opacity(0.4))
            }
        }
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

/// A widget's card in a gallery: its picture, its name, what it shows, and where it comes from.
struct WidgetCard: View {
    let gallery: WidgetGallery
    let widget: Inspection.WidgetInfo
    var highlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetPicture(gallery: gallery, widget: widget.name)
                .frame(height: 140)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: highlighted ? 2 : 1)
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(EditorPlacement.title(widget.name)).font(.body.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(AddWidgetSheet.source(of: widget)).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                Text(widget.description ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
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
            else if path.hasPrefix(packages) { themes[AddWidgetSheet.source(of: widget), default: []].append(widget) }
            else { installed.append(widget) }
        }
        var list = [WidgetGroup(title: "Locky", widgets: core), WidgetGroup(title: "Your Config", widgets: config),
                    WidgetGroup(title: "Installed", widgets: installed)]
        for name in themes.keys.sorted() {
            list.append(WidgetGroup(title: "\(EditorPlacement.title(name)) Theme", widgets: themes[name]!))
        }
        return list.filter { !$0.widgets.isEmpty }
    }
}
