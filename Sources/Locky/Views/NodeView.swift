import AppKit
import ImageIO
import SwiftUI

/// The theme's look, handed down to every view: palette, default font, and the screen's scale.
struct LockyStyle: Equatable, Sendable {
    var palette: [String: String] = [:]
    var font = FontSpec()
    /// Themes are laid out for 1440×900 points; a bigger screen scales everything up.
    var scale: CGFloat = 1
    /// true or false forces a 24- or 12-hour "time"; nil follows the system.
    var hour24: Bool?
    /// The battery saver: nothing animates, digits included.
    var still = false

    /// A palette role, a color name, or "#rrggbb[aa]".
    func color(_ name: String) -> Color {
        if let hex = palette[name] { return Color(hex: hex) ?? .white }
        if let named = Self.named[name] { return named }
        return Color(hex: name) ?? .white
    }

    func paint(_ paint: Paint) -> AnyShapeStyle {
        switch paint {
        case .color(let name):
            return AnyShapeStyle(color(name))
        case .gradient(let names, let angle):
            let radians = (angle - 90) * .pi / 180
            let start = UnitPoint(x: 0.5 - cos(radians) / 2, y: 0.5 - sin(radians) / 2)
            let end = UnitPoint(x: 0.5 + cos(radians) / 2, y: 0.5 + sin(radians) / 2)
            return AnyShapeStyle(LinearGradient(colors: names.map(color), startPoint: start, endPoint: end))
        case .glass:
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    func s(_ value: Double) -> CGFloat { CGFloat(value) * scale }

    /// A font from the node's settings, falling back to the theme's.
    func font(size: Double?, weight: String?, design: String?, family: String?, mono: Bool, italic: Bool) -> Font {
        let points = s(size ?? 13)
        let asked = weight ?? font.weight
        var result: Font
        if let family = family ?? font.family, NSFont(name: family, size: 12) != nil || NSFontManager.shared.availableMembers(ofFontFamily: family) != nil {
            // A PostScript name such as "HelveticaNeue-CondensedBlack" carries its own weight: a default
            // weight would swap the face, so only an asked-for weight applies.
            result = Font.custom(family, size: points)
            if let asked, let value = Self.weights[asked] { result = result.weight(value) }
        } else {
            let designs: [String: Font.Design] = ["rounded": .rounded, "serif": .serif, "monospaced": .monospaced, "default": .default]
            result = Font.system(size: points, weight: Self.weights[asked ?? "regular"] ?? .regular, design: designs[design ?? font.design ?? "default"] ?? .default)
        }
        if mono { result = result.monospacedDigit() }
        if italic { result = result.italic() }
        return result
    }

    static let weights: [String: Font.Weight] = [
        "ultralight": .ultraLight, "thin": .thin, "light": .light, "regular": .regular, "medium": .medium,
        "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black,
    ]

    static let named: [String: Color] = [
        "white": .white, "black": .black, "clear": .clear, "red": .red, "orange": .orange, "yellow": .yellow,
        "green": .green, "mint": .mint, "teal": .teal, "cyan": .cyan, "blue": .blue, "indigo": .indigo,
        "purple": .purple, "pink": .pink, "brown": .brown, "gray": .gray,
    ]
}

extension EnvironmentValues {
    @Entry var lockyStyle = LockyStyle()
}

struct NodeView: View, Equatable {
    let node: Node
    @Environment(\.lockyStyle) private var style

    /// SwiftUI skips an unchanged subtree, so a clock that redraws every second re-evaluates its hands
    /// and not its sixty ticks.
    nonisolated static func == (lhs: NodeView, rhs: NodeView) -> Bool { lhs.node == rhs.node }

    var body: some View {
        // A stack shares its space out evenly, and a spacer wrapped in modifiers no longer counts as one.
        // So spacers stay bare, and everything else asks for its size first.
        if case .spacer = node.kind {
            Spacer(minLength: 0)
        } else {
            decorated.layoutPriority(1)
        }
    }

    private var font: Font {
        let font = style.font(size: node.size, weight: node.weight, design: node.design, family: node.font, mono: node.mono, italic: node.italic)
        switch node.stretch {
        case "compressed": return font.width(.compressed)
        case "condensed": return font.width(.condensed)
        case "expanded": return font.width(.expanded)
        default: return font
        }
    }

    private var blendMode: BlendMode {
        switch node.blend {
        case "multiply": .multiply
        case "screen": .screen
        case "overlay": .overlay
        case "difference": .difference
        case "exclusion": .exclusion
        case "color-dodge": .colorDodge
        case "color-burn": .colorBurn
        case "soft-light": .softLight
        case "hard-light": .hardLight
        case "plus-lighter": .plusLighter
        case "plus-darker": .plusDarker
        case "lighten": .lighten
        case "darken": .darken
        default: .normal
        }
    }

    private var foreground: AnyShapeStyle {
        node.color.map(style.paint) ?? AnyShapeStyle(.foreground)
    }

    private var decorated: some View {
        let shape = RoundedRectangle(cornerRadius: style.s(node.radius ?? 0), style: .continuous)
        return content
            // Only a view that names a color sets one: the others keep their parent's, down from the theme's fg.
            .modifier(When(node.color != nil) { $0.foregroundStyle(foreground) })
            .opacity(node.opacity ?? 1)
            .frame(width: node.width.map(style.s), height: node.height.map(style.s), alignment: frameAlignment(default: .center))
            .frame(maxWidth: node.maxWidth.map(style.s), alignment: frameAlignment(default: .leading))
            .padding(insets)
            .frame(maxWidth: ["both", "width"].contains(node.fill ?? "") ? .infinity : nil,
                   maxHeight: ["both", "height"].contains(node.fill ?? "") ? .infinity : nil,
                   alignment: alignment)
            .background { backgroundView(shape) }
            .overlay {
                if let border = node.border {
                    shape.strokeBorder(style.paint(border), lineWidth: style.s(node.borderWidth ?? 1))
                }
            }
            .modifier(Effects(node: node, style: style, shape: shape, shadowColor: shadowColor, blendMode: blendMode))
            .animation(animation, value: node)
    }

    @ViewBuilder private func backgroundView(_ shape: RoundedRectangle) -> some View {
        switch node.background {
        case .none:
            EmptyView()
        case .glass:
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.clear, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        case .some(let paint):
            shape.fill(style.paint(paint))
        }
    }

    private var shadowColor: Color {
        if node.glow != nil {
            if case .color(let name) = node.color { return style.color(name).opacity(0.9) }
            return style.color("accent").opacity(0.9)
        }
        guard node.shadow != nil else { return .clear }
        return node.shadowColor.map(style.color) ?? .black.opacity(0.25)
    }

    private var animation: Animation? {
        guard !style.still else { return nil }
        return switch node.animate {
        case "smooth": .smooth
        case "spring": .spring(duration: 0.5, bounce: 0.3)
        case "linear": .linear(duration: 0.3)
        default: nil
        }
    }

    @ViewBuilder private var content: some View {
        switch node.kind {
        case .vstack(let children):
            VStack(alignment: alignment.horizontal, spacing: node.spacing.map(style.s)) { each(children) }
        case .hstack(let children):
            HStack(alignment: alignment.vertical, spacing: node.spacing.map(style.s)) { each(children) }
        case .zstack(let children):
            ZStack(alignment: alignment) { each(children) }
        case .grid(let children):
            let rows = stride(from: 0, to: children.count, by: node.columns).map { Array(children[$0..<min($0 + node.columns, children.count)]) }
            Grid(alignment: alignment, horizontalSpacing: node.spacing.map(style.s), verticalSpacing: node.spacing.map(style.s)) {
                ForEach(rows.indices, id: \.self) { row in
                    GridRow { each(rows[row]) }
                }
            }
        case .text(let text):
            // Rolling digits draw every frame while they move, on the CPU: worth it for a value that changes
            // now and then, too costly for one that changes every second or two.
            let roll = (node.numeric ?? false) && !style.still
            styledText(Text(text))
                .contentTransition(roll ? .numericText() : .identity)
                .animation(roll ? .smooth(duration: 0.4) : nil, value: text)
        case .time(let format):
            let roll = (node.numeric ?? !Self.showsSeconds(format)) && !style.still
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let text = SystemInfo.format(context.date, format, hour24: style.hour24)
                styledText(Text(text))
                    .contentTransition(roll ? .numericText() : .identity)
                    .animation(roll ? .smooth(duration: 0.6) : nil, value: text)
            }
        case .symbol(let name):
            symbol(name)
        case .image(let path):
            ImageNode(path: path, fit: node.fit, tint: node.tint, radius: style.s(node.radius ?? 0))
        case .progress(let value):
            Capsule()
                .fill(node.background.map(style.paint) ?? AnyShapeStyle(Color.white.opacity(0.18)))
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule().fill(foreground).frame(width: geometry.size.width * clamp(value))
                    }
                }
                .frame(height: style.s(node.size ?? 6))
        case .ring(let value):
            let width = style.s(node.strokeWidth ?? 4)
            let start = clamp(node.from ?? 0)
            ZStack {
                Circle().stroke(node.stroke.map(style.paint) ?? AnyShapeStyle(Color.white.opacity(0.18)),
                                style: StrokeStyle(lineWidth: width, dash: (node.dash ?? []).map(style.s)))
                Circle().trim(from: min(start, clamp(value)), to: clamp(value))
                    .stroke(foreground, style: StrokeStyle(lineWidth: width, lineCap: node.style == "butt" ? .butt : .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: style.s(node.size ?? 40), height: style.s(node.size ?? 40))
        case .chart(let values):
            Chart(values: values, minimum: node.minValue ?? 0, maximum: node.maxValue ?? max(values.max() ?? 1, 1),
                  slots: node.slots ?? max(values.count, 2), style: node.style ?? "line", paint: foreground,
                  lineWidth: style.s(node.strokeWidth ?? 2))
        case .shape(let kind):
            shapeView(kind)
        case .dot:
            Circle().fill(foreground).frame(width: style.s(node.size ?? 8), height: style.s(node.size ?? 8))
        case .spacer:
            EmptyView()  // drawn bare in body
        case .divider:
            Rectangle().fill(node.color.map(style.paint) ?? AnyShapeStyle(Color.white.opacity(0.12))).frame(height: style.s(node.strokeWidth ?? 1))
        }
    }

    /// A date template with a seconds field ("ss", "s") outside quoted literals.
    static func showsSeconds(_ format: String) -> Bool {
        var quoted = false
        for character in format {
            if character == "'" { quoted.toggle() } else if !quoted, character == "s" { return true }
        }
        return false
    }

    private func styledText(_ text: Text) -> some View {
        text
            .font(font)
            .kerning(style.s(node.tracking ?? 0))
            .lineLimit(node.lines)
            .lineSpacing(style.s(node.lineSpacing ?? 0))
            .multilineTextAlignment(textAlignment)
            .textCase(node.textCase == "upper" ? .uppercase : node.textCase == "lower" ? .lowercase : nil)
    }

    @ViewBuilder private func symbol(_ name: String) -> some View {
        let image = Image(systemName: name).font(font)
        switch node.symbolMode {
        case "multicolor":
            image.symbolRenderingMode(.multicolor)
        case "hierarchical":
            image.symbolRenderingMode(.hierarchical)
        case "palette":
            let colors = (node.colors ?? []).map(style.color)
            image.symbolRenderingMode(.palette)
                .foregroundStyle(colors.first ?? .white, colors.dropFirst().first ?? .white.opacity(0.5), colors.dropFirst(2).first ?? .white.opacity(0.3))
        default:
            image
        }
    }

    @ViewBuilder private func shapeView(_ kind: String) -> some View {
        let fill = node.color.map(style.paint)
        let stroke = node.stroke.map(style.paint)
        let lineWidth = style.s(node.strokeWidth ?? 1)
        switch kind {
        case "circle":
            ZStack {
                if let fill { Circle().fill(fill) }
                if let stroke { Circle().strokeBorder(stroke, style: StrokeStyle(lineWidth: lineWidth, dash: (node.dash ?? []).map(style.s))) }
            }
        case "capsule":
            ZStack {
                if let fill { Capsule().fill(fill) }
                if let stroke { Capsule().strokeBorder(stroke, lineWidth: lineWidth) }
            }
        case "line":
            Capsule().fill(fill ?? stroke ?? AnyShapeStyle(.foreground)).frame(height: lineWidth)
        case "polygon":
            let polygon = Polygon(points: node.points ?? [])
            ZStack {
                if let fill { polygon.fill(fill) }
                if let stroke { polygon.stroke(stroke, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round, dash: (node.dash ?? []).map(style.s))) }
            }
        default:
            let shape = RoundedRectangle(cornerRadius: style.s(node.radius ?? 0), style: .continuous)
            ZStack {
                if let fill { shape.fill(fill) }
                if let stroke { shape.strokeBorder(stroke, style: StrokeStyle(lineWidth: lineWidth, dash: (node.dash ?? []).map(style.s))) }
            }
        }
    }

