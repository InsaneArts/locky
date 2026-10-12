import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The theme editor: a background of the user's choice, and the theme's widgets to move, add, and remove.
/// It writes settings.json's themes.<id>; Reset removes the change.
struct ThemeEditor: View {
    @Bindable var model: AppModel
    let theme: Inspection.ThemeInfo
    @State private var layout: ThemeLayout?
    @State private var layoutError: String?
    @State private var adding = false

    private var store: SettingsStore { model.store }

    var body: some View {
        Form {
            Section("Background") {
                BackgroundEditor(model: model, theme: theme, layout: layout)
            }
            Section {
                if let layoutError {
                    Label(layoutError, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                } else if layout == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if placements.isEmpty {
                    Text("No widgets").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(placements.enumerated()), id: \.offset) { index, placement in
                        PlacementRow(placement: placement, info: model.inspection.widget(placement.widget),
                                     update: { changed in set(index, changed) }, remove: { remove(index) })
                    }
                }
                Button("Add Widget…", systemImage: "plus") { adding = true }
                    .disabled(layout == nil)
            } header: {
                HStack {
                    Text("Widgets")
                    Spacer()
                    if !store.settings.themeEdit(theme.id, "widgets").isNil {
                        Button("Reset Layout") { store.update { $0.setThemeEdit(theme.id, "widgets", nil) } }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
            } footer: {
                Text("Widgets show on the main display. Offsets are in points on a 1440×900 screen; y grows downwards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: "\(theme.id)-\(model.revision)") { await load() }
        .sheet(isPresented: $adding) {
            AddWidgetSheet(widgets: model.inspection.widgets) { name in
                write(placements + [EditorPlacement(widget: name)])
            }
        }
    }

    private func load() async {
        let wallpaper = NSScreen.main.flatMap(Wallpaper.picture(for:))?.path
        switch await Inspection.layout(of: theme.id, config: store.config, wallpaper: wallpaper) {
        case .success(let value):
            layout = value
            layoutError = nil
        case .failure(let error):
            layoutError = error.message
        }
    }

    /// The window's widget list for this theme, or the theme's own.
    private var placements: [EditorPlacement] {
        if let edited = store.settings.themeEdit(theme.id, "widgets").array {
            return edited.map(EditorPlacement.init(entry:))
        }
        return (layout?.widgets ?? []).enumerated().map { EditorPlacement(original: $1, ref: $0 + 1) }
    }

    private func set(_ index: Int, _ placement: EditorPlacement) {
        var list = placements
        guard list.indices.contains(index) else { return }
        list[index] = placement
        write(list)
    }

    private func remove(_ index: Int) {
        var list = placements
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        write(list)
    }

    private func write(_ list: [EditorPlacement]) {
        store.update { $0.setThemeEdit(theme.id, "widgets", .array(list.map(\.settingsValue))) }
    }
}

/// One widget in the editor: the theme's placement number `ref`, or one the user added.
struct EditorPlacement: Equatable {
    var ref: Int?
    var widget: String
    var anchor = "center"
    var x = 0.0
    var y = 0.0
    /// true or false for a card; nil leaves it to the theme and the widget.
    var card: Bool?
    /// Fields the editor does not show (size, align, display, opts), kept as they are.
    var rest: [String: LuaValue] = [:]

    init(widget: String) {
        self.widget = widget
    }

    /// From the theme's own placement.
    init(original: LuaValue, ref: Int) {
        self.init(entry: original)
        self.ref = ref
        rest = [:]
    }

    /// From a settings.json entry.
    init(entry: LuaValue) {
        widget = entry["widget"].string ?? "?"
        ref = entry["ref"].int
        anchor = entry["anchor"].string ?? "center"
        x = Self.coordinate(entry["offset"][0].number)
        y = Self.coordinate(entry["offset"][1].number)
        switch entry["card"] {
        case .bool(let value): card = value
        case .string(let style): card = style != "none"
        default: card = nil
        }
        let shown: Set<String> = ["ref", "widget", "anchor", "offset", "card"]
        rest = (entry.table ?? [:]).filter { !shown.contains($0.key) }
    }

    var settingsValue: LuaValue {
        var table = rest
        table["widget"] = .string(widget)
        if let ref { table["ref"] = .int(ref) }
        table["anchor"] = .string(anchor)
        table["offset"] = .array([Self.number(x), Self.number(y)])
        if let card { table["card"] = .bool(card) }
        return .table(table)
    }

    /// A finite offset within ±100,000 points, as the runtime clamps it; anything else is 0.
    static func coordinate(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, -100_000), 100_000)
    }

    private static func number(_ value: Double) -> LuaValue {
        value.rounded() == value && abs(value) < 1e9 ? .int(Int(value)) : .double(value)
    }
}

private struct PlacementRow: View {
    let placement: EditorPlacement
    let info: Inspection.WidgetInfo?
    let update: (EditorPlacement) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AnchorPicker(anchor: placement.anchor) { anchor in
                var changed = placement
                changed.anchor = anchor
                update(changed)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(placement.widget).font(.body.weight(.medium)).lineLimit(1)
                    if info == nil {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            .help("No widget has this name. Is its plugin installed?")
                    }
                }
                HStack(spacing: 6) {
                    NumberField(label: "X", value: placement.x) { value in
                        var changed = placement
                        changed.x = value
                        update(changed)
                    }
                    NumberField(label: "Y", value: placement.y) { value in
                        var changed = placement
                        changed.y = value
                        update(changed)
                    }
                    Toggle("Card", isOn: Binding(get: { placement.card ?? info?.card ?? false }, set: { value in
                        var changed = placement
                        changed.card = value
                        update(changed)
                    }))
                    .toggleStyle(.checkbox)
                    .help("Put the widget on the theme's card")
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help("Remove \(placement.widget)")
        }
        .padding(.vertical, 2)
        .help(info?.description ?? placement.widget)
    }
}

/// A number field that saves when editing ends, not on every key.
private struct NumberField: View {
    let label: String
    let value: Double
    let commit: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: 54)
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { if !focused { save() } }
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: value) { text = Self.format(value) }
    }

    private func save() {
        guard let number = Double(text.replacingOccurrences(of: ",", with: ".")), number.isFinite else {
            text = Self.format(value)
            return
        }
        if number != value { commit(min(max(number, -10_000), 10_000)) }
    }

    private static func format(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1e9 else { return "0" }
        return value.rounded() == value ? String(Int(value)) : String(value)
    }
}

