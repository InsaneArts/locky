import AppKit
import Foundation

/// One theme in the editor: its own layout, its widget list as the preview shows it, and every change the editor
/// makes, saved to settings.json's themes.<id> at once.
@MainActor @Observable
final class ThemeEditing {
    let theme: Inspection.ThemeInfo
    private let model: AppModel
    /// The theme as init.lua and plugins leave it: what each change starts from, and what Reset goes back to.
    private(set) var layout: ThemeLayout?
    private(set) var layoutError: String?
    /// The window's: each change is a step Edit ▸ Undo takes back.
    @ObservationIgnored weak var undoManager: UndoManager?

    init(theme: Inspection.ThemeInfo, model: AppModel) {
        self.theme = theme
        self.model = model
    }

    private var store: SettingsStore { model.store }

    func load() async {
        let wallpaper = NSScreen.main.flatMap(Wallpaper.picture(for:))?.path
        switch await Inspection.layout(of: theme.id, config: store.config, wallpaper: wallpaper) {
        case .success(let value):
            layout = value
            layoutError = nil
        case .failure(let error):
            // Without the theme's layout nothing may change: refs need it.
            layout = nil
            layoutError = error.message
        }
    }

    // MARK: Widgets

    /// The widget list as the preview shows it: settings.json's for this theme, or the theme's own.
    var placements: [EditorPlacement] {
        let original = layout?.widgets ?? []
        if let entries = store.settings.themeEdit(theme.id, "widgets").array {
            return EditorPlacement.resolve(entries, theme: original)
        }
        return original.enumerated().map { EditorPlacement(original: $1, ref: $0 + 1) }
    }

    var widgetsChanged: Bool { !store.settings.themeEdit(theme.id, "widgets").isNil }

    func info(_ placement: EditorPlacement) -> Inspection.WidgetInfo? { model.inspection.widget(placement.widget) }

    /// The options a placement has before settings.json's: the theme's placement's, or, for a widget the window
    /// added, the widget's own with init.lua's.
    func inherited(_ placement: EditorPlacement) -> [String: LuaValue] {
        if let base = placement.base, let widgets = layout?.widgets, widgets.indices.contains(base) {
            return widgets[base]["opts"].table ?? [:]
        }
        return info(placement)?.opts ?? [:]
    }

    /// Whether a placement sits on the theme's card: its own choice, else the theme's placement's, else the widget's.
    func card(_ placement: EditorPlacement) -> Bool {
        placement.card.flatMap(EditorPlacement.isCard) ?? ownCard(placement)
    }

    /// The card value the card switch saves: none when the theme's placement (or the widget) already does what the
    /// switch says, which keeps the theme's card style.
    func cardValue(_ on: Bool, for placement: EditorPlacement) -> LuaValue? {
        on == ownCard(placement) ? nil : .bool(on)
    }

    /// The family a placement draws: settings.json's, else the theme's placement's.
    func family(_ placement: EditorPlacement) -> String? {
        placement.rest["family"]?.string ?? themeFamily(placement)
    }

    /// The theme's own placement's family, which settings.json can change but not take away.
    func themeFamily(_ placement: EditorPlacement) -> String? {
        guard let base = placement.base, let widgets = layout?.widgets, widgets.indices.contains(base) else { return nil }
        return widgets[base]["family"].string
    }

    /// Whether a placement sits on a card without settings.json's say: the theme's placement's choice, or the widget's.
    private func ownCard(_ placement: EditorPlacement) -> Bool {
        if let base = placement.base, let widgets = layout?.widgets, widgets.indices.contains(base),
           let card = EditorPlacement.isCard(widgets[base]["card"]) {
            return card
        }
        return info(placement)?.card ?? false
    }

    /// Saves a widget's change as the step `action` names, such as "Change Clock".
    func set(_ index: Int, _ placement: EditorPlacement, action: String) {
        var list = placements
        guard list.indices.contains(index) else { return }
        list[index] = placement
        record(action) { write(list) }
    }

    func remove(_ index: Int) {
        var list = placements
        guard list.indices.contains(index) else { return }
        let removed = list.remove(at: index)
        record("Remove \(EditorPlacement.title(removed.widget))") { write(list) }
    }

    /// Adds a widget at the center; returns its place in the list.
    @discardableResult
    func add(_ widget: String, family: String? = nil) -> Int {
        var placement = EditorPlacement(widget: widget)
        if let family { placement.rest["family"] = .string(family) }
        let list = placements + [placement]
        record("Add \(EditorPlacement.title(widget))") { write(list) }
        return list.count - 1
    }

    func resetWidgets() {
        record("Reset Layout") { store.update { $0.setThemeEdit(theme.id, "widgets", nil) } }
    }

