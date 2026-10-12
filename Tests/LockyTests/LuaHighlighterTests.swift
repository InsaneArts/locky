import AppKit
import Foundation
import Testing
@testable import Locky

@Suite struct LuaHighlighterTests {
    /// Each colored token as "kind text".
    private func tokens(_ source: String) -> [String] {
        let text = source as NSString
        return LuaHighlighter.tokens(in: source).map { "\($0.kind) \(text.substring(with: $0.range))" }
    }

    @Test func keywordsAndNames() {
        #expect(tokens("local x = 1") == ["keyword local", "number 1"])
        let words = "and break do else elseif end false for function goto if in local nil not or repeat return then true until while"
        #expect(tokens(words) == words.split(separator: " ").map { "keyword \($0)" })
        // Names that only look like keywords, and `global`, which this Lua does not reserve.
        #expect(tokens("ends iff End _end global endless x1 elseif2") == [])
    }

    @Test func comments() {
        #expect(tokens("x = 1 -- one\ny = 2") == ["number 1", "comment -- one", "number 2"])
        #expect(tokens("--[[ a\nb ]] local") == ["comment --[[ a\nb ]]", "keyword local"])
        #expect(tokens("--[==[ ]] ]=] ]==] end") == ["comment --[==[ ]] ]=] ]==]", "keyword end"])
        // "--[" without a second "[" is a line comment.
        #expect(tokens("--[ not long\nend") == ["comment --[ not long", "keyword end"])
        #expect(tokens("--[=[ x ]] \nend") == ["comment --[=[ x ]] \nend"])
    }

    @Test func strings() {
        #expect(tokens(#"s = 'it\'s' .. "a \"q\" b""#) == [#"string 'it\'s'"#, #"string "a \"q\" b""#])
        // An escaped backslash does not escape the quote after it.
        #expect(tokens(#""\\" end"#) == [#"string "\\""#, "keyword end"])
        #expect(tokens("[[ a ]] ]] end") == ["string [[ a ]]", "keyword end"])
        #expect(tokens("[=[ a ]] [[ b ]=] end") == ["string [=[ a ]] [[ b ]=]", "keyword end"])
        #expect(tokens("[==[ ]=] ]===] ]==] end") == ["string [==[ ]=] ]===] ]==]", "keyword end"])
        // "\z" skips line breaks, and a backslash before a line break continues the string.
        #expect(tokens("\"a\\z\n   b\" end") == ["string \"a\\z\n   b\"", "keyword end"])
        #expect(tokens("'a\\\r\nb' end") == ["string 'a\\\r\nb'", "keyword end"])
        // Brackets that open no long string: an index, and "[=" without its second "[".
        #expect(tokens("t[1] = t[=") == ["number 1"])
    }

    @Test func numbers() {
        let numerals = ["3", "345", "0xff", "0xBEBADA", "3.0", "3.1416", "314.16e-2", "0.31416E1", "34e1", "0x0.1E", "0xA23p-4",
                        "0X1.921FB54442D18P+1", ".5", "1e+10"]
        #expect(tokens(numerals.joined(separator: " ")) == numerals.map { "number \($0)" })
        // A hex "e" is a digit, not an exponent; ".." is concatenation.
        #expect(tokens("0x1e+5") == ["number 0x1e", "number 5"])
        #expect(tokens("a..b .. 5") == ["number 5"])
        #expect(tokens("x1 _2") == [])
    }

    @Test func lockyAPINames() {
        #expect(tokens("locky.setup({ theme = \"station\" })") == ["api locky.setup", "string \"station\""])
        #expect(tokens("locky.pack.add({ 'a/b' })") == ["api locky.pack.add", "string 'a/b'"])
        #expect(tokens("local ui = locky.ui.text") == ["keyword local", "api locky.ui.text"])
        // A field named locky, a bare locky, concatenation, and a method call are not API names.
        #expect(tokens("t.locky.setup") == [])
        #expect(tokens("x = locky") == [])
        #expect(tokens("locky..x") == [])
        #expect(tokens("lockyx.setup locky:setup") == [])
    }

    @Test func functionNames() {
        #expect(tokens("function M.setup(opts) end") == ["keyword function", "function M.setup", "keyword end"])
        #expect(tokens("local function helper() end") == ["keyword local", "keyword function", "function helper", "keyword end"])
        #expect(tokens("function obj.a:method() end") == ["keyword function", "function obj.a:method", "keyword end"])
        #expect(tokens("function --[[ c ]]\n  name() end") == ["keyword function", "comment --[[ c ]]", "function name", "keyword end"])
        // An anonymous function has no name; the next name is a plain one.
        #expect(tokens("f = function(a) return a end") == ["keyword function", "keyword return", "keyword end"])
    }