    private func each(_ children: [Node]) -> some View {
        ForEach(Array(children.enumerated()), id: \.offset) { _, child in
            // No .equatable() here: it hides a spacer's (and any flexible view's) flexibility from the stack.
            // NodeView is Equatable, which SwiftUI uses when it compares views.
            NodeView(node: child).id(child.id)
        }
    }

    private func clamp(_ value: Double) -> CGFloat { CGFloat(max(0, min(1, value))) }

    private var alignment: Alignment {
        switch node.align {
        case "leading", "left": .leading
        case "trailing", "right": .trailing
        case "top": .top
        case "bottom": .bottom
        case "top-leading", "top-left": .topLeading
        case "top-trailing", "top-right": .topTrailing
        case "bottom-leading", "bottom-left": .bottomLeading
        case "bottom-trailing", "bottom-right": .bottomTrailing
        default: .center
        }
    }

    /// Where content sits in a fixed or limited frame: by `text_align`, else `fallback`.
    private func frameAlignment(default fallback: Alignment) -> Alignment {
        switch node.textAlign {
        case "leading", "left": .leading
        case "trailing", "right": .trailing
        case "center": .center
        default: fallback
        }
    }

    private var textAlignment: TextAlignment {
        switch node.textAlign ?? node.align {
        case "leading", "left": .leading
        case "trailing", "right": .trailing
        default: .center
        }
    }