    private func write(_ list: [EditorPlacement]) {
        guard layout != nil else { return }
        store.update { $0.setThemeEdit(theme.id, "widgets", .array(list.map(\.settingsValue))) }
    }

    // MARK: The password field

    /// Where the password field sits: settings.json's place for it, or the theme's.
    var authPlace: (anchor: String, x: Double, y: Double) {
        let edit = store.settings.themeEdit(theme.id, "auth")
        let own = layout?.auth ?? .nil
        return (edit["anchor"].string ?? own["anchor"].string ?? "bottom",
                EditorPlacement.coordinate(edit["offset"][0].number ?? own["offset"][0].number),
                EditorPlacement.coordinate(edit["offset"][1].number ?? own["offset"][1].number))
    }

    var authChanged: Bool { !store.settings.themeEdit(theme.id, "auth").isNil }

    func setAuth(anchor: String, x: Double, y: Double) {
        guard layout != nil else { return }
        let place: LuaValue = .table(["anchor": .string(anchor), "offset": .array([EditorPlacement.number(x), EditorPlacement.number(y)])])
        record("Move Password Field") { store.update { $0.setThemeEdit(theme.id, "auth", place) } }
    }

    func resetAuth() {
        record("Reset Password Field") { store.update { $0.setThemeEdit(theme.id, "auth", nil) } }
    }

    // MARK: Undo

    /// Makes `change` to this theme's part of settings.json one step that Edit ▸ Undo takes back, named `action`.
    func record(_ action: String, _ change: () -> Void) {
        ThemeUndo.record(action, theme: theme.id, model: model, undoManager: undoManager, change)
    }

    // MARK: The canvas

    /// A drag on the canvas ended.
    func move(_ item: EditorItem, anchor: Anchor, offset: CGPoint) {
        switch item {
        case .widget(let index):
            guard placements.indices.contains(index) else { return }
            var placement = placements[index]
            placement.anchor = anchor.rawValue
            placement.x = offset.x
            placement.y = offset.y
            set(index, placement, action: "Move \(EditorPlacement.title(placement.widget))")
        case .passwordField:
            setAuth(anchor: anchor.rawValue, x: offset.x, y: offset.y)
        }
    }

    /// An arrow key moved an item a step across and down (-1, 0, or 1 each), from the anchor it keeps.
    func nudge(_ item: EditorItem, by delta: (x: Int, y: Int), byGrid: Bool) {
        switch item {
        case .widget(let index):
            guard placements.indices.contains(index) else { return }
            var placement = placements[index]
            let offset = Placing.nudge(CGPoint(x: placement.x, y: placement.y), x: delta.x, y: delta.y, byGrid: byGrid)
            placement.x = offset.x
            placement.y = offset.y
            set(index, placement, action: "Move \(EditorPlacement.title(placement.widget))")
        case .passwordField:
            let place = authPlace
            let offset = Placing.nudge(CGPoint(x: place.x, y: place.y), x: delta.x, y: delta.y, byGrid: byGrid)
            setAuth(anchor: place.anchor, x: offset.x, y: offset.y)
        }
    }

    /// The name on a selected item.
    func name(of item: EditorItem) -> String {
        switch item {
        case .widget(let index): placements.indices.contains(index) ? EditorPlacement.title(placements[index].widget) : "Widget"
        case .passwordField: "Password Field"
        }
    }
}

/// Undo for the theme editor. Each step holds settings.json's themes.<id> from before a change and after it;
/// undo puts the one back, and redo the other.
@MainActor
enum ThemeUndo {
    /// Runs `change`, and registers its undo, named `action`, if it changed the theme's part of settings.json.
    static func record(_ action: String, theme: String, model: AppModel, undoManager: UndoManager?, _ change: () -> Void) {
        let before = model.store.settings["themes"][theme]
        change()
        let after = model.store.settings["themes"][theme]
        guard let undoManager, before != after else { return }
        register(action, theme: theme, back: before, from: after, model: model, undoManager: undoManager)
    }

    /// Registers the step that puts `back` in place of `from`; taking that step registers its own inverse, the redo.
    private static func register(_ action: String, theme: String, back: LuaValue, from: LuaValue, model: AppModel, undoManager: UndoManager) {
        undoManager.registerUndo(withTarget: model) { model in
            MainActor.assumeIsolated {
                // The theme being changed shows, so the step is seen to happen.
                model.selectedTheme = theme
                restore(back, theme: theme, store: model.store)
                register(action, theme: theme, back: from, from: back, model: model, undoManager: undoManager)
            }
        }
        undoManager.setActionName(action)
    }

    /// Sets settings.json's themes.<theme> to `value`, nil for no changes.
    static func restore(_ value: LuaValue, theme: String, store: SettingsStore) {
        store.update { settings in
            let keys = Set((settings["themes"][theme].table ?? [:]).keys).union((value.table ?? [:]).keys)
            for key in keys { settings.setThemeEdit(theme, key, value[key].isNil ? nil : value[key]) }
        }
    }
}

