import SwiftUI

/// The Themes window's home, while no theme is being customized, laid out as Scene lays out its themes: every theme in
/// the sidebar, and the theme in use on a page of its own, live, over its own colors. The sidebar's selection is the
/// theme a lock uses: a click or an arrow key changes it, and Return opens Customize for it.
struct ThemeGallery: View {
    let model: AppModel
    /// The theme that did not load on the last lock, until a file of it changes or Dismiss.
    @State private var failure: ThemeFailure?
    /// Why Import Theme… failed, for its alert.
    @State private var problem: ImportProblem?
    /// Why Move to Trash left a theme where it was, for its alert.
    @State private var trashError: String?
    /// Why the editor did not open at the error of the theme in use, if it did not.
    @State private var openError: String?
    @FocusState private var listFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Under a schedule the theme in use follows the clock and the Mac's appearance, and SwiftUI observes neither:
        // the timeline reads the page again each minute (a slot starts on the minute), and colorScheme when the
        // appearance changes. So the page and the selection change with the slot while the window stays open.
        let _ = colorScheme
        TimelineView(.everyMinute) { _ in
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
            } detail: {
                page
            }
        }
        .toolbar(removing: .title)
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

    // MARK: The sidebar

    private var sidebar: some View {
        List(selection: Binding(get: { model.activeTheme as String? }, set: { id in if let id { model.use(id) } })) {
            if model.inspection.loaded {
                Section("Themes") {
                    ForEach(model.inspection.themesByName) { info in
                        ThemeRow(info: info, problem: info.error.map { ConfigProblem($0, config: model.store.config) })
                            .tag(info.id)
                            // A theme that does not load is not one a lock can use.
                            .selectionDisabled(info.error != nil)
                            .contextMenu { actions(info) }
                    }
                }
            }
        }
        .overlay { if !model.inspection.loaded { ProgressView().controlSize(.small) } }
        .focused($listFocused)
        // An explicit assignment moves focus where .defaultFocus does not, on the next turn of the run loop. After
        // Customize, the window gives the list the keyboard once the canvas has left it (LockyWindowController).
        .onAppear { DispatchQueue.main.async { listFocused = true } }
        .onKeyPress(.return) {
            guard loads(model.activeTheme) else { return .ignored }
            model.customize(model.activeTheme)
            return .handled
        }
    }

    /// A theme that does not load has only Move to Trash, and only when it is the person's own.
    @ViewBuilder private func actions(_ info: Inspection.ThemeInfo) -> some View {
        if info.error == nil {
            Button("Customize…") { model.customize(info.id) }
            Button("Preview") { model.preview(info.id) }
        }
        if model.canTrash(info.id) {
            if info.error == nil { Divider() }
            Button("Move to Trash") { trash(info.id) }
        }
    }

    // MARK: The theme in use

    private var page: some View {
        let id = model.activeTheme
        let info = model.inspection.theme(id)
        let look = ThemeLook(palette: info?.palette ?? [:])
        return GeometryReader { viewport in
            // As wide as the page, and the preview at most 60% of the window's height, so the name and Customize stay in
            // view. The words under the preview line up with its edges.
            let width = max(280, min(min(viewport.size.width, 1040) - 72, viewport.size.height * 0.6 * 1.6))
            ScrollView {
                VStack(spacing: 22) {
                    if let failure {
                        FailureBanner(failure: failure, model: model, dismiss: dismissFailure)
                            .transition(.opacity)
                    }
                    // Nothing saves settings.json while it has an error, so a click on a theme changes nothing.
                    if model.store.problem != nil {
                        HStack(spacing: 8) {
                            WarningLabel("settings.json has an error, so the theme can't change.")
                            Button("Open Settings") { model.openWindow(.settings) }
                                .buttonStyle(.link)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    preview(id, info: info)
                        .frame(height: width / 1.6)
                        .hairline(cornerRadius: 10)
                        .shadow(color: .black.opacity(0.3), radius: 30, y: 16)
                        .accessibilityHidden(true)
                    // Empty until the config is read: before that, the name would be the raw id, such as "default".
                    if model.inspection.loaded { header(id, info: info, look: look) }
                }
                .frame(width: width)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .background { AmbientBackground(info: info, id: id, isLight: look.isLight) }
        // The page takes the theme's own light or dark look, as Scene's theme pages do.
        .environment(\.colorScheme, look.isLight ? .light : .dark)
        .toolbar {
            // Without a title, the buttons would sit next to the sidebar.
            if #available(macOS 26, *) { ToolbarSpacer(.flexible) }
            ToolbarItemGroup {
                // File › New Theme…'s action, which the app's delegate answers.
                Button("New Theme", systemImage: "plus") { NSApp.sendAction(#selector(AppDelegate.newTheme(_:)), to: nil, from: nil) }
                    .help("Make a new theme and customize it")
                Button("Schedule", systemImage: "clock.arrow.2.circlepath") { model.scheduling = true }
                    .help("Change the theme by time of day or with Light and Dark mode")
                    .popover(isPresented: Binding(get: { model.scheduling }, set: { model.scheduling = $0 }), arrowEdge: .bottom) {
                        SchedulePopover(model: model)
                    }
            }
        }
        // An editor that did not open belongs to the theme it was asked for.
        .onChange(of: id) { openError = nil }
    }

    private func header(_ id: String, info: Inspection.ThemeInfo?, look: ThemeLook) -> some View {
        // Why Customize… is dimmed: the theme's error, in the words Lua Config uses, or that no theme has the id, such as
        // after its file was deleted in Finder.
        let problem: ConfigProblem? = if let info { info.error.map { ConfigProblem($0, config: model.store.config) } }
            else { ConfigProblem("Locky has no theme named “\(id)”.", config: model.store.config) }
        return HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(info?.name ?? id)
                        .font(.system(size: 32, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Pill(text: "In Use", color: Color(hex: look.accent) ?? .accentColor)
                }
                if let problem {
                    HStack(spacing: 8) {
                        WarningLabel(problem.message)
                            .lineLimit(3)
                            .textSelection(.enabled)
                        OpenProblemButton(model: model, problem: problem, error: $openError)
                            .buttonStyle(.link)
                    }
                    if let openError { WarningLabel(openError) }
                } else if let description = info?.description {
                    Text(description)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if info != nil { PaletteDots(colors: look.swatches, size: 14).padding(.top, 6) }
                if let schedule = model.store.settings.schedule {
                    Label(schedule.summary(model.inspection), systemImage: "clock.arrow.2.circlepath")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 12)
            Button("Preview") { model.preview(nil) }
                .buttonStyle(CapsuleButtonStyle(fill: .primary.opacity(0.1), label: .primary))
                .help("Show the theme in use full size")
            Button("Customize…") { model.customize(id) }
                .buttonStyle(CapsuleButtonStyle(fill: Color(hex: look.accent) ?? .accentColor, label: Color(hex: look.onAccent) ?? .white))
                .disabled(!loads(id))
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

    // MARK: Actions

    /// Whether Customize can open for `id`: a theme the config's read lists, and one that loads.
    private func loads(_ id: String) -> Bool {
        model.inspection.theme(id).map { $0.error == nil } == true
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

/// One theme in the sidebar, as Scene's rows show a theme: its picture, its name, and its colors.
private struct ThemeRow: View {
    let info: Inspection.ThemeInfo
    /// Why the theme does not load, in the words the page and Lua Config use.
    let problem: ConfigProblem?

    var body: some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(width: 52, height: 34)
                .overlay { ThemePicture(info: info) }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .hairline(cornerRadius: 6, lineWidth: 0.5)
                .overlay {
                    if problem != nil {
                        // A shadow edges the triangle: in Light Mode a dimmed picture can be as light as orange.
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    }
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(info.name).lineLimit(1)
                PaletteDots(colors: ThemeLook(palette: info.palette).swatches, size: 7)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .opacity(problem == nil ? 1 : 0.4)
        .help(problem?.described ?? info.description ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(problem == nil ? info.name : "\(info.name), does not load")
        // After .help, which would make its text the hint.
        .accessibilityHint(problem?.message ?? "Uses this theme when the Mac locks.")
        .accessibilityCustomContent(AccessibilityCustomContentKey("Description"), info.description.map { Text($0) })
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
            OpenProblemButton(model: model, problem: place, error: $openError)
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
