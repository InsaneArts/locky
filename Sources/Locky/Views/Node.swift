import Foundation

/// A paint: a palette role ("accent"), a color name, a hex color, a gradient, or Liquid Glass.
enum Paint: Sendable, Equatable {
    case color(String)
    case gradient([String], angle: Double)
    case glass

    init?(lua value: LuaValue, allowGlass: Bool = false) throws {
        switch value {
        case .nil:
            return nil
        case .string("glass") where allowGlass:
            self = .glass
        case .string(let name):
            self = .color(name)
        case .array, .table:
            let colors = (value.array ?? []).compactMap(\.string)
            guard colors.count >= 2 else { throw LuaError("a gradient needs two colors or more, such as { \"#ff00aa\", \"#00ddff\", angle = 90 }") }
            self = .gradient(colors, angle: value["angle"].number ?? 90)
        default:
            throw LuaError("a color must be a palette role, a color name, \"#rrggbb\", or a gradient table")
        }
    }
}

/// A view returned by a widget's render(), built with locky.ui. Parsed once, on the Lua queue.
struct Node: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case vstack([Node]), hstack([Node]), zstack([Node]), grid([Node])
        case text(String), time(String), symbol(String), image(String)
        case progress(Double), ring(Double), gauge(Double), chart([Double])
        case shape(String)
        case dot, spacer, divider
    }

    /// Properties that place or size things: kept within ±100,000 points.
    static let layoutKeys: Set<String> = ["size", "width", "height", "max_width", "padding", "offset", "spacing", "radius",
                                          "border_width", "shadow", "glow", "blur", "stroke_width", "tracking", "line_spacing"]

    static let kinds = ["vstack", "hstack", "zstack", "grid", "text", "time", "symbol", "image", "progress", "ring",
                        "gauge", "chart", "shape", "dot", "spacer", "divider"]

    var kind: Kind
    var id: String?

    // Text
    var size: Double?
    var weight: String?
    var design: String?
    var font: String?
    var mono = false
    var tracking: Double?
    var italic = false
    var textCase: String?
    var lines: Int?
    var textAlign: String?
    var lineSpacing: Double?
    /// Digits roll when the text changes. nil: `ui.time` rolls unless it shows seconds; text does not.
    var numeric: Bool?
    /// "compressed", "condensed", "expanded": the system font's widths.
    var stretch: String?
    /// "multiply", "screen", "overlay", "difference", "plus-lighter", …
    var blend: String?

    // Color
    var color: Paint?
    var opacity: Double?

    // Layout
    var spacing: Double?
    var align: String?
    var columns = 2
    var padding: [Double]?
    var width: Double?
    var height: Double?
    var maxWidth: Double?
    var fill: String?
    var offset: [Double]?
    var rotation: Double?
    var scale: Double?

    // Decoration
    var background: Paint?
    var radius: Double?
    var border: Paint?
    var borderWidth: Double?
    var shadow: Double?
    var shadowColor: String?
    var glow: Double?
    var blur: Double?

    // Shapes, charts, rings, progress
    var stroke: Paint?
    var strokeWidth: Double?
    var minValue: Double?
    var maxValue: Double?
    /// A ring's start, 0 to 1: the arc runs from here to its value.
    var from: Double?
    var dash: [Double]?
    var clip = false
    /// A polygon's corners, as fractions of its frame.
    var points: [CGPoint]?
    /// Degrees of slant, for faces without an italic.
    var skew: Double?
    var slots: Int?
    var style: String?

    // Gauges
    var icon: String?
    var label: String?
    var valueLabel: String?
    var minLabel: String?
    var maxLabel: String?

    // Images and symbols
    var fit: String?
    var tint: Bool = false
    var symbolMode: String?
    var colors: [String]?

    var animate: String?

    /// Views one widget may draw: the main thread draws them, and the password field shares it.
    static let viewLimit = 5_000
    /// Characters one text may hold.
    static let textLimit = 10_000

    private final class Counter {
        var views = 0
    }

    init(lua value: LuaValue) throws {
        try self.init(lua: value, depth: 0, counter: Counter())
    }

    private init(lua value: LuaValue, depth: Int, counter: Counter) throws {
        guard depth < 48 else { throw LuaError("view nested too deeply") }
        counter.views += 1
        guard counter.views <= Node.viewLimit else {
            throw LuaError("too many views: a widget may draw \(Node.viewLimit) at most (trim long lists)")
        }
        guard let fields = value.table else {
            throw LuaError("a view must be a table built with locky.ui, got \(value.typeName)")
        }
        func children(_ key: String) throws -> [Node] {
            guard let list = fields[key]?.array else { throw LuaError("\(key) needs a list of views") }
            return try list.enumerated().map { offset, child in
                do {
                    return try Node(lua: child, depth: depth + 1, counter: counter)
                } catch let error as LuaError {
                    throw LuaError("\(key)[\(offset + 1)]: \(error.message)")
                }
            }
        }
        // Lua divides by zero without an error, so infinity and NaN reach here; a frame made of them
        // crashes AppKit. Sizes are also kept to what a screen can hold.
        func number(_ key: String) throws -> Double? {
            guard let value = fields[key], !value.isNil else { return nil }
            guard let number = value.number else { throw LuaError("'\(key)' must be a number, got \(value.typeName)") }
            guard number.isFinite else { throw LuaError("'\(key)' must be a finite number, got \(number)") }
            return Node.layoutKeys.contains(key) ? min(max(number, -100_000), 100_000) : number
        }
        func string(_ key: String) throws -> String? {
            guard let value = fields[key], !value.isNil else { return nil }
            guard let text = value.string else { throw LuaError("'\(key)' must be a string, got \(value.typeName)") }
            return text
        }
        func numbers(_ key: String) throws -> [Double]? {
            guard let value = fields[key], !value.isNil else { return nil }
            guard let list = value.array, list.allSatisfy({ $0.number?.isFinite == true }) else {
                throw LuaError("'\(key)' must be a list of finite numbers")
            }
            return list.compactMap(\.number).map { Node.layoutKeys.contains(key) ? min(max($0, -100_000), 100_000) : $0 }
        }
        // Counts: clamped before Int(), which traps on huge values.
        func count(_ key: String, _ range: ClosedRange<Double>) throws -> Int? {
            try number(key).map { Int(min(max($0, range.lowerBound), range.upperBound)) }
        }

        // First: a gauge's value is a number, and its labels must not read as a text or symbol view.
        if fields["gauge"] != nil { kind = .gauge(try number("gauge") ?? 0) }
        else if fields["vstack"] != nil { kind = .vstack(try children("vstack")) }
        else if fields["hstack"] != nil { kind = .hstack(try children("hstack")) }
        else if fields["zstack"] != nil { kind = .zstack(try children("zstack")) }
        else if fields["grid"] != nil { kind = .grid(try children("grid")) }
        else if let text = fields["text"] { kind = .text(String((text.string ?? text.number.map { String($0) } ?? "").prefix(Node.textLimit))) }
        else if let format = fields["time"] { kind = .time(format.string ?? "time") }
        else if let name = fields["symbol"] { kind = .symbol(name.string ?? "questionmark") }
        else if let path = fields["image"] { kind = .image(path.string ?? "") }
        else if fields["progress"] != nil { kind = .progress(try number("progress") ?? 0) }
        else if fields["ring"] != nil { kind = .ring(try number("ring") ?? 0) }
        else if fields["chart"] != nil { kind = .chart(try numbers("chart") ?? []) }
        else if let shape = fields["shape"]?.string {
            guard ["rect", "circle", "capsule", "line", "polygon"].contains(shape) else { throw LuaError("unknown shape \"\(shape)\"") }
            kind = .shape(shape)
        }
        else if fields["dot"] != nil { kind = .dot }
        else if fields["spacer"] != nil { kind = .spacer }
        else if fields["divider"] != nil { kind = .divider }
        else {
            throw LuaError("not a view: a table built with locky.ui has one of \(Node.kinds.joined(separator: ", "))")
        }

        id = try string("id")
        size = try number("size")
        weight = try string("weight")
        design = try string("design")
        font = try string("font")
        mono = fields["mono"]?.bool ?? false
        tracking = try number("tracking")
        italic = fields["italic"]?.bool ?? false
        textCase = try string("case")
        lines = try count("lines", 0...10_000)
        textAlign = try string("text_align")
        lineSpacing = try number("line_spacing")
        numeric = fields["numeric"]?.bool
        stretch = try string("stretch")
        blend = try string("blend")
        do {
            color = try Paint(lua: fields["color"] ?? .nil)
            background = try Paint(lua: fields["background"] ?? .nil, allowGlass: true)
            border = try Paint(lua: fields["border"] ?? .nil)
            stroke = try Paint(lua: fields["stroke"] ?? .nil)
        } catch let error as LuaError {
            throw LuaError("\(error.message)")
        }
        opacity = try number("opacity")
        spacing = try number("spacing")
        align = try string("align")
        columns = try count("columns", 1...1_000) ?? 2
        if let value = fields["padding"], !value.isNil {
            if value.number != nil { padding = try number("padding").map { [$0] } }
            else { padding = try numbers("padding") }
            if padding?.isEmpty == true { padding = nil }
        }
        width = try number("width")
        height = try number("height")
        maxWidth = try number("max_width")
        if let value = fields["fill"] {
            fill = value.bool == true ? "both" : value.string
        }
        offset = try numbers("offset")
        rotation = try number("rotation")
        scale = try number("scale")
        radius = try number("radius")
        borderWidth = try number("border_width")
        shadow = try number("shadow")
        shadowColor = try string("shadow_color")
        if let value = fields["glow"] {
            glow = value.bool == true ? 6 : value.number
        }
        blur = try number("blur")
        strokeWidth = try number("stroke_width")
        minValue = try number("min")
        maxValue = try number("max")
        from = try number("from")
        dash = try numbers("dash")
        clip = fields["clip"]?.bool ?? false
        skew = try number("skew")
        if let list = fields["points"]?.array {
            points = try list.map { point in
                guard let x = point[0].number, let y = point[1].number, x.isFinite, y.isFinite else {
                    throw LuaError("'points' must be a list of { x, y } pairs, each 0 to 1 across the view")
                }
                return CGPoint(x: x, y: y)
            }
        }
        slots = try count("slots", 2...10_000)
        style = try string("style")
        if case .gauge = kind {
            icon = try string("icon")
            label = try string("label")
            valueLabel = try string("value_label")
            minLabel = try string("min_label")
            maxLabel = try string("max_label")
        }
        fit = try string("fit")
        tint = fields["tint"]?.bool ?? false
        symbolMode = try string("mode")
        colors = fields["colors"]?.array?.compactMap(\.string)
        animate = fields["animate"].flatMap { $0.bool == true ? "smooth" : $0.string }
    }
}
