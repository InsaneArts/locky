import Foundation

struct FontSpec: Sendable, Equatable {
    var family: String?
    var design: String?
    var weight: String?
}

/// A theme as Lua's load_theme exports it: plain data. Widget options stay in Lua.
struct Theme: Sendable, Equatable {
    enum Background: Sendable, Equatable {
        case shader(url: URL, colors: [String], speed: Double, resolution: Double, fps: Int, params: [Double], dim: Double)
        /// The user's desktop picture, blurred and dimmed: hyprlock's look, without screen recording.
        case wallpaper(blur: Double, dim: Double, tint: String?, tintAmount: Double)
        case image(url: URL, blur: Double, dim: Double)
        case video(url: URL, dim: Double)
        case color(String)
        case gradient(colors: [String], angle: Double, noise: Double)
    }

    struct Card: Sendable, Equatable {
        /// "glass", "solid", "outline", or "none".
        var style = "glass"
        var radius = 22.0
        var fill: String?
        var border: String?
    }

    struct Auth: Sendable, Equatable {
        /// "pill", "underline", "box", "terminal", "minimal", or "ring".
        var style = "pill"
        var anchor = Anchor.bottom
        var offset = CGPoint(x: 0, y: -60)
        var width = 240.0
        var avatar = true
        var name = true
        var hint = true
        var placeholder: String?
        var font = FontSpec()
        var prompt: String?
        /// "always", or "activity": hidden until a key press or mouse movement (the glance state), and
        /// hidden again after `idle` seconds without either.
        var reveal = "always"
        var idle = 20.0
        /// How much the background darkens while the password field shows (0 to 1).
        var dim = 0.0
        /// The palette role of a focused field's border or underline (the field is focused all the time).
        var focus = "accent"
        /// The field's text size; the hint scales with it.
        var size = 14.0
        /// "center" (default), or "leading" to line the hint up with the field's left edge.
        var hintAlign = "center"
        /// A glow of this radius on the field's text, like the theme's glowing text.
        var glow: Double?
        /// The "ring" style: its line width, an inner fill (a palette role or color), and a glow on its arcs.
        var ringWidth: Double?
        var ringFill: String?
        var ringGlow = false
    }

    struct Placement: Sendable, Equatable {
        var widget: String
        var anchor: Anchor
        var offset: CGPoint
        var size: CGSize?
        var align: String?
        /// nil: no card. Otherwise a card style.
        var card: String?
        var allDisplays: Bool
        var known: Bool
        /// The options the widget's instance gets, as plain data: the theme editor's preview keeps an instance
        /// while they stay the same.
        var options: LuaValue = .nil
    }

    var id: String
    var name: String
    var description: String?
    var directory: URL?
    var palette: [String: String]
    var font: FontSpec
    var background: Background
    /// Drawn above the widgets with transparency, such as scanlines or film grain. A shader overlay keeps
    /// its alpha.
    var overlay: Background?
    var card: Card
    var auth: Auth
    var widgets: [Placement]

    /// What a lock shows when no theme loads at all: black, a clock, and the password field.
    static let fallback = Theme(
        id: "fallback", name: "Fallback", description: nil, directory: nil,
        palette: ["bg": "#000000", "fg": "#ffffff", "muted": "#ffffff99", "accent": "#0a84ff", "surface": "#ffffff1a",
                  "border": "#ffffff26", "success": "#30d158", "warning": "#ff9f0a", "danger": "#ff453a"],
        font: FontSpec(), background: .color("#000000"), overlay: nil, card: Card(), auth: Auth(), widgets: []
    )

    init(id: String, name: String, description: String?, directory: URL?, palette: [String: String], font: FontSpec,
         background: Background, overlay: Background?, card: Card, auth: Auth, widgets: [Placement]) {
        self.id = id
        self.name = name
        self.description = description
        self.directory = directory
        self.palette = palette
        self.font = font
        self.background = background
        self.overlay = overlay
        self.card = card
        self.auth = auth
        self.widgets = widgets
    }

