import SwiftUI

/// The Themes window's home, while no theme is being customized: the theme in use, live, and every theme as a picture.
/// A click on a tile makes it the theme a lock uses. The grid is one stop in the key loop: the arrow keys change the
/// theme in use as a click does, and Return opens Customize for it.
struct ThemeGallery: View {
    let model: AppModel
    /// The theme that did not load on the last lock, until a file of it changes or Dismiss.
    @State private var failure: ThemeFailure?
    @State private var scheduling = false
    /// Why Import Theme… failed, for its alert.
    @State private var problem: ImportProblem?
    /// Why Move to Trash left a theme where it was, for its alert.
    @State private var trashError: String?
    @State private var gridWidth: CGFloat = 0
    @FocusState private var gridFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Under a schedule the theme in use follows the clock and the Mac's appearance, and SwiftUI observes neither:
        // the timeline reads the page again each minute (a slot starts on the minute), and colorScheme when the
        // appearance changes. So In Use, the preview, and the ring change with the slot while the window stays open.
        let _ = colorScheme
        TimelineView(.everyMinute) { _ in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if let failure {
                            FailureBanner(failure: failure, model: model, dismiss: dismissFailure)
                                .transition(.opacity)
                        }
                        // Nothing saves settings.json while it has an error, so a click on a tile changes nothing.
                        if model.store.problem != nil {
                            HStack(spacing: 8) {
                                WarningLabel("settings.json has an error, so the theme can't change.")
                                Button("Open Settings") { model.openWindow(.settings) }
                                    .buttonStyle(.link)
                            }
                        }
                        header
                        if model.inspection.loaded {
                            grid(proxy)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    // 24 on every side: the top's last 7 are the scroll view's.
                    .padding(.horizontal, 24)
                    .padding(.top, 17)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 1280)
                    .frame(maxWidth: .infinity)
                }
                // An arrow key scrolls a tile only as far as its top, and the in-use ring is drawn 7 pt outside the tile:
                // 7 pt more at the top keeps the ring clear of the toolbar.
                .safeAreaPadding(.top, 7)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Schedule", systemImage: "clock.arrow.2.circlepath") { scheduling = true }
                    .help("Change the theme by time of day or with Light and Dark mode")
                    .popover(isPresented: $scheduling, arrowEdge: .bottom) { SchedulePopover(model: model) }
                Button("Preview", systemImage: "play.rectangle") { model.preview(nil) }
                    .help("Show the theme in use full size")
            }
        }
        .fileImporter(isPresented: Binding(get: { model.importing }, set: { model.importing = $0 }), allowedContentTypes: [ThemeFile.type]) { result in
            if case .success(let url) = result { importTheme(url) }
        }
        .alert(problem?.title ?? "", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } }), presenting: problem) { _ in
            Button("OK") {}
        } message: { problem in
            Text(problem.message)
        }
        .alert("Can't Move the Theme to the Trash", isPresented: Binding(get: { trashError != nil }, set: { if !$0 { trashError = nil } }),
               presenting: trashError) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        // The record stops counting once a file of its theme changes, so it is read again with the config. Not before the
        // first read: the summary needs the themes' names, and the record its theme's package.
        .task(id: model.revision) {
            guard model.inspection.loaded else { return }
            failure = ThemeFailure.current(.standard, inspection: model.inspection, config: model.store.config)
        }
    }

    // MARK: The theme in use

    private var header: some View {
        let id = model.activeTheme
        let info = model.inspection.theme(id)
        return HStack(alignment: .center, spacing: 24) {
            preview(id, info: info)
                .aspectRatio(1.6, contentMode: .fit)
                .containerRelativeFrame(.horizontal) { width, _ in min(max(width * 0.45, 280), 440) }
                .previewFrame()
                .accessibilityHidden(true)
            // Empty until the config is read: before that, the name would be the raw id, such as "default".
            VStack(alignment: .leading, spacing: 4) {
                if model.inspection.loaded {
                    Text("In Use")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(info?.name ?? id)
                        .font(.largeTitle.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let description = info?.description {
                        Text(description)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    if let schedule = model.store.settings.schedule {
                        Label(schedule.summary(model.inspection), systemImage: "clock.arrow.2.circlepath")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    Button("Customize…") { model.customize(id) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!loads(id))
                        .padding(.top, 8)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The live lock screen of `id`. `info` is set after the initializer, so this call does not depend on where
    /// ThemePreview declares it.
    private func preview(_ id: String, info: Inspection.ThemeInfo?) -> ThemePreview {
        var preview = ThemePreview(theme: id, settings: model.store.settings, sources: model.inspection.sources,
                                   config: model.store.config, alwaysLive: model.screenshots)
        preview.info = info
        return preview
    }

    // MARK: The grid

    private func grid(_ proxy: ScrollViewProxy) -> some View {
        let themes = model.inspection.themesByName
        let active = model.activeTheme
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16, alignment: .top)],
                         alignment: .leading, spacing: 20) {
            ForEach(themes) { info in
                ThemeTile(info: info, inUse: info.id == active, canTrash: model.canTrash(info.id),
                          use: { use(info.id) }, customize: { model.customize(info.id) },
                          preview: { model.preview(info.id) }, trash: { trash(info.id) })
                    .id(info.id)
            }
        }
        .focusable()
        // The ring, drawn in .selection, already shows whether the grid has focus.
        .focusEffectDisabled()
        .focused($gridFocused)
        // An explicit assignment moves focus where .defaultFocus does not.
        .onAppear { gridFocused = true }
        .onMoveCommand { direction in
            guard let next = Self.neighbor(of: model.activeTheme, in: themes, columns: Self.columns(width: gridWidth),
                                           direction: direction, rightToLeft: layoutDirection == .rightToLeft) else { return }
            model.use(next)
            proxy.scrollTo(next)
        }
        .onKeyPress(.return) {
            guard loads(model.activeTheme) else { return .ignored }
            model.customize(model.activeTheme)
            return .handled
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    /// The grid's columns at `width`: the adaptive item's own rule, with its 180-pt minimum and 16-pt spacing.
    static func columns(width: CGFloat) -> Int {
        max(1, Int((width + 16) / (180 + 16)))
    }

    /// The theme an arrow key moves to from `id`: the next one that loads in that direction, a row away for up and
    /// down. nil past either end. Left and right swap for a right-to-left layout, which starts on the right.
    static func neighbor(of id: String, in themes: [Inspection.ThemeInfo], columns: Int, direction: MoveCommandDirection,
                         rightToLeft: Bool) -> String? {
        guard var index = themes.firstIndex(where: { $0.id == id }) else { return nil }
        let step = switch direction {
        case .left: rightToLeft ? 1 : -1
        case .right: rightToLeft ? -1 : 1
        case .up: -columns
        case .down: columns
        @unknown default: 0
        }
        guard step != 0 else { return nil }
        repeat {
            index += step
            guard themes.indices.contains(index) else { return nil }
        } while themes[index].error != nil
        return themes[index].id
    }

    // MARK: Actions

    /// Whether Customize can open for `id`: a theme the config's read lists, and one that loads.
    private func loads(_ id: String) -> Bool {
        model.inspection.theme(id).map { $0.error == nil } == true
    }

    /// A click on a tile: the grid takes focus too, as a click on the grid does.
    private func use(_ id: String) {
        gridFocused = true
        model.use(id)
    }

    /// No alert first: the Trash is the undo.
    private func trash(_ id: String) {
        do {
            try model.trash(id)
        } catch {
            trashError = error.localizedDescription
        }
    }

    private func dismissFailure() {
        UserDefaults.standard.removeObject(forKey: ThemeFailure.key)
        withAnimation(Motion.rows(reduceMotion)) { failure = nil }
    }

    /// Imports a file Export Theme… wrote, and opens it in Customize. Every check runs, so nothing asks first; Move to
    /// Trash removes a wrong one.
    private func importTheme(_ url: URL) {
        let config = model.store.config
        let reading = url.startAccessingSecurityScopedResource()
        defer { if reading { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= ThemeFile.maxSize, let text = try? String(contentsOf: url, encoding: .utf8) else {
            problem = ThemeImport.notExported(config: config)
            return
        }
        switch ThemeImport.check(text, inspection: model.inspection, config: config) {
        case .failure(let failure):
            problem = failure
        case .success(let file):
            Task {
                do {
                    let id = try await model.install(file)
                    model.customize(id)
                } catch {
                    problem = ImportProblem(title: "Can't Import This Theme", message: (error as? LuaError)?.message ?? error.localizedDescription)
                }
            }
        }
    }
}

/// One theme in the grid: its picture and its name. The ring around the picture marks the theme in use.
private struct ThemeTile: View {
    let info: Inspection.ThemeInfo
    let inUse: Bool
    let canTrash: Bool
    let use: () -> Void
    let customize: () -> Void
    let preview: () -> Void
    let trash: () -> Void

    var body: some View {
        // A theme that does not load has only Move to Trash, and only when it is the person's own.
        if info.error == nil || canTrash {
            button.contextMenu {
                if info.error == nil {
                    Button("Customize…", action: customize)
                    Button("Preview", action: preview)
                }
                if canTrash {
                    if info.error == nil { Divider() }
                    Button("Move to Trash", action: trash)
                }
            }
        } else {
            button
        }
    }

    private var button: some View {
        // The error's first line, for a theme that does not load.
        let error = info.error.map { LuaError($0).summary }
        return Button(action: use) {
            VStack(alignment: .leading, spacing: 12) {
                thumbnail
                Text(info.name)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressHighlightStyle())
        // The grid is the one stop in the key loop, not each of its tiles.
        .focusable(false)
        .disabled(error != nil)
        .help(error ?? info.description ?? "")
        .accessibilityLabel(error == nil ? info.name : "\(info.name), does not load")
        // After .help, which would make its text the hint.
        .accessibilityHint(error ?? "Uses this theme when the Mac locks.")
        .accessibilityCustomContent(AccessibilityCustomContentKey("Description"), info.description.map { Text($0) })
        .accessibilityAddTraits(inUse ? .isSelected : [])
    }

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: Design.Radius.thumbnail, style: .continuous)
        return Color.clear
            .aspectRatio(1.6, contentMode: .fit)
            .overlay { picture }
            .clipShape(shape)
            .hairline(cornerRadius: Design.Radius.thumbnail)
            .pressOverlay(light: Design.isLight(info.palette["bg"]), in: shape)
            .opacity(info.error == nil ? 1 : 0.4)
            .overlay {
                if info.error != nil {
                    // A shadow edges the triangle: in Light Mode a dimmed picture can be as light as orange.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                }
            }
            // A 3-pt ring outside a 4-pt gap, concentric with the picture's corners: 8 + 4 + 3 = 15.
            .overlay {
                if inUse {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(.selection, lineWidth: 3)
                        .padding(-7)
                }
            }
    }

    /// The theme's picture, else its own colors with a clock. A theme that does not load shows no clock: its warning
    /// symbol takes the middle.
    @ViewBuilder private var picture: some View {
        if let image = ThemeThumbnails.image(for: info) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            let color = { (role: String, fallback: String) in Color(hex: info.palette[role] ?? fallback) ?? .black }
            LinearGradient(colors: [color("bg", "#000000"), color("surface", "#1c1c1e")], startPoint: .top, endPoint: .bottom)
                .overlay {
                    if info.error == nil {
                        VStack(spacing: 6) {
                            Text("12:00")
                                .font(.system(.title2, design: .rounded).weight(.semibold))
                                .foregroundStyle(color("fg", "#ffffff"))
                            Circle()
                                .fill(color("accent", "#0a84ff"))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
        }
    }
}

/// The last lock's theme that did not load, and the theme Locky showed instead. Open goes to the file and line the
/// error names, as a Lua Config problem's Open does.
private struct FailureBanner: View {
    let failure: ThemeFailure
    let model: AppModel
    let dismiss: () -> Void
    /// Why the editor did not open, if it did not.
    @State private var openError: String?

    var body: some View {
        let place = ConfigProblem(failure.message, config: model.store.config)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(failure.summary(model.inspection))
                    .font(.headline)
                Text(failure.message)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let openError { WarningLabel(openError) }
            }
            Spacer()
            if let file = place.file, let line = place.line {
                Button("Open") { openError = model.open(file, line: line) }
                    // The editors are found once, before the first Open.
                    .task { await model.findEditors() }
            }
            Button("Dismiss", action: dismiss)
        }
        .padding(16)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: Design.Radius.tile, style: .continuous))
    }
}

/// An import that failed, in words for its alert. An Error, so a `Result` can carry it.
struct ImportProblem: Error, Equatable {
    let title: String
    let message: String
}

/// Import Theme…'s checks on a file's text, after its size: only a file Export Theme… wrote, made from one of Locky's
/// own themes, with only Locky's own widgets. A theme file sets widgets' options, and a plugin's widget could run one
/// as a command. The install then tries the theme before it lands among the person's themes.
enum ThemeImport {
    static func check(_ text: String, inspection: Inspection, config: URL) -> Result<ThemeFile, ImportProblem> {
        guard let file = ThemeFile.parse(text) else { return .failure(notExported(config: config)) }
        guard ThemeFile.isBuiltIn(file.base) else {
            return .failure(ImportProblem(title: "Can't Import This Theme", message: "It is made from “\(file.base)”, which is not one of Locky's themes."))
        }
        let foreign = file.foreignWidgets(inspection.widgets)
        guard foreign.isEmpty else {
            return .failure(ImportProblem(title: "Can't Import This Theme",
                                          message: "It uses widgets from plugins: \(foreign.joined(separator: ", ")). Locky imports only themes that use its own widgets."))
        }
        return .success(file)
    }

    /// A file that is too big, cannot be read, or is not one Export Theme… wrote.
    static func notExported(config: URL) -> ImportProblem {
        ImportProblem(title: "Can't Import This File",
                      message: "Choose a file made with Export Theme…. A theme written in Lua goes in \(LuaError.shortenPaths(config.path))/themes.")
    }
}
