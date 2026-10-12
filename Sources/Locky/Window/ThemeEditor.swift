import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The theme editor's panel. With nothing selected: the theme, its background, and its widgets and password field
/// to select. With a widget selected: where it sits, its card, and its options. With the password field selected:
/// where it sits. Changes save to settings.json at once, and the preview shows them as they are made.
struct ThemeEditor: View {
    @Bindable var model: AppModel
    let editing: ThemeEditing
    @Binding var selection: EditorItem?
    /// settings.json with a change still being made, such as a slider being dragged: the preview shows it first.
    @Binding var draft: Settings?
    @State private var adding = false

    private var theme: Inspection.ThemeInfo { editing.theme }

    var body: some View {
        Group {
            if let layoutError = editing.layoutError {
                ContentUnavailableView("Can't Edit This Theme", systemImage: "exclamationmark.triangle", description: Text(layoutError))
            } else if editing.layout == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch selection {
                case .widget(let index) where editing.placements.indices.contains(index):
                    // A panel of its own per widget: typing in one widget's fields never carries over to another's.
                    WidgetInspector(model: model, editing: editing, index: index, selection: $selection, draft: $draft)
                        .id(index)
                case .passwordField:
                    PasswordFieldInspector(editing: editing, selection: $selection)
                default:
                    overview
                }
            }
        }
        .sheet(isPresented: $adding) {
            AddWidgetSheet(widgets: model.inspection.widgets) { name in
                selection = .widget(editing.add(name))
            }
        }
    }

    private var overview: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(theme.name).font(.title3.weight(.semibold))
                        if theme.id == model.activeTheme { Tag("In Use", color: .green) }
                        if !model.store.settings["themes"][theme.id].isNil { Tag("Changed", color: .orange) }
                    }
                    Text(theme.description ?? theme.id).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let author = theme.author { Text("By \(author)").font(.caption).foregroundStyle(.tertiary) }
                }
            }
            Section("Background") {
                BackgroundEditor(model: model, theme: theme, layout: editing.layout, draft: $draft)
            }
            Section {
                ForEach(Array(editing.placements.enumerated()), id: \.offset) { index, placement in
                    Button { selection = .widget(index) } label: {
                        WidgetRow(placement: placement, info: editing.info(placement))
                    }
                    .buttonStyle(.plain)
                }
                Button("Add Widget…", systemImage: "plus") { adding = true }
            } header: {
                HStack {
                    Text("Widgets")
                    Spacer()
                    if editing.widgetsChanged {
                        Button("Reset Layout") { editing.resetWidgets() }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
            }
            Section {
                Button { selection = .passwordField } label: {
                    HStack {
                        Text("Password Field")
                        Spacer()
                        Text(editing.authPlace.anchor.replacingOccurrences(of: "-", with: " ").capitalizedFirst).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Click a widget in the preview to change it, and drag it to move it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// A widget in the theme's list: its name and what it shows.
private struct WidgetRow: View {
    let placement: EditorPlacement
    let info: Inspection.WidgetInfo?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(EditorPlacement.title(placement.widget)).font(.body.weight(.medium)).lineLimit(1)
                    if info == nil {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            .help("No widget has this name. Is its plugin installed?")
                    }
                }
                if let description = info?.description {
                    Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Back to the theme's panel.
private struct BackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label(title, systemImage: "chevron.left") }
            .buttonStyle(.link)
    }
}

/// One widget: where it sits, its card, its options, and Remove.
private struct WidgetInspector: View {
    @Bindable var model: AppModel
    let editing: ThemeEditing
    let index: Int
    @Binding var selection: EditorItem?
    @Binding var draft: Settings?

    var body: some View {
        let placement = editing.placements[index]
        let info = editing.info(placement)
        let inherited = editing.inherited(placement)
        let keys = OptionRow.keys(inherited: inherited, overrides: placement.opts, choices: info?.choices ?? [:])
        Form {
            Section {
                BackButton(title: editing.theme.name) { selection = nil }
                VStack(alignment: .leading, spacing: 3) {
                    Text(EditorPlacement.title(placement.widget)).font(.title3.weight(.semibold))
                    if let info {
                        if let description = info.description { Text(description).foregroundStyle(.secondary) }
                        Text(AddWidgetSheet.source(of: info)).font(.caption).foregroundStyle(.tertiary)
                    } else {
                        Label("No widget has this name. Is its plugin installed?", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section("Position") {
                PositionEditor(anchor: placement.anchor, x: placement.x, y: placement.y) { anchor, x, y in
                    change {
                        $0.anchor = anchor
                        $0.x = x
                        $0.y = y
                    }
                }
            }
            if editing.layout?.cardStyle != "none" {
                Section {
                    Toggle("On a Card", isOn: Binding(get: { editing.card(placement) }, set: { value in change { $0.card = .bool(value) } }))
                }
            }
            if !keys.isEmpty {
                Section {
                    ForEach(keys, id: \.self) { key in
                        OptionRow(key: key, value: placement.opts[key] ?? inherited[key] ?? .nil, choices: info?.choices[key],
                                  fallback: info?.opts[key], palette: Theme.fallback.palette.merging(editing.theme.palette) { $1 },
                                  live: { draft = settings(key, $0) },
                                  commit: { value in
                                      change { $0.opts[key] = value == inherited[key] ? nil : value }
                                      draft = nil
                                  })
                    }
                } header: {
                    HStack {
                        Text("Options")
                        Spacer()
                        if !placement.opts.isEmpty {
                            Button("Reset Options") { change { $0.opts = [:] } }
                                .buttonStyle(.link)
                                .font(.callout)
                        }
                    }
                }
            }
            Section {
                Button("Remove Widget", role: .destructive) {
                    selection = nil
                    editing.remove(index)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Changes this widget as it is now, so a change that saves a moment late (a color picked) never brings back an
    /// older copy of it. An option set back to what the theme gives it leaves settings.json.
    private func change(_ edit: (inout EditorPlacement) -> Void) {
        guard editing.placements.indices.contains(index) else { return }
        var placement = editing.placements[index]
        edit(&placement)
        editing.set(index, placement)
    }

    /// settings.json with an option changed, for the preview while a color is being picked.
    private func settings(_ key: String, _ value: LuaValue) -> Settings? {
        var list = editing.placements
        guard list.indices.contains(index) else { return nil }
        list[index].opts[key] = value
        var settings = model.store.settings
        settings.setThemeEdit(editing.theme.id, "widgets", .array(list.map(\.settingsValue)))
        return settings
    }
}

/// The password field: where it sits. The theme sets its look.
private struct PasswordFieldInspector: View {
    let editing: ThemeEditing
    @Binding var selection: EditorItem?

    var body: some View {
        let place = editing.authPlace
        Form {
            Section {
                BackButton(title: editing.theme.name) { selection = nil }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Password Field").font(.title3.weight(.semibold))
                    Text("Where the password is typed. Its look is the theme's.").foregroundStyle(.secondary)
                }
            }
            Section("Position") {
                PositionEditor(anchor: place.anchor, x: place.x, y: place.y) { editing.setAuth(anchor: $0, x: $1, y: $2) }
            }
            if editing.authChanged {
                Section {
                    Button("Put It Back Where the Theme Has It") { editing.resetAuth() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Where an item sits: one dot for each place on the screen, and its offset from that place.
private struct PositionEditor: View {
    let anchor: String
    let x: Double
    let y: Double
    let set: (_ anchor: String, _ x: Double, _ y: Double) -> Void

    var body: some View {
        LabeledContent("Place") {
            AnchorPicker(anchor: anchor) { picked in
                let margin = EditorPlacement.margin(for: picked)
                set(picked, margin.x, margin.y)
            }
        }
        LabeledContent("Offset") {
            HStack(spacing: 8) {
                NumberField(label: "X", value: x) { set(anchor, $0, y) }
                NumberField(label: "Y", value: y) { set(anchor, x, $0) }
            }
        }
        Text("In points \(Self.describe(anchor)), on a 1440 × 900 screen; y grows downwards.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// "top-right" → "from the top right corner".
    static func describe(_ anchor: String) -> String {
        switch anchor {
        case "center": "from the center"
        case "top", "bottom", "left", "right": "from the \(anchor) edge"
        default: "from the \(anchor.replacingOccurrences(of: "-", with: " ")) corner"
        }
    }
}

/// One of a widget's options, with a control that fits its value: a menu for listed values, weights, and designs;
/// a switch for true and false; a number field; a color; or text.
private struct OptionRow: View {
    let key: String
    let value: LuaValue
    let choices: [String]?
    /// The widget's own value for the option, which tells what kind of value it takes.
    let fallback: LuaValue?
    let palette: [String: String]
    /// A change in progress, for the preview.
    let live: (LuaValue) -> Void
    let commit: (LuaValue) -> Void

    static let weights = ["ultralight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"]
    static let designs = ["default", "rounded", "serif", "monospaced"]

    var body: some View {
        let label = Self.label(key)
        if let choices = choices ?? (key == "weight" ? Self.weights : key == "design" ? Self.designs : nil), value.string != nil || value.isNil {
            let current = value.string ?? choices.first ?? ""
            Picker(label, selection: Binding(get: { current }, set: { commit(.string($0)) })) {
                ForEach(choices.contains(current) ? choices : choices + [current], id: \.self) { Text($0.capitalizedFirst).tag($0) }
            }
        } else {
            switch value {
            case .bool(let on) where fallback?.string != nil:
                // Text that a theme turned off with false, such as a header: on brings the widget's own text back.
                Toggle(label, isOn: Binding(get: { on }, set: { commit($0 ? fallback ?? .bool(true) : .bool(false)) }))
            case .bool(let on):
                Toggle(label, isOn: Binding(get: { on }, set: { commit(.bool($0)) }))
            case .int, .double:
                LabeledContent(label) {
                    NumberField(label: nil, value: value.number ?? 0, step: Self.step(key, value)) { commit(EditorPlacement.number($0)) }
                }
            case .string(let text) where Self.isColor(key, text, palette):
                LabeledContent(label) {
                    ColorChoice(value: text, palette: palette, live: { live(.string($0)) }, commit: { commit(.string($0)) })
                }
            case .string(let text):
                LabeledContent(label) { TextOption(text: text) { commit(.string($0)) } }
            default:
                EmptyView()
            }
        }
    }

    /// The options to show, the common ones first, then by name. Lists and tables are left out: only Lua changes them.
    static func keys(inherited: [String: LuaValue], overrides: [String: LuaValue], choices: [String: [String]]) -> [String] {
        let keys = Set(inherited.keys).union(overrides.keys).union(choices.keys).filter { key in
            switch overrides[key] ?? inherited[key] ?? .nil {
            case .bool, .int, .double, .string: true
            case .nil: choices[key] != nil
            default: false
            }
        }
        let first = ["style", "format", "text", "label", "title", "size", "weight", "design", "font", "color"]
        return keys.sorted { a, b in
            let (rankA, rankB) = (first.firstIndex(of: a) ?? first.count, first.firstIndex(of: b) ?? first.count)
            return rankA != rankB ? rankA < rankB : a < b
        }
    }

    /// "shadow_color" → "Shadow color".
    static func label(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalizedFirst
    }

    /// Fractions step by 0.05; other numbers by 1.
    static func step(_ key: String, _ value: LuaValue) -> Double {
        let number = value.number ?? 0
        return ["opacity", "dim", "alpha"].contains(key) || (number.rounded() != number && abs(number) < 1) ? 0.05 : 1
    }

    /// A color option: named like one, or holding a palette role or a "#rrggbb" color.
    static func isColor(_ key: String, _ text: String, _ palette: [String: String]) -> Bool {
        key == "color" || key.hasSuffix("_color") || palette[text] != nil || (text.hasPrefix("#") && NSColor(hex: text) != nil)
    }
}

/// A palette role or a color: a menu of the theme's roles, and a color well for any other color.
private struct ColorChoice: View {
    let value: String
    let palette: [String: String]
    let live: (String) -> Void
    let commit: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(palette.keys.sorted(), id: \.self) { role in
                    Button { commit(role) } label: {
                        Label { Text(role) } icon: { Image(nsImage: Self.swatch(palette[role] ?? "#000000")) }
                    }
                }
            } label: {
                Text(palette[value] != nil ? value : "Custom")
            }
            .fixedSize()
            DebouncedColorPicker(title: "", hex: palette[value] ?? value, live: live, commit: commit)
                .labelsHidden()
        }
    }

    /// A small dot of a color, for the menu.
    static func swatch(_ hex: String) -> NSImage {
        NSImage(size: CGSize(width: 12, height: 12), flipped: false) { rect in
            (NSColor(hex: hex) ?? .black).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            NSColor.separatorColor.setStroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }
}

/// A text option that saves when editing ends, not on every key.
private struct TextOption: View {
    let text: String
    let commit: (String) -> Void
    @State private var current = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $current)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
            .focused($focused)
            .onSubmit { if current != text { commit(current) } }
            .onChange(of: focused) { if !focused, current != text { commit(current) } }
            .onAppear { current = text }
            .onChange(of: text) { current = text }
    }
}

/// A number field that saves when editing ends, not on every key; with a step, a stepper beside it saves at once.
private struct NumberField: View {
    let label: String?
    let value: Double
    var step: Double?
    let commit: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 3) {
            if let label { Text(label).font(.caption).foregroundStyle(.secondary) }
            TextField(label ?? "", text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { if !focused { save() } }
            if let step {
                Stepper("", onIncrement: { commit(Self.round(value + step, step)) }, onDecrement: { commit(Self.round(value - step, step)) })
                    .labelsHidden()
            }
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

    /// A step of 0.05 keeps two decimals, so steps add up without drift.
    private static func round(_ value: Double, _ step: Double) -> Double {
        step < 1 ? (value * 100).rounded() / 100 : value.rounded()
    }

    private static func format(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1e9 else { return "0" }
        return value.rounded() == value ? String(Int(value)) : String(value)
    }
}

/// Nine dots, one per place on the screen: its corners, its edges' middles, and its center.
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
                                .frame(width: 16, height: 11)
                        }
                        .buttonStyle(.plain)
                        .help("Move it to the \(PositionEditor.describe(name).dropFirst(9))")
                    }
                }
            }
        }
        .padding(5)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement()
        .accessibilityLabel("Place")
        .accessibilityValue(anchor)
    }
}

struct AddWidgetSheet: View {
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
                        Text(EditorPlacement.title(widget.name)).font(.body.weight(.medium))
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
                Text("The new widget starts at the center. Drag it where you want it.").font(.callout).foregroundStyle(.secondary)
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

/// The background picker: the theme's own, or the wallpaper, an image, a video, a color, or a gradient. Sliders and
/// colors show in the preview as they change, and save when they stop.
private struct BackgroundEditor: View {
    @Bindable var model: AppModel
    let theme: Inspection.ThemeInfo
    let layout: ThemeLayout?
    @Binding var draft: Settings?

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
            color("Color", get: { edit["color"].string }, fields: { ["color": .string($0)] })
        case .gradient:
            color("From", get: { edit["gradient"][0].string }, fields: { ["gradient": gradient(0, $0)] })
            color("To", get: { edit["gradient"][1].string }, fields: { ["gradient": gradient(1, $0)] })
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
        draft = nil
    }

    /// The background with `fields` changed.
    private func patched(_ fields: [String: LuaValue]) -> LuaValue {
        var table = edit.table ?? [:]
        for (key, value) in fields { table[key] = value }
        return .table(table)
    }

    /// Shows the change in the preview before it saves.
    private func preview(_ fields: [String: LuaValue]) {
        var settings = store.settings
        settings.setThemeEdit(theme.id, "background", patched(fields))
        draft = settings
    }

    private func save(_ fields: [String: LuaValue]) {
        let value = patched(fields)
        store.update { $0.setThemeEdit(theme.id, "background", value) }
        draft = nil
    }

    private func gradient(_ index: Int, _ hex: String) -> LuaValue {
        var colors = edit["gradient"].array ?? [.string("#000000"), .string("#000000")]
        while colors.count < 2 { colors.append(.string("#000000")) }
        colors[index] = .string(hex)
        return .array(colors)
    }

    private func slider(_ title: String, key: String, range: ClosedRange<Double>, fallback: Double) -> some View {
        let fields = { (value: Double) -> [String: LuaValue] in [key: .double((value * 100).rounded() / 100)] }
        return CommittingSlider(title: title, value: edit[key].number ?? fallback, range: range,
                                live: { preview(fields($0)) }, commit: { save(fields($0)) })
    }

    private func file(_ key: String, types: [UTType]) -> some View {
        LabeledContent("File") {
            HStack {
                Text(edit[key].string.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "None")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("Choose…") {
                    if let url = Self.chooseFile(types: types) { save([key: .string(url.path)]) }
                }
            }
        }
    }

    private func color(_ title: String, get: @escaping () -> String?, fields: @escaping (String) -> [String: LuaValue]) -> some View {
        DebouncedColorPicker(title: title, hex: get() ?? "#000000", live: { preview(fields($0)) }, commit: { save(fields($0)) })
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

/// A slider that shows its value live while dragged, and saves once, when the drag ends.
private struct CommittingSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let live: (Double) -> Void
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
        .onChange(of: current) { if dragging { live(current) } }
    }

    /// Within the slider's range; a value that is not a finite number starts at the low end.
    private func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }
}

/// A color well that shows each color live, and saves a moment after the color stops changing, not on every step
/// of a drag.
private struct DebouncedColorPicker: View {
    let title: String
    let hex: String
    let live: (String) -> Void
    let commit: (String) -> Void
    @State private var color = Color.black
    @State private var pending: Task<Void, Never>?

    var body: some View {
        ColorPicker(title, selection: Binding(get: { color }, set: { new in
            color = new
            guard let value = new.hexString else { return }
            live(value)
            pending?.cancel()
            pending = Task {
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled { commit(value) }
            }
        }), supportsOpacity: false)
        .onAppear { color = Color(hex: hex) ?? .black }
        .onChange(of: hex) { color = Color(hex: hex) ?? .black }
        // A control that goes away (another widget selected, a background picked) never saves late.
        .onDisappear { pending?.cancel() }
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