/// One widget in the editor: the theme's placement number `ref`, or one the user added.
struct EditorPlacement: Equatable {
    var ref: Int?
    /// The theme's placement it starts from (0-based), as Lua finds it: by `ref`, or by widget name after the theme
    /// changed. nil for a widget the window added. Not saved.
    var base: Int?
    var widget: String
    var anchor = "center"
    var x = 0.0
    var y = 0.0
    /// true, false, or a card style such as "outline", kept as settings.json has it; nil leaves it to the theme and
    /// the widget.
    var card: LuaValue?
    /// Fields the editor does not show (size, align, display), and opts, kept as they are.
    var rest: [String: LuaValue] = [:]

    init(widget: String) {
        self.widget = widget
    }

    /// From the theme's own placement. Its card and the rest stay the theme's: Lua takes them from the placement.
    init(original: LuaValue, ref: Int) {
        self.init(entry: original)
        self.ref = ref
        base = ref - 1
        card = nil
        rest = [:]
    }

    /// From a settings.json entry.
    init(entry: LuaValue) {
        widget = entry["widget"].string ?? "?"
        ref = entry["ref"].int
        anchor = entry["anchor"].string ?? "center"
        x = Self.coordinate(entry["offset"][0].number)
        y = Self.coordinate(entry["offset"][1].number)
        card = entry["card"].isNil ? nil : entry["card"]
        let shown: Set<String> = ["ref", "widget", "anchor", "offset", "card"]
        rest = (entry.table ?? [:]).filter { !shown.contains($0.key) }
    }

    var settingsValue: LuaValue {
        var table = rest
        table["widget"] = .string(widget)
        if let ref { table["ref"] = .int(ref) }
        table["anchor"] = .string(anchor)
        table["offset"] = .array([Self.number(x), Self.number(y)])
        if let card { table["card"] = card }
        return .table(table)
    }

    /// Whether a card value puts the widget on a card: true, or a style other than "none".
    static func isCard(_ value: LuaValue) -> Bool? {
        switch value {
        case .bool(let on): on
        case .string(let style): style != "none"
        default: nil
        }
    }

    /// settings.json's options for this widget, over the theme's and init.lua's.
    var opts: [String: LuaValue] {
        get { rest["opts"]?.table ?? [:] }
        set { rest["opts"] = newValue.isEmpty ? nil : .table(newValue) }
    }

    /// settings.json's entries as the preview shows them, each with the theme's placement it starts from. As in
    /// Lua, an entry keeps its exact placement first, then takes the first free one of its widget, and an entry whose
    /// widget the theme no longer has is left out, so the editor's list and the preview's stay in step.
    static func resolve(_ entries: [LuaValue], theme original: [LuaValue]) -> [EditorPlacement] {
        let names = original.map { $0["widget"].string }
        var used = Set<Int>()
        var bases: [Int: Int] = [:]
        for (index, entry) in entries.enumerated() {
            if let ref = entry["ref"].int, names.indices.contains(ref - 1), names[ref - 1] == entry["widget"].string, !used.contains(ref - 1) {
                bases[index] = ref - 1
                used.insert(ref - 1)
            }
        }
        for (index, entry) in entries.enumerated() where entry["ref"].int != nil && bases[index] == nil {
            if let free = names.indices.first(where: { !used.contains($0) && names[$0] == entry["widget"].string }) {
                bases[index] = free
                used.insert(free)
            }
        }
        return entries.enumerated().compactMap { index, entry in
            guard entry["ref"].isNil || bases[index] != nil else { return nil }
            var placement = EditorPlacement(entry: entry)
            placement.base = bases[index]
            return placement
        }
    }

    /// A finite offset within ±100,000 points, as the runtime clamps it; anything else is 0.
    static func coordinate(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, -100_000), 100_000)
    }

    static func number(_ value: Double) -> LuaValue {
        value.rounded() == value && abs(value) < 1e9 ? .int(Int(value)) : .double(value)
    }

    /// "mocha.center" → "Mocha Center".
    static func title(_ widget: String) -> String {
        widget.split(whereSeparator: { ".-_".contains($0) }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The offset a widget gets when the editor places it at `anchor`: off the edges it is pinned to, on the grid.
    static func margin(for anchor: String) -> (x: Double, y: Double) {
        let inset = Double(Placing.grid)
        let x: Double = anchor.hasSuffix("left") ? inset : anchor.hasSuffix("right") ? -inset : 0
        let y: Double = anchor.hasPrefix("top") ? inset : anchor.hasPrefix("bottom") ? -inset : 0
        return (x, y)
    }
}
