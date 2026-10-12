import AppKit

/// Colors Lua source for the read-only config viewer. One pass over the UTF-16 code units, so it takes linear
/// time; an unterminated string ends at its line break and an unterminated long string or comment at the end of
/// the file, as Lua reads them. Read the file with `String(decoding:as: UTF8.self)`: invalid UTF-8 then shows
/// as U+FFFD instead of failing to load.
enum LuaHighlighter {
    enum Kind: CaseIterable {
        case comment, string, number, keyword, api, function

        /// System colors, so they follow light and dark mode, darkened in light mode by `readable`.
        var color: NSColor {
            switch self {
            case .comment: .secondaryLabelColor
            case .string: LuaHighlighter.readable(.systemGreen)
            case .number: LuaHighlighter.readable(.systemOrange)
            case .keyword: LuaHighlighter.readable(.systemPink)
            case .api: LuaHighlighter.readable(.systemBlue)
            case .function: LuaHighlighter.readable(.systemPurple)
            }
        }
    }

    struct Token: Equatable {
        var kind: Kind
        /// In UTF-16 code units, as NSString counts.
        var range: NSRange
    }

    static func highlight(_ source: String, font: NSFont) -> NSAttributedString {
        let text = NSMutableAttributedString(string: source, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let colors = Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0, $0.color) })
        text.beginEditing()
        for token in tokens(in: source) {
            text.addAttribute(.foregroundColor, value: colors[token.kind]!, range: token.range)
        }
        text.endEditing()
        return text
    }

    /// The colored tokens of `source`, in order. Names, operators, and whitespace are left out.
    static func tokens(in source: String) -> [Token] {
        Array(source.utf16).withUnsafeBufferPointer { units in
            var lexer = Lexer(units: units)
            lexer.run()
            return lexer.tokens
        }
    }

    /// `color` as it is in dark mode, and darker in light mode, where the light green and orange are hard to read
    /// on white (2.2:1). The darker shades keep at least 4.5:1.
    private static func readable(_ color: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            guard appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua else { return color }
            var darker = color
            appearance.performAsCurrentDrawingAppearance {
                darker = color.usingColorSpace(.sRGB)?.blended(withFraction: 0.4, of: .black) ?? color
            }
            return darker
        }
    }

    /// Lua's reserved words, packed as in `pack`. Lua 5.5 as built here (LUA_COMPAT_GLOBAL) does not reserve
    /// `global`.
    private static let keywords = Set(["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if",
                                       "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until",
                                       "while"].map { pack(Array($0.utf16)) })
    private static let function = pack(Array("function".utf16))
    private static let locky = pack(Array("locky".utf16))

    /// A name of up to 8 ASCII characters as one number, one byte each: a cheap key for the reserved words. Longer
    /// names get 0, which no word matches.
    private static func pack(_ name: some Collection<UInt16>) -> UInt64 {
        guard name.count <= 8 else { return 0 }
        return name.reduce(0) { $0 << 8 | UInt64($1) }
    }

    private struct Lexer {
        let units: UnsafeBufferPointer<UInt16>
        var tokens: [Token] = []
        var i = 0
        /// After a single ".": the next name is a field, so it is not the global `locky`.
        var afterDot = false
        /// After `function`: the next name, with its dots, is the function's name.
        var afterFunction = false

        init(units: UnsafeBufferPointer<UInt16>) {
            self.units = units
        }

        mutating func run() {
            while i < units.count {
                let c = units[i]
                if isSpace(c) {
                    i += 1
                } else if c == ascii("-"), at(i + 1) == ascii("-") {
                    comment()
                } else if c == ascii("\"") || c == ascii("'") {
                    shortString(quote: c)
                } else if c == ascii("["), let level = longBracket(at: i) {
                    let start = i
                    skipLong(level: level)
                    add(.string, from: start)
                } else if isDigit(c) || (c == ascii(".") && isDigit(at(i + 1))) {
                    number()
                } else if c == ascii(".") {
                    var end = i + 1
                    while end - i < 3, at(end) == ascii(".") { end += 1 }
                    // ".." and "..." are operators; a single "." picks a field.
                    afterDot = end == i + 1
                    afterFunction = false
                    i = end
                } else if isNameStart(c) {
                    name()
                } else {
                    i += 1
                    afterDot = false
                    afterFunction = false
                }
            }
        }

        /// The code unit at `index`, or 0 past the end.
        func at(_ index: Int) -> UInt16 {
            index < units.count ? units[index] : 0
        }

        mutating func add(_ kind: Kind, from start: Int) {
            if i > start { tokens.append(Token(kind: kind, range: NSRange(location: start, length: i - start))) }
        }

        /// "--" to the end of the line, or a long comment such as --[[ ]] or --[==[ ]==]. A comment is
        /// whitespace to Lua, so it leaves `afterDot` and `afterFunction` alone.
        mutating func comment() {
            let start = i
            i += 2
            if at(i) == ascii("["), let level = longBracket(at: i) {
                skipLong(level: level)
            } else {
                while i < units.count, units[i] != ascii("\n"), units[i] != ascii("\r") { i += 1 }
            }
            add(.comment, from: start)
        }

        /// The level of the long bracket that opens at `start` ("[[" is 0, "[==[" is 2), or nil.
        func longBracket(at start: Int) -> Int? {
            var end = start + 1
            while at(end) == ascii("=") { end += 1 }
            return at(end) == ascii("[") ? end - start - 1 : nil
        }

        /// Moves past a long bracket of `level` and its closing bracket, or to the end of the source. Only the "="
        /// run right after each "]" is checked, so every unit is read at most twice.
        mutating func skipLong(level: Int) {
            i += level + 2
            while i < units.count {
                if units[i] == ascii("]") {
                    var end = i + 1
                    while end - i - 1 < level, at(end) == ascii("=") { end += 1 }
                    if end - i - 1 == level, at(end) == ascii("]") {
                        i = end + 1
                        return
                    }
                }
                i += 1
            }
        }

        /// '...' or "..." with escapes. Lua ends an unfinished string at the line break; "\z" skips the
        /// whitespace after it, line breaks included, and a backslash before a line break keeps the string going.
        mutating func shortString(quote: UInt16) {
            let start = i
            i += 1
            while i < units.count {
                let c = units[i]
                if c == quote {
                    i += 1
                    break
                }
                if c == ascii("\n") || c == ascii("\r") { break }
                i += 1
                guard c == ascii("\\"), i < units.count else { continue }
                let escaped = units[i]
                i += 1
                if escaped == ascii("z") {
                    while i < units.count, isSpace(units[i]) { i += 1 }
                } else if isNewline(escaped), isNewline(at(i)), at(i) != escaped {
                    i += 1
                }
            }
            add(.string, from: start)
            afterDot = false
            afterFunction = false
        }

        /// A numeral as Lua's lexer reads one: digits, ".", and exponents, with "p" exponents after "0x". Like
        /// Lua, it also takes the letters a-f of a malformed decimal such as "12ab".
        mutating func number() {
            let start = i
            var exponent = (ascii("e"), ascii("E"))
            if units[i] == ascii("0"), at(i + 1) == ascii("x") || at(i + 1) == ascii("X") {
                exponent = (ascii("p"), ascii("P"))
                i += 2
            } else {
                i += 1
            }
            while i < units.count {
                let c = units[i]
                if c == exponent.0 || c == exponent.1 {
                    i += 1
                    if at(i) == ascii("+") || at(i) == ascii("-") { i += 1 }
                } else if isHexDigit(c) || c == ascii(".") {
                    i += 1
                } else {
                    break
                }
            }
            add(.number, from: start)
            afterDot = false
            afterFunction = false
        }

        /// A reserved word, the name of the function being defined (`M.f`, `M:f`), a `locky.*` API name, or a
        /// plain name, which keeps the default color.
        mutating func name() {
            let start = i
            i = nameEnd(from: i)
            let key = LuaHighlighter.pack(units[start..<i])
            if LuaHighlighter.keywords.contains(key) {
                add(.keyword, from: start)
                afterFunction = key == LuaHighlighter.function
            } else if afterFunction {
                while at(i) == ascii(".") || at(i) == ascii(":"), isNameStart(at(i + 1)) {
                    let method = units[i] == ascii(":")
                    i = nameEnd(from: i + 1)
                    if method { break }
                }
                add(.function, from: start)
                afterFunction = false
            } else if !afterDot, key == LuaHighlighter.locky, at(i) == ascii("."), isNameStart(at(i + 1)) {
                while at(i) == ascii("."), isNameStart(at(i + 1)) { i = nameEnd(from: i + 1) }
                add(.api, from: start)
            } else {
                afterFunction = false
            }
            afterDot = false
        }

        func nameEnd(from start: Int) -> Int {
            var end = start
            while isNameStart(at(end)) || isDigit(at(end)) { end += 1 }
            return end
        }

        func isSpace(_ c: UInt16) -> Bool { c == ascii(" ") || c == ascii("\t") || isNewline(c) || c == 0x0B || c == 0x0C }
        func isNewline(_ c: UInt16) -> Bool { c == ascii("\n") || c == ascii("\r") }
        func isDigit(_ c: UInt16) -> Bool { c >= ascii("0") && c <= ascii("9") }
        func isHexDigit(_ c: UInt16) -> Bool { isDigit(c) || (c >= ascii("a") && c <= ascii("f")) || (c >= ascii("A") && c <= ascii("F")) }
        func isNameStart(_ c: UInt16) -> Bool { (c >= ascii("a") && c <= ascii("z")) || (c >= ascii("A") && c <= ascii("Z")) || c == ascii("_") }
    }
}

/// An ASCII character as a UTF-16 code unit.
private func ascii(_ scalar: Unicode.Scalar) -> UInt16 {
    UInt16(scalar.value)
}
