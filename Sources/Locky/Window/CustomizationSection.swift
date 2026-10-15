import AppKit
import SwiftUI

/// Settings › General › Customization, the last section: the config folder with init.lua in an editor, init.lua's
/// problems at their line, a new theme, a new widget, the agent skill that writes them, and the log. It follows the
/// config as it changes on disk.
struct CustomizationSection: View {
    let model: AppModel
    /// Whether init.lua is there, read again whenever the config changes.
    @State private var exists = false
    /// Why Open in <editor> failed, under the folder's row.
    @State private var openError: String?
    /// Why a problem's Open failed, under that problem's row.
    @State private var problemError: (key: String, text: String)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var file: URL { model.store.config.appending(path: "init.lua") }

    var body: some View {
        // The config's own problems. A theme that does not load says so in the Themes window.
        let problems = Self.rows(model.inspection.problems, config: model.store.config)
        Section("Customization") {
            LabeledContent {
                if exists {
                    OpenInButton(model: model, file: file, error: $openError)
                } else {
                    Button("Create init.lua") {
                        CLI.ensureConfig()
                        exists = FileManager.default.fileExists(atPath: file.path)
                    }
                }
            } label: {
                Text("Config folder")
                Text(LuaError.shortenPaths(model.store.config.path))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if let openError {
                WarningLabel(openError)
            }
            ForEach(problems, id: \.key) { problem in
                LabeledContent {
                    if let file = problem.file, let line = problem.line {
                        // Waits for the editors, which the section looks for when it first shows.
                        Button("Open") { problemError = model.open(file, line: line).map { (problem.key, $0) } }
                            .disabled(model.editor == nil)
                    }
                } label: {
                    WarningLabel(problem.message)
                        .textSelection(.enabled)
                    if let file = problem.file, let line = problem.line {
                        Text("\(file.lastPathComponent), line \(line)")
                    }
                }
                if let problemError, problemError.key == problem.key {
                    WarningLabel(problemError.text)
                }
            }
            LabeledContent("Themes") {
                // File › New Theme…'s action, wherever it is in the responder chain.
                Button("New Theme…") { NSApp.sendAction(#selector(AppDelegate.newTheme(_:)), to: nil, from: nil) }
            }
            LabeledContent("Widgets") {
                Button("New Widget…") { model.newWidget = true }
            }
            AgentSkillRow(model: model)
            LabeledContent("Log") {
                Button("Open") {
                    LogFile.shared.write(level: "info", message: "log opened", source: "locky")
                    NSWorkspace.shared.open(LogFile.shared.url)
                }
            }
        }
        .animation(Motion.rows(reduceMotion), value: problems)
        .task(id: model.revision) { exists = FileManager.default.fileExists(atPath: file.path) }
        // A problem's Open needs the editors before the Open in button has shown.
        .task { await model.findEditors() }
        // A lock closes it (AppModel.locked): Return at the lock must not reach it.
        .sheet(isPresented: Binding(get: { model.newWidget }, set: { model.newWidget = $0 })) { NewWidgetSheet(model: model) }
    }

    /// The problem rows: each problem once, so its key names one row. When a problem goes, the rows below keep theirs.
    private static func rows(_ problems: [String], config: URL) -> [ConfigProblem] {
        var seen = Set<String>()
        return problems.map { ConfigProblem($0, config: config) }.filter { seen.insert($0.key).inserted }
    }
}

private extension ConfigProblem {
    /// A problem's row in the list: what it says, and where.
    var key: String { "\(file?.path ?? ""):\(line ?? 0): \(message)" }
}

/// "Open in <editor>", with a menu to choose the editor (and the terminal for terminal editors) and to show init.lua in
/// Finder. The choice saves to settings.json.
private struct OpenInButton: View {
    let model: AppModel
    let file: URL
    @Binding var error: String?

    var body: some View {
        if let found = model.editors, let editor = model.editor {
            Menu {
                Section("Open With") {
                    ForEach(found.editors) { candidate in
                        Toggle(candidate.name, isOn: Binding(get: { candidate.id == editor.id }, set: { _ in choose(editor: candidate) }))
                    }
                }
                if case .command = editor.kind, !found.terminals.isEmpty {
                    Section("In Terminal") {
                        ForEach(found.terminals) { terminal in
                            Toggle(terminal.name, isOn: Binding(get: { terminal.id == model.terminal?.id }, set: { _ in
                                model.store.update { $0["terminal"] = .string(terminal.id) }
                            }))
                        }
                    }
                }
                Divider()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: file.path) ? file : model.store.config])
                }
            } label: {
                Text("Open in \(editor.shortName)")
            } primaryAction: {
                error = model.open(file)
            }
            .fixedSize()
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func choose(editor: Editor) {
        model.store.update { $0["editor"] = .string(editor.id) }
        error = model.open(file)
    }
}

/// The agent skill: which agents have it, and Install, Update, or Show in Finder. It reads the agents' folders when it
/// shows and when Locky becomes active, as after an agent was installed.
struct AgentSkillRow: View {
    let model: AppModel
    private let skill = AgentSkill()
    @State private var states: [(agent: AgentSkill.Agent, state: AgentSkill.State)] = []
    @State private var error: String?