    init(lua value: LuaValue, path: RuntimePath) throws {
        id = value["id"].string ?? "theme"
        name = value["name"].string ?? id
        description = value["description"].string
        directory = value["dir"].string.map { URL(fileURLWithPath: $0) }
        palette = (value["palette"].table ?? [:]).compactMapValues(\.string)
        font = Self.font(value["font"])

        let card = value["card"]
        self.card = Card(style: card["style"].string ?? "glass", radius: card["radius"].number ?? 22,
                         fill: card["fill"].string, border: card["border"].string)

        let auth = value["auth"]
        self.auth = Auth(
            style: auth["style"].string ?? "pill",
            anchor: auth["anchor"].string.flatMap(Anchor.init(rawValue:)) ?? .bottom,
            offset: Self.point(auth["offset"]) ?? CGPoint(x: 0, y: -60),
            width: auth["width"].number ?? 240,
            avatar: auth["avatar"].bool ?? true,
            name: auth["name"].bool ?? true,
            hint: auth["hint"].bool ?? true,
            placeholder: auth["placeholder"].string,
            font: Self.font(auth["font"]),
            prompt: auth["prompt"].string,
            reveal: auth["reveal"].string ?? "always",
            idle: Self.seconds(auth["idle"], 1...3600, 20),
            dim: Self.seconds(auth["dim"], 0...1, 0),
            focus: auth["focus"].string ?? "accent",
            size: auth["font"]["size"].number ?? 14,
            hintAlign: auth["hint_align"].string ?? (auth["style"].string == "terminal" ? "leading" : "center"),
            glow: auth["glow"].bool == true ? 6 : auth["glow"].number,
            ringWidth: auth["ring"]["width"].number,
            ringFill: auth["ring"]["fill"].string,
            ringGlow: auth["ring"]["glow"].bool ?? false
        )

        let defaultCard = self.card.style
        widgets = (value["widgets"].array ?? []).map { entry in
            let card: String? = switch entry["card"] {
            case .bool(true): defaultCard
            case .string(let style): style
            default: nil
            }
            return Placement(
                widget: entry["widget"].string ?? "?",
                anchor: entry["anchor"].string.flatMap(Anchor.init(rawValue:)) ?? .center,
                offset: Self.point(entry["offset"]) ?? .zero,
                size: Self.point(entry["size"]).map { CGSize(width: $0.x, height: $0.y) },
                align: entry["align"].string,
                card: card,
                allDisplays: entry["display"].string == "all",
                known: entry["known"].bool ?? false,
                options: entry["opts"]
            )
        }
        background = try Self.background(value["background"], palette: palette, directory: directory, path: path)
        overlay = value["overlay"].table == nil ? nil : try Self.background(value["overlay"], palette: palette, directory: directory, path: path)
    }

    private static func font(_ value: LuaValue) -> FontSpec {
        FontSpec(family: value["family"].string, design: value["design"].string, weight: value["weight"].string)
    }

    /// A finite { x, y } within ±100,000 points: NaN or infinity would make a frame AppKit crashes on.
    private static func point(_ value: LuaValue) -> CGPoint? {
        guard let x = value[0].number, let y = value[1].number, x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: min(max(x, -100_000), 100_000), y: min(max(y, -100_000), 100_000))
    }

    /// A duration in seconds within `range`, or `fallback` when it is missing, NaN, or infinite: a sleep of
    /// an infinite duration traps.
    private static func seconds(_ value: LuaValue, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard let number = value.number, number.isFinite else { return fallback }
        return min(max(number, range.lowerBound), range.upperBound)
    }

    /// A palette role or a color, as hex.
    private static func resolve(_ color: String, _ palette: [String: String]) -> String {
        palette[color] ?? color
    }

    /// A file next to the theme, in the runtime path, or anywhere ("~/..." or absolute).
    private static func file(_ name: String, directory: URL?, path: RuntimePath, folder: String) -> URL? {
        if name.hasPrefix("/") || name.hasPrefix("~") { return LuaRuntime.expand(name) }
        if let directory {
            for candidate in [directory.appending(path: name), directory.appending(path: "\(folder)/\(name)")]
            where FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return path.find(name) ?? path.find("\(folder)/\(name)")
    }

    private static func background(_ value: LuaValue, palette: [String: String], directory: URL?, path: RuntimePath) throws -> Background {
        let dim = value["dim"].number ?? 0
        if let shader = value["shader"].string {
            let file = shader.hasSuffix(".metal") ? shader : shader + ".metal"
            guard let url = Self.file(file, directory: directory, path: path, folder: "shaders") else {
                throw LuaError("background: no shader \(file) next to the theme or in shaders/ in the runtime path")
            }
            let colors = (value["colors"].array?.compactMap(\.string) ?? ["bg", "accent", "fg"]).map { resolve($0, palette) }
            return .shader(url: url, colors: colors, speed: value["speed"].number ?? 1, resolution: value["resolution"].number ?? 1,
                           fps: value["fps"].int ?? 60, params: value["params"].array?.compactMap(\.number) ?? [], dim: dim)
        }
        if value["wallpaper"].bool == true {
            return .wallpaper(blur: value["blur"].number ?? 30, dim: value["dim"].number ?? 0.25,
                              tint: value["tint"].string.map { resolve($0, palette) }, tintAmount: value["tint_amount"].number ?? 0)
        }
        if let image = value["image"].string {
            guard let url = Self.file(image, directory: directory, path: path, folder: "assets") else {
                throw LuaError("background: no image \(image)")
            }
            return .image(url: url, blur: value["blur"].number ?? 0, dim: dim)
        }
        if let video = value["video"].string {
            guard let url = Self.file(video, directory: directory, path: path, folder: "assets") else {
                throw LuaError("background: no video \(video)")
            }
            return .video(url: url, dim: dim)
        }
        if let colors = value["gradient"].array?.compactMap(\.string), colors.count >= 2 {
            return .gradient(colors: colors.map { resolve($0, palette) }, angle: value["angle"].number ?? 180, noise: value["noise"].number ?? 0)
        }
        return .color(resolve(value["color"].string ?? "bg", palette))
    }
}
