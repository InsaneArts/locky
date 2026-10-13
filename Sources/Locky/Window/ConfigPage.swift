import AppKit
import SwiftUI

/// Settings › Lua Config: init.lua opens in an editor, its problems open at their line, and the log opens too. It
/// follows the config as it changes on disk.
struct ConfigPage: View {
    let model: AppModel
    /// Whether init.lua is there, read again whenever the config changes.
    @State private var exists = false
    @State private var openError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var file: URL { model.store.config.appending(path: "init.lua") }

    var body: some View {
        let problems = model.inspection.problems.map { ConfigProblem($0, config: model.store.config) }
        Form {
            Section {
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
                    Text("init.lua")
                    Text(exists ? LuaError.shortenPaths(file.path) : "Not created")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if let openError {
                    WarningLabel(openError)
                }
            } footer: {
                Text(exists ? "What you change in these settings is saved in settings.json, next to init.lua, and wins over it."
                    : "Locky runs init.lua each time the screen locks, like Neovim's init.lua. It starts with commented examples.")
            }
            Section {
                LabeledContent {
                    Button("Open") {
                        LogFile.shared.write(level: "info", message: "log opened", source: "locky")
                        NSWorkspace.shared.open(LogFile.shared.url)
                    }
                } label: {
                    Text("Log")
                    Text("What plugins print, and every error.")
                }
            }
            if !problems.isEmpty {
                Section("Problems") {
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                        LabeledContent {
                            if let file = problem.file, let line = problem.line {
                                // Waits for the editors, which the pane looks for when it first shows.
                                Button("Open") { openError = model.open(file, line: line) }
                                    .disabled(model.editor == nil)
                            }
                        } label: {
                            Text(problem.message)
                                .textSelection(.enabled)
                            if let file = problem.file, let line = problem.line {
                                Text("\(file.lastPathComponent), line \(line)")
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .animation(Motion.rows(reduceMotion), value: problems)
        .task(id: model.revision) { exists = FileManager.default.fileExists(atPath: file.path) }
        // A problem's Open needs the editors before the Open in button has shown.
        .task { await model.findEditors() }
    }
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
