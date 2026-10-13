import AppKit
import SwiftUI

/// Every widget, live, for the Add Widget sheet: one Lua runtime runs the theme being customized with each widget
/// placed once in each of its families (once at its own size without any), and each card draws the family it shows.
/// It runs while the sheet shows.
@MainActor @Observable
final class WidgetGallery {
    private(set) var style = LockyStyle()
    /// The theme's card: a widget that sits on one takes its radius, fill, and border.
    private(set) var card = Theme.Card()
    /// Each placement's instance and card style, by key (see `key`).
    private var instances: [String: (id: Int, card: String?)] = [:]
    private var nodes: [Int: Node] = [:]
    /// The instances that have drawn at least once, a drawing of nothing included. A tile shows its background alone
    /// until its instance draws.
    private var drawn: Set<Int> = []
    private var errors: [Int: String] = [:]
    @ObservationIgnored private var runtime: LuaRuntime?
    @ObservationIgnored private var running: [String] = []

    static func key(_ widget: String, _ family: String?) -> String { "\(widget)#\(family ?? "")" }

    /// Starts again when the widget list, the config, or the theme changes; nothing happens when they are the same.
    /// The widgets draw in `theme`'s palette, font, and cards, as they will on its lock screen.
    func start(widgets: [Inspection.WidgetInfo], settings: Settings, config: URL, revision: Int, theme: String = "default") {
        let placements = widgets.flatMap { widget in
            widget.families.isEmpty ? [(widget.name, String?.none)] : widget.families.map { (widget.name, Optional($0)) }
        }
        let key = placements.map { Self.key($0.0, $0.1) } + [String(revision), theme]
        guard key != running else { return }
        stop()
        running = key
        var settings = settings
        // A plain background: the gallery draws its own behind each card.
        settings.setThemeEdit(theme, "background", .table(["color": .string("#000000")]))
        settings.setThemeEdit(theme, "widgets", .array(placements.map { name, family in
            var entry: [String: LuaValue] = ["widget": .string(name)]
            if let family { entry["family"] = .string(family) }
            return .table(entry)
        }))
        let runtime = LuaRuntime(path: .standard(config: config), settings: settings, delegate: LuaRuntime.Delegate(
            present: { [weak self] id, node in
                Task { @MainActor in
                    self?.nodes[id] = node
                    self?.drawn.insert(id)
                    self?.errors[id] = nil
                }
            },
            failed: { [weak self] id, message, _ in Task { @MainActor in self?.errors[id] = message } }
        ))
        self.runtime = runtime
        Task {
            let started = await runtime.start(theme: theme)
            guard self.runtime === runtime else { return }
            style = LockyStyle(palette: started.theme.palette, font: started.theme.font, scale: 1, hour24: started.hour24)
            card = started.theme.card
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
        drawn = []
        errors = [:]
    }

    enum Shown {
        case loading
        case node(Node, card: String?)
        /// It drew nothing: it shows something once it is set up.
        case empty(card: String?)
        case failed(String)
    }

    func shown(_ widget: String, family: String? = nil) -> Shown {
        guard let instance = instances[Self.key(widget, family)] else {
            return runtime == nil || instances.isEmpty ? .loading : .failed("Did not start")
        }
        if let error = errors[instance.id] { return .failed(error) }
        if let node = nodes[instance.id] { return .node(node, card: instance.card) }
        return drawn.contains(instance.id) ? .empty(card: instance.card) : .loading
    }
}

/// A widget's tile: its live view in one family on the theme's background, at its real size scaled down to fit, never
/// up. The tile takes the color scheme the lock window would take on that background, so glass cards and system
/// colors draw as they will on the lock.
struct WidgetPicture: View {
    let gallery: WidgetGallery
    let widget: String
    var family: String?
    /// The theme's background ("#rrggbb"), for the time before the gallery's runtime has the theme's whole palette.
    var background: String?

