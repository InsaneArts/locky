import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Customize: one theme's live lock screen as a canvas, where widgets are clicked to change them and dragged to move
/// them, the inspector beside it, and the theme's commands in the toolbar. Changes save to settings.json at once, and
/// the canvas follows.
struct ThemeEditorPage: View {
    let model: AppModel
    let info: Inspection.ThemeInfo
    /// The theme being edited; a new one per theme, so one theme's layout is never saved as another's.
    @State private var editing: ThemeEditing?
    @State private var selection: EditorItem?
    /// settings.json with a change still being made, such as a slider being dragged: the canvas shows it first.
    @State private var draft: Settings?
    /// The name Duplicate Theme asks for, while it asks.
    @State private var copyName: String?
    /// A command that failed: its alert's title and message.
    @State private var problem: (title: String, message: String)?
    @AppStorage("themeEditorGrid") private var grid = false
    @AppStorage("customizeInspector") private var inspectorShown = true
    @Environment(\.undoManager) private var undoManager
    @FocusedValue(\.typing) private var typing

    /// The editor of this theme, once it is made: right after a change of theme, `editing` is still the last one's.
    private var current: ThemeEditing? { editing?.theme.id == info.id ? editing : nil }
    /// The editor once it has the theme's layout, which every change starts from.
    private var loaded: ThemeEditing? { current?.layout == nil ? nil : current }

    var body: some View {
        content
            .navigationTitle(info.name)
            .toolbar { toolbar }
            // Read again when Lua files change: init.lua may give the theme other widgets or options.
            .task(id: "\(info.id)-\(model.inspection.sources)") {
                let next = ThemeEditing(theme: info, model: model)
                next.undoManager = undoManager
                await next.load()
                // A newer load replaced this one.
                guard !Task.isCancelled else { return }
                editing = next
                if let name = model.selectingWidget, let index = next.placements.firstIndex(where: { $0.widget == name }) {
                    model.selectingWidget = nil
                    selection = .widget(index)
                }
            }
            .onChange(of: info.id) {
                selection = nil
                draft = nil
            }
            // A change in progress belongs to what was selected.
            .onChange(of: selection) { draft = nil }
            // Escape in the inspector does what it does on the canvas: it clears the selection, then ends Customize. A text
            // field that has the keyboard keeps it.
            .onExitCommand {
                guard typing != true else { return }
                if selection == nil { model.finishEditing() } else { selection = nil }
            }
            // File menu commands that need the editor: the More menu's, under its rules.
            .onChange(of: model.editorRequest) {
                guard let request = model.editorRequest else { return }
                model.editorRequest = nil
                guard allows(request) else { return }
                switch request {
                case .duplicate: copyName = "\(info.name) Copy"
                case .export: export()
                case .revert: current?.revertToOriginal()
                }
            }
            .sheet(isPresented: Binding(get: { model.addingWidget && loaded != nil }, set: { model.addingWidget = $0 })) {
                WidgetGallerySheet(model: model, theme: info) { name, family in
                    if let loaded { selection = .widget(loaded.add(name, family: family)) }
                }
            }
            // A lock cancels the Duplicate alert: its name field must not take what is typed at the lock.
            .onChange(of: model.locked) { if model.locked { copyName = nil } }
            .alert("Duplicate Theme", isPresented: Binding(get: { copyName != nil }, set: { if !$0 { copyName = nil } })) {
                TextField("Name", text: Binding(get: { copyName ?? "" }, set: { copyName = $0 }))
                Button("Duplicate") { duplicate(named: copyName ?? "") }
                Button("Cancel", role: .cancel) {}
            }
            .alert(problem?.title ?? "", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK") {}
            } message: {
                Text(problem?.message ?? "")
            }
    }