/// Nine dots, one per anchor: the widget's corner, edge, or center of the screen.
private struct AnchorPicker: View {
    let anchor: String
    let pick: (String) -> Void

    private static let grid = [["top-left", "top", "top-right"], ["left", "center", "right"], ["bottom-left", "bottom", "bottom-right"]]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Self.grid, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { name in
                        Button { pick(name) } label: {
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(name == anchor ? Color.accentColor : Color.primary.opacity(0.15))
                                .frame(width: 11, height: 8)
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
        }
        .padding(5)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement()
        .accessibilityLabel("Anchor")
        .accessibilityValue(anchor)
    }
}

private struct AddWidgetSheet: View {
    let widgets: [Inspection.WidgetInfo]
    let add: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var shown: [Inspection.WidgetInfo] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return widgets }
        return widgets.filter { $0.name.lowercased().contains(query) || ($0.description ?? "").lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add a Widget").font(.headline)
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            .padding(16)
            Divider()
            List(shown) { widget in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(widget.name).font(.body.weight(.medium))
                        Text(widget.description ?? "").font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        Text(Self.source(of: widget)).font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Add") {
                        add(widget.name)
                        dismiss()
                    }
                }
                .padding(.vertical, 3)
            }
            Divider()
            HStack {
                Text("The new widget starts at the center; set its place in the list.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 520)
    }

    /// "Built in", a package's name, or the user's config.
    static func source(of widget: Inspection.WidgetInfo) -> String {
        guard let path = widget.file?.path else { return "" }
        if path.hasPrefix(RuntimePath.builtInRuntime.path) { return "Built in" }
        if path.hasPrefix(RuntimePath.defaultConfig.path) { return "Your config" }
        let parts = path.split(separator: "/")
        if let plugin = parts.lastIndex(of: "plugin"), plugin > 0 { return String(parts[plugin - 1]) }
        return LuaError.shortenPaths(path)
    }
}

/// The background picker: the theme's own, or the wallpaper, an image, a video, a color, or a gradient.
private struct BackgroundEditor: View {
    @Bindable var model: AppModel
    let theme: Inspection.ThemeInfo
    let layout: ThemeLayout?

    enum Kind: String, CaseIterable, Identifiable {
        case theme, wallpaper, image, video, color, gradient
        var id: String { rawValue }
        var title: String {
            switch self {
            case .theme: "Theme's Own"
            case .wallpaper: "Desktop Picture"
            case .image: "Image"
            case .video: "Video"
            case .color: "Color"
            case .gradient: "Gradient"
            }
        }
    }

    private var store: SettingsStore { model.store }
    private var edit: LuaValue { store.settings.themeEdit(theme.id, "background") }

    private var kind: Kind {
        if edit.isNil { return .theme }
        if edit["wallpaper"].bool == true { return .wallpaper }
        if edit["image"].string != nil { return .image }
        if edit["video"].string != nil { return .video }
        if edit["gradient"].array != nil { return .gradient }
        return .color
    }