    var body: some View {
        let bg = gallery.style.palette["bg"] ?? background
        let light = Design.isLight(bg)
        let shape = RoundedRectangle(cornerRadius: Design.Radius.tile, style: .continuous)
        let shown = gallery.shown(widget, family: family)
        let isLoaded = if case .loading = shown { false } else { true }
        ZStack {
            shape.fill(bg.flatMap { Color(hex: $0) } ?? .black)
            switch shown {
            case .loading:
                EmptyView()
            case .node(let node, let card):
                let size = family.flatMap(WidgetChrome<EmptyView>.size)
                fitted {
                    WidgetChrome(card: card.map(themeCard), family: family, fills: size != nil) {
                        NodeView(node: node)
                    }
                    .frame(width: size?.width, height: size?.height)
                }
                .transition(.opacity)
            case .empty(let card):
                if let size = family.flatMap(WidgetChrome<EmptyView>.size) {
                    fitted {
                        WidgetChrome(card: card.map(themeCard), family: family, fills: true) { Color.clear }
                            .frame(width: size.width, height: size.height)
                    }
                }
            case .failed:
                Image(systemName: "exclamationmark.triangle").foregroundStyle(gallery.style.color("muted"))
            }
        }
        // Only the first appearance fades; later updates never animate.
        .animation(Motion.easeOut(duration: 0.2), value: isLoaded)
        .environment(\.colorScheme, light ? .light : .dark)
        .clipShape(shape)
        .pressOverlay(light: light, in: shape)
        .hairline(cornerRadius: Design.Radius.tile, lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    /// A card in `style`, with the theme's radius, fill, and border.
    private func themeCard(_ style: String) -> Theme.Card {
        Theme.Card(style: style, radius: gallery.card.radius, fill: gallery.card.fill, border: gallery.card.border)
    }

    /// Content at its real size inside the tile's 16-pt padding, in the theme's palette and font.
    private func fitted<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Fitted(content: content)
            .padding(16)
            .environment(\.lockyStyle, gallery.style)
            .foregroundStyle(gallery.style.color("fg"))
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

/// Add Widget: the widgets the theme being customized can take, live in its palette, font, and cards. A click on a card
/// adds the widget at the canvas center.
struct WidgetGallerySheet: View {
    let model: AppModel
    /// The theme being customized, which the widget goes to.
    let theme: Inspection.ThemeInfo
    let add: (_ widget: String, _ family: String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var gallery = WidgetGallery()
    @State private var search = ""
    /// The size picked on each card, by widget. A card without one shows `WidgetCard.first`.
    @State private var picked: [String: String] = [:]

    private var groups: [WidgetGroup] { WidgetGroup.groups(model.inspection.widgets, theme: theme) }

    /// The groups, with only the cards whose name or description has the search text.
    private var shown: [WidgetGroup] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let widgets = group.widgets.filter { widget in
                [widget.name, EditorPlacement.title(widget.name), widget.description ?? ""].contains { $0.localizedStandardContains(query) }
            }
            return widgets.isEmpty ? nil : WidgetGroup(title: group.title, widgets: widgets)
        }
    }

    var body: some View {
        let visible = shown
        VStack(spacing: 0) {
            HStack {
                Text("Add Widget").font(.headline)
                Spacer()
                SearchField(text: $search, onSubmit: addFirst)
                    .frame(width: 200)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            ScrollView {
                // A lazy stack's spacing also lies between a header and its cards, so the 24 points between groups
                // come after each grid instead, and the last grid ends with the body's 20.
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(visible) { group in
                        Section {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 20, alignment: .top)], spacing: 24) {
                                ForEach(group.widgets) { widget in
                                    WidgetCard(gallery: gallery, widget: widget, themeName: theme.name, background: theme.palette["bg"],
                                               family: family(of: widget)) { family in
                                        add(widget.name, family)
                                        dismiss()
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, group.id == visible.last?.id ? 20 : 24)
                        } header: {
                            Text(group.title)
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(.bar)
                        }
                    }
                }
            }
            .overlay {
                if visible.isEmpty { ContentUnavailableView.search(text: search) }
            }
            Divider()
            HStack {
                Spacer()
                // While the search field has text, Esc clears it (NSSearchField's own behavior); the next Esc closes the sheet.
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(search.isEmpty ? .cancelAction : nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 760, height: 560)
        // The runtime runs the widgets of every group, whatever the search: it never restarts on a keystroke.
        .task(id: "\(theme.id)#\(model.revision)") {
            gallery.start(widgets: groups.flatMap(\.widgets), settings: model.store.settings, config: model.store.config,
                          revision: model.revision, theme: theme.id)
        }
        .onDisappear { gallery.stop() }
    }

    private func family(of widget: Inspection.WidgetInfo) -> Binding<String?> {
        Binding(get: { picked[widget.name] ?? WidgetCard.first(widget) }, set: { picked[widget.name] = $0 })
    }

    /// Return in the search field: the first card shown, in its picked size, as a click on it adds it.
    private func addFirst() {
        guard let widget = shown.first?.widgets.first else { return }
        add(widget.name, family(of: widget).wrappedValue)
        dismiss()
    }
}

/// The sheet's search field: AppKit's, which has the magnifier and the clear button. It takes the keyboard when the
/// sheet opens, and Return in it calls `onSubmit`.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = FocusedSearchField()
        field.placeholderString = "Search Widgets"
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField

        init(_ parent: SearchField) { self.parent = parent }

        /// The clear button, and Esc, which empty the field. AppKit sends the action for typing only after the run loop
        /// turns, so typing writes the text in `controlTextDidChange`.
        @objc func changed(_ field: NSSearchField) { parent.text = field.stringValue }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            // The text as it is now, so Return right after a key adds what the field shows.
            parent.text = control.stringValue
            parent.onSubmit()
            return true
        }
    }