    /// The canvas, in the space the inspector leaves; for a theme that does not load, why.
    @ViewBuilder private var content: some View {
        if let error = info.error {
            UnloadableTheme(model: model, problem: ConfigProblem(error, config: model.store.config))
        } else {
            ThemePreview(theme: info.id, settings: draft ?? model.store.settings, sources: model.inspection.sources,
                         config: model.store.config, alwaysLive: model.screenshots, canvas: canvas, info: info)
                .aspectRatio(1.6, contentMode: .fit)
                .previewFrame()
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .inspector(isPresented: $inspectorShown) {
                    Group {
                        if let current {
                            ThemeInspector(model: model, editing: current, selection: $selection, draft: $draft)
                        } else {
                            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .inspectorColumnWidth(min: 280, ideal: 300, max: 400)
                }
        }
    }

    /// Three groups: the theme's tools, Use Theme, and Done. Use Theme stays when it does not apply, dimmed, so a click
    /// never takes a button from under the pointer.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Add Widget…", systemImage: "plus") { model.addingWidget = true }
                .help("Add a widget to this theme")
                .disabled(loaded == nil)
            Button("Preview", systemImage: "play.rectangle") { model.preview(info.id) }
                .help("Show this theme full size")
                .disabled(info.error != nil)
            Menu {
                Button("Duplicate Theme…") { copyName = "\(info.name) Copy" }
                    .disabled(!allows(.duplicate))
                Button("Export Theme…", action: export)
                    .disabled(!allows(.export))
                Divider()
                Button("Revert to Original") { current?.revertToOriginal() }
                    .disabled(!allows(.revert))
                if model.canTrash(info.id) {
                    Button("Move to Trash", action: moveToTrash)
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
            .help(model.canTrash(info.id) ? "Duplicate, export, revert, or move this theme to the Trash" : "Duplicate, export, or revert this theme")
            .disabled(info.error != nil && !model.canTrash(info.id))
        }
        if #available(macOS 26, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
        ToolbarItem(placement: .primaryAction) {
            Button("Use Theme") { model.use(info.id) }
                .disabled(info.id == model.activeTheme || info.error != nil)
        }
        if #available(macOS 26, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
        ToolbarItem(placement: .primaryAction) {
            Button("Done") { model.finishEditing() }
                .buttonStyle(.borderedProminent)
        }
    }

    /// Whether a More menu command applies: none to a theme that does not load, Export only to a theme another Mac can
    /// load, and Revert only to a theme with changes.
    private func allows(_ command: AppModel.EditorRequest) -> Bool {
        guard info.error == nil else { return false }
        switch command {
        case .duplicate: return true
        case .export: return model.canExport(info.id)
        case .revert: return current?.isChanged == true
        }
    }

    /// What the canvas shows and reports, once the theme's layout is in: the selection, the grid, and where clicks,
    /// drags, and keys go.
    private var canvas: ThemePreview.Canvas? {
        guard let editing = loaded else { return nil }
        return ThemePreview.Canvas(selection: selection, grid: grid, name: { editing.name(of: $0) }, select: { selection = $0 },
                                   move: { editing.move($0, anchor: $1, offset: $2) },
                                   nudge: { editing.nudge($0, by: $1, byGrid: $2) },
                                   remove: { index in
                                       draft = nil
                                       selection = nil
                                       editing.remove(index)
                                   },
                                   exit: { model.finishEditing() })
    }

    /// This theme with its changes, as a theme named `name`.
    private func made(name: String) -> ThemeFile {
        ThemeFile.made(from: info.id, edit: model.store.settings["themes"][info.id], name: name, config: model.store.config)
    }

    /// Writes the copy to the config's themes folder, and opens it in Customize.
    private func duplicate(named name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard ThemeFile.isName(name) else {
            problem = ("Can't Duplicate the Theme", "Use a name of 1 to 80 characters on one line.")
            return
        }
        let file = made(name: name)
        Task {
            do {
                model.customize(try await model.install(file))
            } catch {
                problem = ("Can't Duplicate the Theme", (error as? LuaError)?.message ?? error.localizedDescription)
            }
        }
    }

    /// Saves the theme, with its changes, as one file to share; Import Theme adds it on another Mac.
    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(info.id).lua"
        panel.allowedContentTypes = [ThemeFile.type]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try made(name: info.name).source().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            problem = ("Can't Export the Theme", (error as? LuaError)?.message ?? error.localizedDescription)
        }
    }

    /// The person's own theme goes to the Trash, which is the undo, and Customize ends with it.
    private func moveToTrash() {
        do {
            try model.trash(info.id)
        } catch {
            problem = ("Can't Move the Theme to the Trash", error.localizedDescription)
        }
    }
}

/// A theme that does not load: why, in the words Lua Config uses, and Open at the file and line the error names.
private struct UnloadableTheme: View {
    let model: AppModel
    let problem: ConfigProblem
    /// Why the editor did not open, if it did not.
    @State private var openError: String?
    @FocusState private var focused: Bool