    @Test func unterminatedStringsAndComments() {
        // A short string ends at its line break; the next line is code.
        #expect(tokens("s = \"abc\nlocal") == ["string \"abc", "keyword local"])
        #expect(tokens("s = 'abc\r\nlocal") == ["string 'abc", "keyword local"])
        // Long ones, and strings ending in a backslash, run to the end.
        #expect(tokens("x = [==[ abc ]=] end") == ["string [==[ abc ]=] end"])
        #expect(tokens("--[[ abc") == ["comment --[[ abc"])
        #expect(tokens("s = 'abc\\") == ["string 'abc\\"])
        #expect(tokens("s = \"\\z") == ["string \"\\z"])
        #expect(tokens("--") == ["comment --"])
        #expect(tokens("[[") == ["string [["])
        #expect(tokens("0x") == ["number 0x"])
        #expect(tokens("") == [])
    }

    @Test func nonASCIIAndInvalidUTF8() {
        // Ranges count UTF-16 code units, as NSAttributedString does.
        #expect(tokens("s = \"héllo 👋\" end") == ["string \"héllo 👋\"", "keyword end"])
        #expect(tokens("名前 = 1 -- 🙂\nend") == ["number 1", "comment -- 🙂", "keyword end"])
        let invalid = String(decoding: Data([0x2D, 0x2D, 0x20, 0xFF, 0xC3, 0x0A, 0x6C, 0x6F, 0x63, 0x61, 0x6C, 0x20, 0x22, 0xE2, 0x82]), as: UTF8.self)
        #expect(tokens(invalid) == ["comment -- \u{FFFD}\u{FFFD}", "keyword local", "string \"\u{FFFD}"])
    }

    @Test func pathologicalInputsStayLinear() {
        // A long bracket of level 2000 whose body is full of brackets that almost close it.
        let level = String(repeating: "=", count: 2000)
        let almost = String(repeating: "]" + String(repeating: "=", count: 1999) + "]", count: 250)
        let inputs = [
            "[\(level)[" + almost + "]\(level)] end",
            String(repeating: "[=", count: 200_000),
            String(repeating: "\"\\", count: 200_000),
            String(repeating: "--[", count: 200_000),
            String(repeating: "function ", count: 100_000),
        ]
        for input in inputs {
            #expect(cpuSeconds { _ = LuaHighlighter.tokens(in: input) } < 2)
        }
        #expect(tokens("[\(level)[" + almost + "]\(level)] end").last == "keyword end")
    }

    @Test func aMegabyteHighlightsQuickly() throws {
        var chunk = ""
        for url in FileManager.default.enumerator(at: RuntimePath.resources, includingPropertiesForKeys: nil)!
            .compactMap({ $0 as? URL }) where url.pathExtension == "lua" {
            chunk += try String(contentsOf: url, encoding: .utf8)
        }
        let source = String(repeating: chunk, count: (1 << 20) / chunk.utf8.count + 1)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        var text = NSAttributedString()
        // Measured on an M4 Max for 1.1 MB: 13 ms optimized (swiftc -O), 94 ms unoptimized. The bound is for slow CI.
        let seconds = cpuSeconds { text = LuaHighlighter.highlight(source, font: font) }
        #expect(seconds < 3)
        #expect(text.length == (source as NSString).length)
    }

    @Test func colorsAndFont() {
        let source = "local s = 'x' -- c"
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let text = LuaHighlighter.highlight(source, font: font)
        let all = NSRange(location: 0, length: text.length)
        var runs: [String] = []
        text.enumerateAttribute(.foregroundColor, in: all) { value, range, _ in
            let color = value as? NSColor
            let name = color == .labelColor ? "plain" : color == .secondaryLabelColor ? "comment" : "colored"
            runs.append("\(name) \((source as NSString).substring(with: range))")
        }
        #expect(runs == ["colored local", "plain  s = ", "colored 'x'", "plain  ", "comment -- c"])
        var fonts: [NSFont] = []
        text.enumerateAttribute(.font, in: all) { value, _, _ in fonts.append(value as! NSFont) }
        #expect(fonts == [font])
    }

    /// Colored text keeps at least 4.5:1 against the text background, in light and in dark mode.
    @MainActor @Test func colorsReadWellInBothModes() throws {
        func luminance(_ color: NSColor) -> Double {
            let rgb = color.usingColorSpace(.sRGB)!
            func linear(_ c: CGFloat) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                let background = luminance(.textBackgroundColor)
                for kind in LuaHighlighter.Kind.allCases where kind != .comment {
                    let text = luminance(kind.color)
                    let ratio = (max(text, background) + 0.05) / (min(text, background) + 0.05)
                    #expect(ratio >= 4.5, "\(kind) in \(name.rawValue): \(ratio)")
                }
            }
        }
    }
}