    /// One value: all sides. Two: vertical, horizontal. Four: top, leading, bottom, trailing.
    private var insets: EdgeInsets {
        let given = (node.padding ?? []).map(style.s)
        let p = given.isEmpty ? [0] : given
        switch p.count {
        case 2: return EdgeInsets(top: p[0], leading: p[1], bottom: p[0], trailing: p[1])
        case 4: return EdgeInsets(top: p[0], leading: p[1], bottom: p[2], trailing: p[3])
        default: return EdgeInsets(top: p[0], leading: p[0], bottom: p[0], trailing: p[0])
        }
    }
}

/// Applies only the effects a view asks for. A clip, shadow, blur, or blend mode on every view would each
/// cost an offscreen pass, even at zero.
private struct Effects: ViewModifier {
    let node: Node
    let style: LockyStyle
    let shape: RoundedRectangle
    let shadowColor: Color
    let blendMode: BlendMode

    func body(content: Content) -> some View {
        content
            .modifier(When(node.clip) { $0.clipShape(shape) })
            .modifier(When((node.shadow ?? 0) > 0 || node.glow != nil) {
                $0.shadow(color: shadowColor, radius: style.s(node.shadow ?? node.glow ?? 0), y: node.glow == nil ? style.s(1) : 0)
            })
            .modifier(When((node.blur ?? 0) > 0) { $0.blur(radius: style.s(node.blur ?? 0)) })
            .modifier(When(node.offset != nil) {
                $0.offset(x: style.s(node.offset?.first ?? 0), y: style.s(node.offset?.dropFirst().first ?? 0))
            })
            .modifier(When((node.rotation ?? 0) != 0) { $0.rotationEffect(.degrees(node.rotation ?? 0)) })
            // A slant for faces without an italic: the top stays, the bottom moves left.
            .modifier(When((node.skew ?? 0) != 0) {
                $0.transformEffect(CGAffineTransform(a: 1, b: 0, c: -tan((node.skew ?? 0) * .pi / 180), d: 1, tx: 0, ty: 0))
            })
            .modifier(When((node.scale ?? 1) != 1) { $0.scaleEffect(node.scale ?? 1) })
            .modifier(When(blendMode != .normal) { $0.blendMode(blendMode) })
    }
}

