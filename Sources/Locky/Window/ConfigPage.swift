import AppKit
import SwiftUI

/// The config, read-only: init.lua, or settings.json (what this window writes), with line numbers and the
/// config's problems marked on their lines. It follows the files as they change on disk.
struct ConfigPage: View {
    @Bindable var model: AppModel
    @State private var file: ConfigFile = .initLua
    @State private var text: String?
    @State private var check: (running: Bool, report: String?) = (false, nil)

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
            header
            Divider()
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
            Spacer()
            Button("Check", systemImage: "checkmark.seal") { runCheck() }
                .disabled(check.running)
                .help("Run init.lua, plugins, and the theme, and report every error (locky check)")
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: url.path) ? url : model.store.config])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var problems: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.inspection.problems.enumerated()), id: \.offset) { _, problem in
                    Label(LuaError(problem).summary, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
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
        text = try? String(contentsOf: url, encoding: .utf8)
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
        let styled = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
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