    var body: some View {
        ContentUnavailableView {
            Label("Can't Edit This Theme", systemImage: "exclamationmark.triangle")
        } description: {
            Text(problem.described)
        } actions: {
            OpenProblemButton(model: model, problem: problem, error: $openError)
            if let openError { WarningLabel(openError) }
        }
        // Nothing here takes the keyboard by itself, as the canvas does: this view does, so Esc reaches the page and
        // ends Customize. On the next turn, once the view that had it is gone.
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { DispatchQueue.main.async { focused = true } }
        // Gives the keyboard back as it goes, or the gallery's grid takes Return but not the arrows.
        .onDisappear { focused = false }
    }
}

/// Customize's inspector, which follows the selection. With nothing selected: the person's own theme's name, the theme's
/// background, colors, and font, and its widgets and password field to select. With a widget selected: where it sits,
/// its card, and its options. With the password field selected: where it sits. Changes save to settings.json at once,
/// and the canvas shows them as they are made.
struct ThemeInspector: View {
    let model: AppModel
    let editing: ThemeEditing
    @Binding var selection: EditorItem?
    /// settings.json with a change still being made, such as a slider being dragged: the canvas shows it first.
    @Binding var draft: Settings?

    var body: some View {
        content
    }

    private var content: some View {
        Group {
            if let layoutError = editing.layoutError {
                ContentUnavailableView("Can't Edit This Theme", systemImage: "exclamationmark.triangle", description: Text(layoutError))
            } else if editing.layout == nil {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch selection {
                case .widget(let index) where editing.placements.indices.contains(index):
                    // A panel of its own per widget: typing in one widget's fields never carries over to another's.
                    WidgetInspector(model: model, editing: editing, index: index, selection: $selection, draft: $draft)
                        .id(index)
                case .passwordField:
                    PasswordFieldInspector(model: model, editing: editing)
                default:
                    overview
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var overview: some View {
        Form {
            SaveProblem(model: model)
            if let name = editing.ownName {
                Section {
                    NameField(name: model.inspection.theme(editing.theme.id)?.name ?? name) { try? editing.rename($0) }
                }
            }
            Section("Background") {
                BackgroundEditor(model: model, editing: editing, draft: $draft)
            }
            Section {
                ColorsEditor(model: model, editing: editing, draft: $draft)
            } header: {
                ResetHeader(title: "Colors", shown: editing.colorsChanged) {
                    draft = nil
                    editing.resetColors()
                }
            }
            Section {
                FontEditor(editing: editing)
            } header: {
                ResetHeader(title: "Font", shown: editing.fontChanged) { editing.resetFont() }
            }
            // A theme with no widgets has no header over nothing; the toolbar's + adds one.
            if !editing.placements.isEmpty {
                Section("Widgets") {
                    ForEach(Array(editing.placements.enumerated()), id: \.offset) { index, placement in
                        Button { selection = .widget(index) } label: {
                            WidgetRow(placement: placement, missing: editing.info(placement) == nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section {
                Button { selection = .passwordField } label: {
                    HStack(spacing: 8) {
                        Text("Password Field")
                        Spacer()
                        Text(AnchorPicker.name(editing.authPlace.anchor)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .formStyle(.grouped)
    }
}

/// A widget in the theme's list, by name.
private struct WidgetRow: View {
    let placement: EditorPlacement
    /// Locky has no widget of its name, such as one from a plugin that is not installed.
    let missing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(EditorPlacement.title(placement.widget)).lineLimit(1)
            if missing {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help("No widget has this name. Is its plugin installed?")
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// The name of the person's own theme. It saves when editing ends; a name that is empty or too long goes back.
private struct NameField: View {
    let name: String
    let rename: (String) -> Void
    @State private var current = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $current)
            .focused($focused)
            .focusedValue(\.typing, true)
            .onSubmit(save)
            .onChange(of: focused) { if !focused { save() } }
            .onAppear { current = name }
            .onChange(of: name) { current = name }
            // The panel can go before the field gives up the keyboard, as after Done or a click on the canvas.
            .onDisappear { if focused { save() } }
    }

    private func save() {
        let typed = current.trimmingCharacters(in: .whitespaces)
        guard typed != name else { return }
        guard ThemeFile.isName(typed) else {
            current = name
            return
        }
        rename(typed)
    }
}

/// A section's header with a trailing Reset, shown while there is something to reset.
private struct ResetHeader: View {
    let title: String
    let shown: Bool
    let reset: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if shown {
                Button("Reset", action: reset)
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
    }
}

/// While settings.json has an error, nothing the inspector changes can save: it says so first, with the way to fix it.
private struct SaveProblem: View {
    let model: AppModel

    var body: some View {
        if model.store.problem != nil {
            Section {
                // WarningLabel's look, with the link under the sentence: the inspector is too narrow for it beside.
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("settings.json has an error, so changes can't save.")
                        Button("Open Settings") { model.openWindow(.settings) }
                            .buttonStyle(.link)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        }
    }
}

/// One widget: where it sits, its card, its options, and Remove.
private struct WidgetInspector: View {
    @Bindable var model: AppModel
    let editing: ThemeEditing
    let index: Int
    @Binding var selection: EditorItem?
    @Binding var draft: Settings?
    /// Colors being picked: the preview shows them at once, and they save once the picking stops for a moment, with
    /// the next change, or when the panel goes away.
    @State private var picked: [String: LuaValue] = [:]
    @State private var saving: Task<Void, Never>?

    var body: some View {
        // An undo can take the widget away before the panel goes.
        if editing.placements.indices.contains(index) { form(editing.placements[index]) }
    }

    @ViewBuilder private func form(_ placement: EditorPlacement) -> some View {
        let info = editing.info(placement)
        let inherited = editing.inherited(placement)
        let keys = OptionRow.keys(inherited: inherited, overrides: placement.opts, choices: info?.choices ?? [:])
        let families = info?.families ?? []
        let cards = editing.layout?.cardStyle != "none"
        Form {
            SaveProblem(model: model)
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(EditorPlacement.title(placement.widget)).font(.headline)
                    if let info {
                        if let description = info.description { Text(description).font(.callout).foregroundStyle(.secondary) }
                        if let source = info.source { Text(source).font(.caption).foregroundStyle(.secondary) }
                    } else {
                        WarningLabel("No widget has this name. Is its plugin installed?")
                    }
                }
            }
            Section {
                PositionEditor(anchor: placement.anchor, x: placement.x, y: placement.y) { anchor, x, y in
                    change("Move") {
                        $0.anchor = anchor
                        $0.x = x
                        $0.y = y
                    }
                }
            } header: {
                ResetHeader(title: "Position", shown: editing.isMoved(.widget(index))) {
                    // Colors being picked save first, as before any change.
                    if !picked.isEmpty { change() }
                    editing.resetPlace(.widget(index))
                }
            }
            if !families.isEmpty || cards {
                Section {
                    if !families.isEmpty {
                        let options = (editing.themeFamily(placement) == nil ? [String?.none] : []) + families.map(Optional.some)
                        Picker("Size", selection: Binding(get: { editing.family(placement) }, set: { value in
                            change("Resize") { $0.rest["family"] = value.map(LuaValue.string) }
                        })) {
                            ForEach(options, id: \.self) { family in
                                Text(family.map(FamilyPicker.name) ?? "Original").tag(family)
                            }
                        }
                    }
                    if cards {
                        Toggle("Show card", isOn: Binding(get: { editing.card(placement) }, set: { value in change { $0.card = editing.cardValue(value, for: $0) } }))
                    }
                }
            }
            if !keys.isEmpty {
                Section {
                    ForEach(keys, id: \.self) { key in
                        if key == "location" {
                            LocationOption(location: (placement.opts[key] ?? inherited[key])?.string ?? "",
                                           placeName: (placement.opts["place_name"] ?? inherited["place_name"])?.string,
                                           privacy: model.privacy, permission: model.location.state, grant: model.location.grant) { location, name in
                                // Picked now: macOS asks, if it never did.
                                if LocationOption.isCurrent(location) { model.location.request() }
                                change {
                                    $0.opts[key] = .string(location) == inherited[key] ? nil : .string(location)
                                    $0.opts["place_name"] = name.map(LuaValue.string)
                                }
                            }
                        } else {
                            OptionRow(key: key, value: placement.opts[key] ?? inherited[key] ?? .nil, choices: info?.choices[key],
                                      own: info?.defaults[key], inherited: inherited[key],
                                      palette: Theme.fallback.palette.merging(editing.theme.palette) { $1 },
                                      pick: { pick(key, $0) },
                                      commit: { value in change { $0.opts[key] = value == inherited[key] ? nil : value } })
                        }
                    }
                } header: {
                    ResetHeader(title: "Options", shown: !placement.opts.isEmpty) { change("Reset Options of") { $0.opts = [:] } }
                }
            }
            Section {
                Button("Remove Widget", role: .destructive) {
                    // Its colors go with it.
                    saving?.cancel()
                    picked = [:]
                    draft = nil
                    selection = nil
                    editing.remove(index)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { if !picked.isEmpty { change() } }
    }

    /// Changes this widget as it is now, together with the colors picked so far, which save first: a color never
    /// lands after a later change, nor brings back an older copy of the widget. An option set back to what the theme
    /// gives it leaves settings.json. `verb` names the step Edit ▸ Undo takes back, as in "Move Clock".
    private func change(_ verb: String = "Change", _ edit: (inout EditorPlacement) -> Void = { _ in }) {
        saving?.cancel()
        saving = nil
        let colors = picked
        picked = [:]
        draft = nil
        guard editing.placements.indices.contains(index) else { return }
        var placement = editing.placements[index]
        let inherited = editing.inherited(placement)
        for (key, value) in colors { placement.opts[key] = value == inherited[key] ? nil : value }
        edit(&placement)
        editing.set(index, placement, action: "\(verb) \(EditorPlacement.title(placement.widget))")
    }

    /// A color being picked: the preview shows it at once, and it saves once the picking stops for a moment.
    private func pick(_ key: String, _ value: LuaValue) {
        picked[key] = value
        var list = editing.placements
        if list.indices.contains(index) {
            for (key, value) in picked { list[index].opts[key] = value }
            var settings = model.store.settings
            settings.setThemeEdit(editing.theme.id, "widgets", .array(list.map(\.settingsValue)))
            draft = settings
        }
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { change() }
        }
    }
}

/// The password field: where it sits. The theme sets its look.
private struct PasswordFieldInspector: View {
    let model: AppModel
    let editing: ThemeEditing

    var body: some View {
        let place = editing.authPlace
        Form {
            SaveProblem(model: model)
            Section {
                Text("Password Field").font(.headline)
            }
            Section {
                PositionEditor(anchor: place.anchor, x: place.x, y: place.y) { editing.setAuth(anchor: $0, x: $1, y: $2) }
            } header: {
                ResetHeader(title: "Position", shown: editing.isMoved(.passwordField)) { editing.resetPlace(.passwordField) }
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
        LabeledContent("Pinned to") {
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
    let own: LuaValue?
    /// The value before settings.json's: the theme's or init.lua's.
    let inherited: LuaValue?
    let palette: [String: String]
    /// A color being picked, which the panel saves.
    let pick: (LuaValue) -> Void
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
        } else if let text = OptionControl.textOrOff(value, own: own, inherited: inherited) {
            LabeledContent(label) { TextOrOff(text: value.string, own: text, commit: commit) }
        } else {
            switch value {
            case .bool(let on):
                Toggle(label, isOn: Binding(get: { on }, set: { commit(.bool($0)) }))
            case .int, .double:
                LabeledContent(label) {
                    NumberField(label: nil, value: value.number ?? 0, step: Self.step(key, value)) { commit(EditorPlacement.number($0)) }
                }
            case .string(let text) where Self.isColor(key, text, palette):
                LabeledContent(label) {
                    ColorChoice(value: text, palette: palette, pick: { pick(.string($0)) }, commit: { commit(.string($0)) })
                }
            case .string(let text):
                LabeledContent(label) { TextOption(text: text) { commit(.string($0)) } }
            default:
                EmptyView()
            }
        }
    }

    /// The options to show, the common ones first, then by name. Lists and tables are left out: only Lua changes them. So
    /// is place_name, which Location writes with the place.
    static func keys(inherited: [String: LuaValue], overrides: [String: LuaValue], choices: [String: [String]]) -> [String] {
        let keys = Set(inherited.keys).union(overrides.keys).union(choices.keys).filter { key in
            guard key != "place_name" else { return false }
            return switch overrides[key] ?? inherited[key] ?? .nil {
            case .bool, .int, .double, .string: true
            case .nil: choices[key] != nil
            default: false
            }
        }
        let first = ["style", "location", "units", "format", "text", "label", "title", "size", "weight", "design", "font", "color"]
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
    /// A color picked in the well, which the panel saves; a role from the menu saves at once.
    let pick: (String) -> Void
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
            ColorWell(title: "", hex: palette[value] ?? value, pick: pick)
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

/// Which control an option gets, where its value alone does not say.
enum OptionControl {
    /// The widget's own text for an option that holds text or false, such as a header the theme or init.lua turned
    /// off; nil for any other option. As a plain switch it would write true, which the widget cannot draw.
    static func textOrOff(_ value: LuaValue, own: LuaValue?, inherited: LuaValue?) -> String? {
        guard let text = own?.string, value == .bool(false) || (value.string != nil && inherited == .bool(false)) else { return nil }
        return text
    }
}

/// Text that can be off: a switch, and the text while it is on. On, it starts from the widget's own text.
private struct TextOrOff: View {
    let text: String?
    let own: String
    let commit: (LuaValue) -> Void
    /// Set as the switch turns the text off: the field then goes, and the text it held does not save. Text that comes
    /// back, by the switch or by Undo, saves again.
    @State private var off = false

    var body: some View {
        HStack(spacing: 8) {
            if let text {
                TextOption(text: text, commit: { off = false; commit(.string($0)) }, leave: { if !off { commit(.string($0)) } })
            }
            Toggle("", isOn: Binding(get: { text != nil }, set: { on in
                off = !on
                commit(on ? .string(own) : .bool(false))
            }))
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .onChange(of: text != nil) { _, on in if on { off = false } }
    }
}

/// A text option that saves when editing ends, not on every key.
private struct TextOption: View {
    let text: String
    let commit: (String) -> Void
    /// What saves the typed text when the field goes while it has the keyboard; commit, unless the caller says otherwise.
    var leave: ((String) -> Void)?
    @State private var current = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $current)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
            .focused($focused)
            .focusedValue(\.typing, true)
            .onSubmit { if current != text { commit(current) } }
            .onChange(of: focused) { if !focused, current != text { commit(current) } }
            .onAppear { current = text }
            .onChange(of: text) { current = text }
            // The panel can go before the field gives up the keyboard, as after Done or a click on the canvas.
            .onDisappear { if focused, current != text { (leave ?? commit)(current) } }
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
        HStack(spacing: 4) {
            if let label { Text(label).font(.callout).foregroundStyle(.secondary) }
            TextField(label ?? "", text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .focused($focused)
                .focusedValue(\.typing, true)
                .onSubmit(save)
                .onChange(of: focused) { if !focused { save() } }
            if let step {
                Stepper("", onIncrement: { commit(Self.round(value + step, step)) }, onDecrement: { commit(Self.round(value - step, step)) })
                    .labelsHidden()
            }
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: value) { text = Self.format(value) }
        // The panel can go before the field gives up the keyboard, as after Done or a click on the canvas.
        .onDisappear { if focused { save() } }
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

    /// "top-left" → "Top Left": a place's name, as the password field's row shows it and VoiceOver reads its cell.
    static func name(_ anchor: String) -> String {
        anchor.split(separator: "-").map(\.capitalized).joined(separator: " ")
    }

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
                        .accessibilityLabel(Self.name(name))
                        .accessibilityAddTraits(name == anchor ? .isSelected : [])
                    }
                }
            }
        }
        .padding(5)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned to")
    }
}

/// The background picker: the theme's own, an animated one of the built-in themes', or the wallpaper, an image, a video,
/// a color, or a gradient. Sliders and colors show in the preview as they change, and save when they stop.
private struct BackgroundEditor: View {
    @Bindable var model: AppModel
    let editing: ThemeEditing
    @Binding var draft: Settings?
    /// Colors being picked: shown at once, saved once the picking stops for a moment, with the next change, or when
    /// the panel goes away.
    @State private var picked: [String: LuaValue] = [:]
    @State private var saving: Task<Void, Never>?

    enum Kind: String, CaseIterable, Identifiable {
        case theme, animated, wallpaper, image, video, color, gradient
        var id: String { rawValue }
        var title: String {
            switch self {
            case .theme: "Original"
            case .animated: "Animated"
            case .wallpaper: "Desktop Picture"
            case .image: "Image"
            case .video: "Video"
            case .color: "Color"
            case .gradient: "Gradient"
            }
        }
    }

    private var store: SettingsStore { model.store }
    private var theme: Inspection.ThemeInfo { editing.theme }
    private var edit: LuaValue { store.settings.themeEdit(theme.id, "background") }

    private var kind: Kind {
        if edit.isNil { return .theme }
        if edit["shader"].string != nil { return .animated }
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
        .onDisappear { if !picked.isEmpty { save([:]) } }
        switch kind {
        case .theme:
            EmptyView()
        case .animated:
            ShaderGrid(choices: model.inspection.shaders, selected: edit["shader"].string, path: .standard(config: store.config)) { choice in
                // The dim stays: it keeps the text readable over the new one too.
                var table = choice.background.table ?? [:]
                table["dim"] = edit["dim"].isNil ? nil : edit["dim"]
                save(table, replacing: true)
            }
            slider("Dim", key: "dim", range: 0...0.8, fallback: 0)
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
        // Colors picked for the background being left go with it.
        saving?.cancel()
        picked = [:]
        let palette = theme.palette
        let value: LuaValue?
        switch kind {
        case .theme: value = nil
        case .animated:
            guard let first = model.inspection.shaders.first else { return }
            value = first.background
        case .wallpaper: value = .table(["wallpaper": .bool(true), "blur": .int(30), "dim": .double(0.25)])
        case .image, .video:
            guard let url = Self.chooseFile(types: kind == .image ? [.image] : [.movie]) else { return }
            value = .table([kind.rawValue: .string(url.path)])
        case .color: value = .table(["color": .string(palette["bg"] ?? "#101820")])
        case .gradient:
            value = .table(["gradient": .array([.string(palette["bg"] ?? "#101820"), .string(palette["accent"] ?? "#0a84ff")]),
                            "angle": .int(180)])
        }
        editing.record("Change Background") { store.update { $0.setThemeEdit(theme.id, "background", value) } }
        draft = nil
    }

    /// The background with `fields` changed.
    private func patched(_ fields: [String: LuaValue]) -> LuaValue {
        var table = edit.table ?? [:]
        for (key, value) in fields { table[key] = value }
        return .table(table)
    }

    /// Shows the change, with the colors picked so far, in the preview before it saves.
    private func preview(_ fields: [String: LuaValue]) {
        var settings = store.settings
        settings.setThemeEdit(theme.id, "background", patched(picked.merging(fields) { $1 }))
        draft = settings
    }

    /// Saves the change, with the colors picked so far. `replacing` saves `fields` alone, as another background.
    private func save(_ fields: [String: LuaValue], replacing: Bool = false) {
        saving?.cancel()
        saving = nil
        let value = replacing ? LuaValue.table(fields) : patched(picked.merging(fields) { $1 })
        picked = [:]
        editing.record("Change Background") { store.update { $0.setThemeEdit(theme.id, "background", value) } }
        draft = nil
    }

    /// A color being picked: the preview shows it at once, and it saves once the picking stops for a moment.
    private func pick(_ fields: [String: LuaValue]) {
        picked.merge(fields) { $1 }
        preview([:])
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { save([:]) }
        }
    }

    private func gradient(_ index: Int, _ hex: String) -> LuaValue {
        var colors = (picked["gradient"] ?? edit["gradient"]).array ?? [.string("#000000"), .string("#000000")]
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
        ColorWell(title: title, hex: get() ?? "#000000", pick: { pick(fields($0)) })
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

/// The animated backgrounds as pictures, as the Wallpaper settings show theirs: a click uses one.
private struct ShaderGrid: View {
    let choices: [Inspection.ShaderChoice]
    /// The shader in use, by name.
    let selected: String?
    let path: RuntimePath
    let pick: (Inspection.ShaderChoice) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12, alignment: .top)], spacing: 12) {
            ForEach(choices) { choice in
                ShaderTile(choice: choice, selected: choice.background["shader"].string == selected, path: path) { pick(choice) }
            }
        }
        // Room for the selection ring, which is drawn outside the pictures.
        .padding(5)
    }
}

/// One animated background: a frame of it, made in the background, and its name.
private struct ShaderTile: View {
    let choice: Inspection.ShaderChoice
    let selected: Bool
    let path: RuntimePath
    let pick: () -> Void
    @State private var image: CGImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let first = choice.background["colors"][0].string
        Button(action: pick) {
            VStack(spacing: 5) {
                // The theme's first color until the frame is made, so the tile never shows empty.
                (first.flatMap { Color(hex: $0) } ?? .black)
                    .aspectRatio(1.6, contentMode: .fit)
                    .overlay {
                        if let image {
                            Image(decorative: image, scale: 1).resizable().scaledToFill().transition(.opacity)
                        }
                    }
                    .clipShape(shape)
                    .hairline(cornerRadius: 6)
                    .pressOverlay(light: Design.isLight(first), in: shape)
                    // A 2.5-pt ring outside a 2.5-pt gap, concentric with the picture's corners: 6 + 2.5 + 2.5 = 11.
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(.selection, lineWidth: 2.5)
                                .padding(-5)
                        }
                    }
                Text(choice.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(PressHighlightStyle())
        .help(choice.name)
        .accessibilityLabel(choice.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(Motion.easeOut(duration: 0.2), value: image == nil)
        .task { image = await ShaderThumbnails.image(for: choice, path: path) }
    }
}

/// The theme's colors that people choose: its text, secondary text, and accent, and its cards' fill while its widgets
/// sit on glass or solid cards. Colors show on the canvas as they are picked, and save once the picking stops.
private struct ColorsEditor: View {
    let model: AppModel
    let editing: ThemeEditing
    @Binding var draft: Settings?
    /// Colors being picked, by role ("card" for the cards' fill): shown at once, saved once the picking stops for a
    /// moment, or when the panel goes away.
    @State private var picked: [String: String] = [:]
    @State private var saving: Task<Void, Never>?

    var body: some View {
        // Each row's: whichever goes last saves what is still being picked.
        Group {
            ForEach(ThemeEditing.colorRoles, id: \.role) { role, title in
                ColorWell(title: title, hex: picked[role] ?? editing.color(role), pick: { pick(role, $0) })
            }
            if editing.hasCardFill {
                ColorWell(title: "Cards", hex: picked["card"] ?? editing.cardFill(), pick: { pick("card", $0) })
            }
        }
        .onDisappear { if !picked.isEmpty { save() } }
    }

    private func pick(_ role: String, _ hex: String) {
        picked[role] = hex
        draft = editing.applying(picked, to: model.store.settings)
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { save() }
        }
    }

    private func save() {
        saving?.cancel()
        saving = nil
        let colors = picked
        picked = [:]
        draft = nil
        editing.setColors(colors)
    }
}

/// The theme's font: a family (the system font first), a weight, and, for the system font, a design. Text whose widget
/// sets its own weight or design keeps it.
private struct FontEditor: View {
    let editing: ThemeEditing

    /// The installed families, by name; AppKit's hidden ones (".SF NS", for one) left out.
    private static let families = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    var body: some View {
        let font = editing.font
        Picker("Family", selection: Binding(get: { font.family ?? "" }, set: { family in
            var next = font
            next.family = family.isEmpty ? nil : family
            // A design belongs to the system font only.
            if next.family != nil { next.design = nil }
            editing.setFont(next)
        })) {
            Text("System").tag("")
            Divider()
            // A family that is not installed stays listed, so the menu shows what the theme names.
            ForEach(Self.families.contains(font.family ?? "") || font.family == nil ? Self.families : [font.family!] + Self.families,
                    id: \.self) { Text($0).tag($0) }
        }
        Picker("Weight", selection: Binding(get: { font.weight ?? "regular" }, set: { weight in
            var next = font
            next.weight = weight
            editing.setFont(next)
        })) {
            ForEach(OptionRow.weights, id: \.self) { Text($0.capitalizedFirst).tag($0) }
        }
        if font.family == nil {
            Picker("Design", selection: Binding(get: { font.design ?? "default" }, set: { design in
                var next = font
                next.design = design == "default" ? nil : design
                editing.setFont(next)
            })) {
                ForEach(OptionRow.designs, id: \.self) { Text($0.capitalizedFirst).tag($0) }
            }
        }
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

/// A color well that reports each color as it is picked; the panel it is in saves it.
private struct ColorWell: View {
    let title: String
    let hex: String
    let pick: (String) -> Void
    @State private var color = Color.black

    var body: some View {
        ColorPicker(title, selection: Binding(get: { color }, set: { new in
            color = new
            if let value = new.hexString { pick(value) }
        }), supportsOpacity: false)
        .onAppear { color = Color(hex: hex) ?? .black }
        .onChange(of: hex) { color = Color(hex: hex) ?? .black }
    }
}

private extension FocusedValues {
    /// True while a text field in the inspector has the keyboard: Escape belongs to it, not to the page.
    @Entry var typing: Bool?
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