    var body: some View {
        let installed = states.filter { $0.state != .missing }.map(\.agent)
        LabeledContent {
            if states.contains(where: { $0.state == .outdated }) {
                Button("Update", action: install)
            } else if states.contains(where: { $0.state == .missing }) {
                Button("Install", action: install)
            } else if !installed.isEmpty {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(installed.map(skill.folder(for:))) }
            }
        } label: {
            Text("Agent skill")
            Text(Self.subtitle(agents: states.map(\.agent), installed: installed))
        }
        .onAppear(perform: read)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // A lock activates Locky at its start and at each keyboard reclaim: nothing is read then.
            if !model.locked { read() }
        }
        if let error {
            WarningLabel(error)
        }
    }

    /// Where the skill is, or what it does while it is nowhere.
    nonisolated static func subtitle(agents: [AgentSkill.Agent], installed: [AgentSkill.Agent]) -> String {
        if agents.isEmpty { return "Needs Claude Code, Codex, or a ~/.agents folder." }
        if installed.isEmpty { return "Lets coding agents make widgets and themes." }
        let names = installed.map(\.name)
        let list = names.count < 3 ? names.joined(separator: " and ") : names.dropLast().joined(separator: ", ") + ", and " + names.last!
        return "Installed in \(list)."
    }

    private func read() {
        states = skill.agents.map { ($0, skill.state(for: $0)) }
    }

    private func install() {
        do {
            try skill.install()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        read()
    }
}

/// New Widget: widgets have no builder in the window, so the sheet hands the work to a coding agent: the skill, a prompt
/// to start from, and the guide.
struct NewWidgetSheet: View {
    let model: AppModel
    static let prompt = "Make a Locky widget that shows the days until my vacation on December 20."
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Widget").font(.headline)
            Text("A widget is a small Lua file in your config folder. A coding agent with Locky's skill writes it for you, checks it, and looks at it on the lock screen until it is right.")
                .fixedSize(horizontal: false, vertical: true)
            Form {
                Section {
                    AgentSkillRow(model: model)
                }
                Section("Example Prompt") {
                    LabeledContent {
                        Button(copied ? "Copied" : "Copy", action: copy)
                    } label: {
                        Text(Self.prompt)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            // The form's own margins give way to the sheet's: its groups line up with the text above them.
            .frame(height: 194)
            .padding(.horizontal, -20)
            .padding(.vertical, -20)
            HStack {
                Button("Widget Guide", action: openGuide)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.prompt, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    /// The guide Locky ships, as a copy in the temporary folder: opened in place, an editor could change Locky.app.
    private func openGuide() {
        let guide = AgentSkill.bundled.appending(path: "references/create-widget.md")
        let copy = FileManager.default.temporaryDirectory.appending(path: "Locky Widget Guide.md")
        try? FileManager.default.removeItem(at: copy)
        guard (try? FileManager.default.copyItem(at: guide, to: copy)) != nil else { return }
        NSWorkspace.shared.open(copy)
    }
}