    var body: some View {
        Picker("Background", selection: Binding(get: { kind }, set: { choose($0) })) {
            ForEach(Kind.allCases) { Text($0.title).tag($0) }
        }
        switch kind {
        case .theme:
            LabeledContent("Uses", value: summary(layout?.background ?? .nil))
        case .wallpaper:
            slider("Blur", key: "blur", range: 0...60, fallback: 30)
            slider("Dim", key: "dim", range: 0...0.8, fallback: 0.25)
        case .image:
            file("image", types: [.image])
            slider("Blur", key: "blur", range: 0...60, fallback: 0)
            slider("Dim", key: "dim", range: 0...0.8, fallback: 0)
        case .video:
            file("video", types: [.movie])
            slider("Dim", key: "dim", range: 0...0.8, fallback: 0)
        case .color:
            color("Color", get: { edit["color"].string }, set: { patch(["color": .string($0)]) })
        case .gradient:
            color("From", get: { edit["gradient"][0].string }, set: { setGradient(0, $0) })
            color("To", get: { edit["gradient"][1].string }, set: { setGradient(1, $0) })
            slider("Angle", key: "angle", range: 0...360, fallback: 180)
        }
    }

    private func choose(_ kind: Kind) {
        let palette = theme.palette
        let value: LuaValue?
        switch kind {
        case .theme: value = nil
        case .wallpaper: value = .table(["wallpaper": .bool(true), "blur": .int(30), "dim": .double(0.25)])
        case .image, .video:
            guard let url = Self.chooseFile(types: kind == .image ? [.image] : [.movie]) else { return }
            value = .table([kind.rawValue: .string(url.path)])
        case .color: value = .table(["color": .string(palette["bg"] ?? "#101820")])
        case .gradient:
            value = .table(["gradient": .array([.string(palette["bg"] ?? "#101820"), .string(palette["accent"] ?? "#0a84ff")]),
                            "angle": .int(180)])
        }
        store.update { $0.setThemeEdit(theme.id, "background", value) }
    }

    private func patch(_ fields: [String: LuaValue]) {
        var table = edit.table ?? [:]
        for (key, value) in fields { table[key] = value }
        store.update { $0.setThemeEdit(theme.id, "background", .table(table)) }
    }

    private func setGradient(_ index: Int, _ hex: String) {
        var colors = edit["gradient"].array ?? [.string("#000000"), .string("#000000")]
        while colors.count < 2 { colors.append(.string("#000000")) }
        colors[index] = .string(hex)
        patch(["gradient": .array(colors)])
    }

    private func slider(_ title: String, key: String, range: ClosedRange<Double>, fallback: Double) -> some View {
        CommittingSlider(title: title, value: edit[key].number ?? fallback, range: range) { patch([key: .double(($0 * 100).rounded() / 100)]) }
    }

    private func file(_ key: String, types: [UTType]) -> some View {
        LabeledContent("File") {
            HStack {
                Text(edit[key].string.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "None")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("Choose…") {
                    if let url = Self.chooseFile(types: types) { patch([key: .string(url.path)]) }
                }
            }
        }
    }

    private func color(_ title: String, get: @escaping () -> String?, set: @escaping (String) -> Void) -> some View {
        DebouncedColorPicker(title: title, hex: get() ?? "#000000", commit: set)
    }

    /// What the theme's own background is, in a few words.
    private func summary(_ background: LuaValue) -> String {
        if let shader = background["shader"].string { return "Animated shader · \(shader)" }
        if background["wallpaper"].bool == true { return "Desktop picture" }
        if let image = background["image"].string { return "Image · \(URL(fileURLWithPath: image).lastPathComponent)" }
        if let video = background["video"].string { return "Video · \(URL(fileURLWithPath: video).lastPathComponent)" }
        if background["gradient"].array != nil { return "Gradient" }
        if background["color"].string != nil { return "Color" }
        return "—"
    }

    @MainActor
    static func chooseFile(types: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// A slider that saves once, when the drag ends.
private struct CommittingSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let commit: (Double) -> Void
    @State private var current = 0.0
    @State private var dragging = false

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $current, in: range) { editing in
                    dragging = editing
                    if !editing { commit(current) }
                }
                Text(range.upperBound > 10 ? String(Int(current.rounded())) : String(format: "%.2f", current))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .onAppear { current = clamped(value) }
        .onChange(of: value) { if !dragging { current = clamped(value) } }
    }

    /// Within the slider's range; a value that is not a finite number starts at the low end.
    private func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }
}

/// A color well that saves a moment after the color stops changing, not on every step of a drag.
private struct DebouncedColorPicker: View {
    let title: String
    let hex: String
    let commit: (String) -> Void
    @State private var color = Color.black
    @State private var pending: Task<Void, Never>?

    var body: some View {
        ColorPicker(title, selection: Binding(get: { color }, set: { new in
            color = new
            pending?.cancel()
            pending = Task {
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled, let value = new.hexString { commit(value) }
            }
        }), supportsOpacity: false)
        .onAppear { color = Color(hex: hex) ?? .black }
        .onChange(of: hex) { color = Color(hex: hex) ?? .black }
    }
}

extension Color {
    /// "#rrggbb" in sRGB.
    var hexString: String? {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()).clamped(to: 0...255) }
        return String(format: "#%02x%02x%02x", channels[0], channels[1], channels[2])
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
