import Foundation
import UniformTypeIdentifiers

/// A theme the window makes (Duplicate Theme, Export Theme, Import Theme): a built-in or installed theme by id, with
/// the editor's changes, under a name of its own. On disk it is one .lua file that Lua loads with
/// locky.theme.derive, holding the changes as JSON. Reading one runs nothing: the file is taken apart as text, and
/// an imported one is written again from what it holds, so no code in it reaches the themes folder.
struct ThemeFile: Equatable {
    /// The theme it is made from.
    var base: String
    var name: String
    /// Changes as settings.json's themes.<id> holds them, applied in order.
    var edits: [LuaValue]

    static let maxSize = 1 << 20
    /// The theme New Theme… starts from: a dark color, the date, the clock, and the password field.
    static let blank = "_blank"
    /// A new theme's name, before a number when one is taken.
    static let untitled = "Untitled Theme"
    /// A .lua file.
    static let type = UTType(filenameExtension: "lua", conformingTo: .sourceCode) ?? .plainText

    /// The file's text. The JSON sits in a long string whose brackets it does not contain.
    func source() throws -> String {
        // A theme file's name, and nothing that could end the Lua string it sits in.
        guard base.wholeMatch(of: /[A-Za-z0-9_.-]{1,64}/) != nil else { throw LuaError("not a theme id: \(base)") }
        let object = try LuaValue.table(["name": .string(name), "edits": .array(edits)]).jsonObject()
        let json = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
                          as: UTF8.self)
        var level = ""
        while json.contains("]\(level)]") { level += "=" }
        return """
        -- A Locky theme, made with Customize in Locky. To add it, choose File › Import Theme… in Locky.
        return locky.theme.derive("\(base)", locky.json.decode([\(level)[
        \(json)
        ]\(level)]))

        """
    }

    /// A file `source()` wrote, else nil. Comments before the return are allowed; anything else is not.
    static func parse(_ text: String) -> ThemeFile? {
        guard text.utf8.count <= maxSize,
              let match = text.wholeMatch(of: /(?s)(?:--[^\n]*\n)*return locky\.theme\.derive\("([A-Za-z0-9_.-]{1,64})", locky\.json\.decode\(\[(=*)\[\n(.*)\]\2\]\)\)\s*/),
              let object = try? JSONSerialization.jsonObject(with: Data(match.3.utf8)) as? [String: Any] else { return nil }
        let value = LuaValue(json: object)
        guard let name = value["name"].string, isName(name), let edits = value["edits"].array,
              edits.allSatisfy({ $0.table != nil }) else { return nil }
        return ThemeFile(base: String(match.1), name: name, edits: edits)
    }

    /// A theme's name: 1 to 80 characters, none of them control characters.
    static func isName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 80 && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// `theme` (its id) with `edit` (settings.json's themes.<id>) as a new theme named `name`. A theme the window
    /// made starts from its own base with its own changes first, so the new one never depends on it.
    static func made(from theme: String, edit: LuaValue, name: String, config: URL) -> ThemeFile {
        let made = (try? String(contentsOf: file(theme, config: config), encoding: .utf8)).flatMap(parse)
        let edits = (made?.edits ?? []) + (edit.isNil ? [] : [edit])
        return ThemeFile(base: made?.base ?? theme, name: name, edits: edits)
    }

    /// Whether Locky itself ships `theme`: a file made from it loads on any Mac with Locky.
    static func isBuiltIn(_ theme: String) -> Bool {
        let roots = [RuntimePath.builtInRuntime] + RuntimePath.builtInPackages
        return roots.contains { FileManager.default.fileExists(atPath: $0.appending(path: "themes/\(theme).lua").path) }
    }

    /// The widgets the changes name that do not come with Locky, as `known` (the window's widget list) has them. An
    /// imported theme may not use them: it gives a widget options, and a plugin's widget could run one as a command.
    func foreignWidgets(_ known: [Inspection.WidgetInfo]) -> [String] {
        let resources = RuntimePath.resources.resolvingSymlinksInPath().path + "/"
        let names = Set(edits.flatMap { $0["widgets"].array ?? [] }.compactMap { $0["widget"].string })
        return names.filter { name in
            guard let file = known.first(where: { $0.name == name })?.file else { return true }
            return !file.resolvingSymlinksInPath().path.hasPrefix(resources)
        }.sorted()
    }

    /// The ids a new theme must not take: every theme's, every file's in the config's themes folder, and every
    /// id settings.json has changes for, which a theme removed in Finder leaves behind.
    static func takenIDs(_ themes: [Inspection.ThemeInfo], settings: Settings, config: URL) -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: config.appending(path: "themes").path)) ?? []
        let edited = (settings["themes"].table ?? [:]).keys
        return Set(themes.map(\.id) + files.filter { $0.hasSuffix(".lua") }.map { String($0.dropLast(4)) } + edited)
    }

    /// A new theme for New Theme…: the blank one, under an id `taken` does not have, and the name that goes with it,
    /// "Untitled Theme 2" for "untitled-theme-2".
    static func untitled(taken: Set<String>) -> (id: String, file: ThemeFile) {
        let id = id(for: untitled, taken: taken)
        let number = id.split(separator: "-").last.flatMap { Int($0) }
        return (id, ThemeFile(base: blank, name: number.map { "\(untitled) \($0)" } ?? untitled, edits: []))
    }

    /// The user's file for theme `id`.
    static func file(_ id: String, config: URL) -> URL {
        config.appending(path: "themes/\(id).lua")
    }

    /// An id for a theme named `name`: its letters and digits joined by "-", and a number after it when `taken`
    /// has it already. A theme with a built-in theme's id would hide that one.
    static func id(for name: String, taken: Set<String>) -> String {
        let words = name.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        let stem = words.isEmpty ? "theme" : String(words.joined(separator: "-").prefix(40))
        var id = stem
        var number = 2
        while taken.contains(id) {
            id = "\(stem)-\(number)"
            number += 1
        }
        return id
    }

    /// Writes the theme to the config's themes folder as `id`, once it loads: it is tried first from a folder of its
    /// own, put before the config's, so one that fails never lands among the user's themes, and a base that is the
    /// user's own theme or a package's is still found.
    func install(as id: String, config: URL) async throws {
        let text = try source()
        let trial = FileManager.default.temporaryDirectory.appending(path: "locky-theme-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: trial) }
        try FileManager.default.createDirectory(at: trial.appending(path: "themes"), withIntermediateDirectories: true)
        try text.write(to: Self.file(id, config: trial), atomically: true, encoding: .utf8)
        var path = RuntimePath.standard(config: config)
        path.roots.insert(trial, at: 0)
        if case .failure(let error) = await Inspection.layout(of: id, path: path, wallpaper: nil) { throw error }
        let url = Self.file(id, config: config)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw LuaError("\(LuaError.shortenPaths(url.path)) is there already") }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
