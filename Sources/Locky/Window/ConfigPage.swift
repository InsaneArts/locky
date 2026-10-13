import AppKit
import SwiftUI

/// The config, read-only: init.lua, or settings.json (what this window writes), with line numbers and the
/// config's problems marked on their lines. It follows the files as they change on disk.
struct ConfigPage: View {
    @Bindable var model: AppModel
    @State private var file: ConfigFile = .initLua
    @State private var text: String?
    @State private var check: (running: Bool, report: String?) = (false, nil)
    @State private var openError: String?

    enum ConfigFile: String, CaseIterable, Identifiable {
        case initLua = "init.lua"
        case settings = "settings.json"
        var id: String { rawValue }
    }

    private var url: URL { model.store.config.appending(path: file.rawValue) }

    /// init.lua's problems, by line.
    private var problemLines: [Int: String] {
        guard file == .initLua else { return [:] }
        var lines: [Int: String] = [:]
        for problem in model.inspection.problems {
            let summary = LuaError(problem).summary
            if let match = summary.firstMatch(of: /init\.lua:(\d+):/), let line = Int(match.1) { lines[line] = summary }
        }
        return lines
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Changes made in this window are saved to settings.json and override init.lua. Use Reset to go back to init.lua.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
            header
            Divider()
            if let openError {
                Label(openError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Divider()
            }
            if !model.inspection.problems.isEmpty || check.report != nil {
                problems
                Divider()
            }
            if let text {
                CodeView(text: text, language: file == .initLua ? .lua : .json, marked: problemLines)
            } else {
                ContentUnavailableView {
                    Label("No \(file.rawValue) Yet", systemImage: "doc.badge.plus")
                } description: {
                    Text(file == .initLua
                         ? "init.lua is your Lua config, like Neovim's. Locky runs it each time the screen locks."
                         : "This window writes settings.json when you change a setting.")
                } actions: {
                    if file == .initLua {
                        Button("Create init.lua with Examples") {
                            CLI.ensureConfig()
                            load()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(file.rawValue)-\(model.revision)") { load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("File", selection: $file) {
                ForEach(ConfigFile.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text(LuaError.shortenPaths(url.path))
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .layoutPriority(-1)
            Spacer(minLength: 0)
            OpenInButton(model: model, file: url, error: $openError)
            // In a narrow window, the buttons show only their icons instead of shortened titles.
            ViewThatFits(in: .horizontal) {
                actions.fixedSize()
                actions.labelStyle(.iconOnly).fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Check", systemImage: "checkmark.seal") { runCheck() }
                .disabled(check.running)
                .help("Run init.lua, plugins, and the theme, and report every error (locky check)")
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: url.path) ? url : model.store.config])
            }
            .help("Show the file in Finder")
            Button("Open Log", systemImage: "doc.text.magnifyingglass") {
                LogFile.shared.write(level: "info", message: "log opened", source: "locky")
                NSWorkspace.shared.open(LogFile.shared.url)
            }
            .help("What plugins print, and every error: ~/Library/Logs/Locky/locky.log")
        }
    }

    private var problems: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.inspection.problems.enumerated()), id: \.offset) { _, problem in
                    let summary = LuaError(problem).summary
                    let place = place(of: summary)
                    HStack(alignment: .firstTextBaseline) {
                        Label(summary, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                        if let place {
                            Spacer()
                            Button("Open at Line \(place.line)") { openError = model.open(place.file, line: place.line) }
                                .buttonStyle(.link)
                        }
                    }
                }
                if check.running {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                    }
                } else if let report = check.report {
                    Text(report)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: 180)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func load() {
        // Invalid UTF-8 shows as U+FFFD instead of hiding the whole file.
        text = (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// "~/.config/locky/init.lua:12: …" → that file and line 12. Lua shortens a long path to "…/init.lua";
    /// that one is the config's.
    func place(of problem: String) -> (file: URL, line: Int)? {
        guard let match = problem.firstMatch(of: /^(.+?\.lua):(\d+):/), let line = Int(match.2) else { return nil }
        let path = (String(match.1) as NSString).expandingTildeInPath
        if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) { return (URL(fileURLWithPath: path), line) }
        if path.hasPrefix("..."), path.hasSuffix("/init.lua") { return (model.store.config.appending(path: "init.lua"), line) }
        return nil
    }

    private func runCheck() {
        check = (true, nil)
        Task {
            let report = await Task.detached { CLI.checkReport(theme: nil) }.value
            check = (false, report.text)
        }
    }
}

/// A read-only code view: monospaced, selectable, line numbers in the gutter, and marked lines tinted.
struct CodeView: NSViewRepresentable {
    enum Language { case lua, json }

    let text: String
    let language: Language
    /// Lines (from 1) to tint, with what is wrong there.
    var marked: [Int: String] = [:]

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.drawsBackground = false
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        let ruler = LineNumberRuler(textView: textView)
        scroll.verticalRulerView = ruler
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let styled = language == .lua
            ? NSMutableAttributedString(attributedString: LuaHighlighter.highlight(text, font: font))
            : NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        // Tint the lines with problems.
        let lines = text.components(separatedBy: "\n")
        var offset = 0
        for (index, line) in lines.enumerated() {
            let length = (line as NSString).length
            if marked[index + 1] != nil {
                styled.addAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.18),
                                    range: NSRange(location: offset, length: min(length + 1, styled.length - offset)))
            }
            offset += length + 1
        }
        if textView.textStorage?.isEqual(to: styled) != true {
            textView.textStorage?.setAttributedString(styled)
        }
        (scroll.verticalRulerView as? LineNumberRuler)?.marked = Set(marked.keys)
        scroll.verticalRulerView?.needsDisplay = true
    }
}

/// Line numbers beside an NSTextView; marked lines show in orange.
final class LineNumberRuler: NSRulerView {
    var marked: Set<Int> = [] { didSet { needsDisplay = true } }
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification,
                                               object: textView.enclosingScrollView?.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSText.didChangeNotification, object: textView)
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let text = textView.string as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // The number of the first visible line: count the line breaks before it.
        var line = 1
        text.enumerateSubstrings(in: NSRange(location: 0, length: characters.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            line += 1
        }
        if characters.location == 0 { line = 1 }
        var index = characters.location
        let inset = textView.textContainerInset.height
        while index <= NSMaxRange(characters), index <= text.length {
            let lineRange = text.lineRange(for: NSRange(location: min(index, max(text.length - 1, 0)), length: 0))
            let glyph = layout.glyphIndexForCharacter(at: min(lineRange.location, max(text.length - 1, 0)))
            var lineRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            lineRect.origin.y += inset - visible.origin.y
            let color = marked.contains(line) ? NSColor.systemOrange : NSColor.tertiaryLabelColor
            let label = "\(line)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: lineRect.minY + (lineRect.height - size.height) / 2), withAttributes: attributes)
            line += 1
            if NSMaxRange(lineRange) <= index || NSMaxRange(lineRange) >= text.length { break }
            index = NSMaxRange(lineRange)
        }
    }
}

/// "Open in <editor>", with a menu to choose the editor (and the terminal for terminal editors). The choice
/// saves to settings.json.
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
            } label: {
                Label("Open in \(editor.name)", systemImage: "square.and.pencil")
            } primaryAction: {
                error = model.open(file)
            }
            .fixedSize()
            .disabled(!FileManager.default.fileExists(atPath: file.path))
        } else {
            ProgressView().controlSize(.small)
                .task { await model.findEditors() }
        }
    }

    private func choose(editor: Editor) {
        model.store.update { $0["editor"] = .string(editor.id) }
        error = model.open(file)
    }
}