/// `transform` when `condition` holds; the view as it is otherwise.
private struct When<Output: View>: ViewModifier {
    let condition: Bool
    let transform: (AnyView) -> Output

    init(_ condition: Bool, _ transform: @escaping (AnyView) -> Output) {
        self.condition = condition
        self.transform = transform
    }

    func body(content: Content) -> some View {
        if condition { transform(AnyView(content)) } else { content }
    }
}

/// A closed shape through points given as fractions of the view's frame: (0, 0) top left, (1, 1) bottom right.
private struct Polygon: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        Path { path in
            guard let first = points.first else { return }
            let map = { (p: CGPoint) in CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
            path.move(to: map(first))
            for point in points.dropFirst() { path.addLine(to: map(point)) }
            path.closeSubpath()
        }
    }
}

/// A line, area, or bar chart of the last `slots` values, newest on the right.
private struct Chart: View {
    let values: [Double]
    let minimum: Double
    let maximum: Double
    let slots: Int
    let style: String
    let paint: AnyShapeStyle
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let points = Array(values.suffix(slots))
            let width = geometry.size.width, height = geometry.size.height
            let range = max(maximum - minimum, .ulpOfOne)
            let y = { (value: Double) in height - CGFloat(min(max((value - minimum) / range, 0), 1)) * (height - lineWidth * 2) - lineWidth }
            if style == "bar" {
                let slot = width / CGFloat(max(slots, 1))
                Path { path in
                    for (index, value) in points.enumerated() {
                        let x = width - CGFloat(points.count - index) * slot
                        path.addRoundedRect(in: CGRect(x: x + slot * 0.15, y: y(value), width: slot * 0.7, height: height - y(value)),
                                            cornerSize: CGSize(width: slot * 0.2, height: slot * 0.2))
                    }
                }
                .fill(paint)
            } else {
                let step = width / CGFloat(max(slots - 1, 1))
                let line = Path { path in
                    for (index, value) in points.enumerated() {
                        let point = CGPoint(x: width - CGFloat(points.count - 1 - index) * step, y: y(value))
                        index == 0 ? path.move(to: point) : path.addLine(to: point)
                    }
                }
                if style == "area" || style == "line" {
                    let area = Path { path in
                        path.addPath(line)
                        path.addLine(to: CGPoint(x: width, y: height))
                        path.addLine(to: CGPoint(x: width - CGFloat(max(points.count - 1, 0)) * step, y: height))
                        path.closeSubpath()
                    }
                    area.fill(paint).mask(LinearGradient(colors: [.white.opacity(style == "area" ? 0.7 : 0.45), .clear], startPoint: .top, endPoint: .bottom))
                }
                line.stroke(paint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// An image file. Decoded off the main thread, as a thumbnail of at most 4096 pixels: a huge file must not
/// stall the main thread, which the password field shares.
private struct ImageNode: View {
    let path: String
    let fit: String?
    let tint: Bool
    let radius: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .renderingMode(tint ? .template : .original)
                    .resizable()
                    .aspectRatio(contentMode: fit == "fit" ? .fit : .fill)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                Color.clear
            }
        }
        // The file's modification date is part of the key, so a picture rewritten at the same path shows anew.
        .task(id: ImageCache.key(path)) { image = await ImageCache.shared.image(path) }
    }
}

/// Decoded images by path and modification date, the 64 most recent.
actor ImageCache {
    static let shared = ImageCache()
    private var images: [String: NSImage] = [:]
    private var order: [String] = []

    nonisolated static func key(_ path: String) -> String {
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(path)@\(modified)"
    }

    func image(_ path: String) async -> NSImage? {
        let key = Self.key(path)
        if let cached = images[key] { return cached }
        let decoded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 4096,
                  ] as CFDictionary) else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }.value
        guard let decoded else { return nil }
        images[key] = decoded
        order.append(key)
        if order.count > 64 { images[order.removeFirst()] = nil }
        return decoded
    }
}

extension Color {
    /// "#rgb", "#rrggbb", or "#rrggbbaa".
    init?(hex: String) {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let rgba = digits.count == 6 ? value << 8 | 0xFF : value
        self.init(.sRGB, red: Double(rgba >> 24 & 0xFF) / 255, green: Double(rgba >> 16 & 0xFF) / 255,
                  blue: Double(rgba >> 8 & 0xFF) / 255, opacity: Double(rgba & 0xFF) / 255)
    }
}