    /// Becomes the first responder once it is in the sheet's window.
    private final class FocusedSearchField: NSSearchField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // After the sheet has set up its own first responder.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }
}

/// A widget in the Add Widget sheet, as in macOS's widget gallery: its live picture in the size picked below it, its
/// name, and what it shows. A click on the picture adds the widget in that size.
struct WidgetCard: View {
    let gallery: WidgetGallery
    let widget: Inspection.WidgetInfo
    /// The theme the widget goes to, for VoiceOver.
    let themeName: String
    /// The theme's background ("#rrggbb"), for the tile until the gallery's runtime has the theme's palette.
    let background: String?
    @Binding var family: String?
    let add: (_ family: String?) -> Void
    @State private var hovered = false

    /// The family a card shows first: small, as Apple's galleries do, else the first the widget has.
    static func first(_ widget: Inspection.WidgetInfo) -> String? {
        widget.families.contains("small") ? "small" : widget.families.first
    }

    var body: some View {
        let title = EditorPlacement.title(widget.name)
        VStack(alignment: .leading, spacing: 12) {
            Button { add(family) } label: {
                WidgetPicture(gallery: gallery, widget: widget.name, family: family, background: background)
                    .frame(height: 170)
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .font(.system(size: 20))
                            .padding(8)
                            .opacity(hovered ? 1 : 0)
                            .animation(.easeOut(duration: 0.1), value: hovered)
                    }
            }
            .buttonStyle(PressHighlightStyle())
            .onHover { hovered = $0 }
            .accessibilityLabel(family.map { "\(title), \(FamilyPicker.name($0))" } ?? title)
            .accessibilityHint("Adds it to \(themeName).")
            if widget.families.count > 1 {
                FamilyPicker(families: widget.families, selection: $family)
                    .frame(maxWidth: .infinity)
            } else {
                // The picker's height, so the cards in a row line up.
                Color.clear.frame(height: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                Text(widget.description ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, 2)
        }
    }
}

/// Apple's widget sizes as a row of small outlines in each size's proportions, the picked one filled: the Lock Screen
/// sizes, then the desktop ones, in one order on every card.
struct FamilyPicker: View {
    let families: [String]
    @Binding var selection: String?

    static let order = ["circular", "rectangular", "inline", "small", "medium", "large"]

    /// `families` in `order`.
    static func sorted(_ families: [String]) -> [String] {
        families.sorted { (order.firstIndex(of: $0) ?? order.count) < (order.firstIndex(of: $1) ?? order.count) }
    }

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
        let sorted = Self.sorted(families)
        let lockScreen = sorted.filter { ["circular", "rectangular", "inline"].contains($0) }
        let desktop = sorted.filter { !lockScreen.contains($0) }
        HStack(spacing: 2) {
            ForEach(lockScreen, id: \.self, content: button)
            if !lockScreen.isEmpty, !desktop.isEmpty {
                Divider().frame(height: 12)
            }
            ForEach(desktop, id: \.self, content: button)
        }
        .padding(2)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Size")
    }

    private func button(_ family: String) -> some View {
        Button { selection = family } label: {
            glyph(family, picked: selection == family)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Self.name(family))
        .accessibilityLabel(Self.name(family))
        .accessibilityAddTraits(selection == family ? .isSelected : [])
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
        case "rectangular": CGSize(width: 13, height: 6)
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

/// The Add Widget sheet's groups: Locky's own widgets, the config's, each plugin's (A to Z), then the pieces of the
/// built-in theme being customized. Other themes' pieces are left out: each is drawn for its own theme.
struct WidgetGroup: Identifiable {
    var id: String { title }
    var title: String
    var widgets: [Inspection.WidgetInfo]

    static func groups(_ widgets: [Inspection.WidgetInfo], theme: Inspection.ThemeInfo? = nil) -> [WidgetGroup] {
        let packages = RuntimePath.resources.appending(path: "packages").path + "/"
        // The theme's package: the folder its themes/ folder is in.
        let package = theme?.directory.map { $0.resolvingSymlinksInPath().path + "/" }
        var core: [Inspection.WidgetInfo] = [], config: [Inspection.WidgetInfo] = [], own: [Inspection.WidgetInfo] = []
        var plugins: [String: [Inspection.WidgetInfo]] = [:]
        for widget in widgets {
            let path = widget.file?.path ?? ""
            if path.hasPrefix(RuntimePath.builtInRuntime.path + "/") {
                core.append(widget)
            } else if path.hasPrefix(packages) {
                if let package, widget.file?.resolvingSymlinksInPath().path.hasPrefix(package) == true { own.append(widget) }
            } else if path.isEmpty || path.hasPrefix(RuntimePath.defaultConfig.path + "/") {
                // A widget without a file (defined from a string of Lua) joins the config's.
                config.append(widget)
            } else {
                plugins[widget.source ?? path, default: []].append(widget)
            }
        }
        var list = [WidgetGroup(title: "Locky", widgets: core), WidgetGroup(title: "Lua Config", widgets: config)]
        for folder in plugins.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            list.append(WidgetGroup(title: folder, widgets: plugins[folder] ?? []))
        }
        if let theme { list.append(WidgetGroup(title: theme.name, widgets: own)) }
        return list.filter { !$0.widgets.isEmpty }
    }
}
