import AppKit
import SwiftUI

/// Locky's design tokens: the radii and spacing the windows share. Each says where it is used.
enum Design {
    enum Radius {
        /// Theme tiles, plugin icons, photos.
        static let thumbnail: CGFloat = 8
        /// Widget tiles, the failed-theme banner, wells.
        static let tile: CGFloat = 12
    }

    /// Whether a "#rrggbb" color is light: the rule LockSession uses for the lock window's appearance.
    static func isLight(_ hex: String?) -> Bool {
        guard let color = hex.flatMap(NSColor.init(hex:))?.usingColorSpace(.sRGB) else { return false }
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent > 0.5
    }
}

/// A theme's colors as the windows show them, from its palette: the dots that tell it apart, the accent of its page's
/// main button, and whether its page is light. Scene's theme pages take their colors the same way.
struct ThemeLook: Equatable {
    /// Up to six "#rrggbb" colors of the theme's own: the accent, then the others, the most colorful first.
    let swatches: [String]
    let accent: String
    /// The text on the accent: the theme's background where it reads on it, else black or white.
    let onAccent: String
    let isLight: Bool

    init(palette: [String: String]) {
        // The theme's colors over Locky's defaults, as a lock has them. A color with alpha counts as it looks over bg.
        let colors = Theme.fallback.palette.merging(palette) { $1 }
        let black = Contrast.RGB(r: 0, g: 0, b: 0)
        let bg = colors["bg"].flatMap { Contrast.over($0, black) } ?? black
        func solid(_ hex: String?) -> Contrast.RGB? { hex.flatMap { Contrast.over($0, bg) } }
        func chroma(_ c: Contrast.RGB) -> Double { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }
        func hex(_ c: Contrast.RGB) -> String {
            String(format: "#%02x%02x%02x", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
        }
        let accent = solid(colors["accent"]) ?? Contrast.RGB(r: 1, g: 1, b: 1)
        // The theme's own colors tell it apart; a theme with none shows the defaults.
        let own = (palette.isEmpty ? colors : palette).filter { $0.key != "accent" }.values.compactMap(solid)
        var picked = [accent]
        for color in own.sorted(by: { (chroma($0), hex($0)) > (chroma($1), hex($1)) }) where picked.count < 6 {
            // One dot per color: two roles a shade apart read as one.
            if picked.allSatisfy({ abs($0.r - color.r) + abs($0.g - color.g) + abs($0.b - color.b) > 0.12 }) { picked.append(color) }
        }
        swatches = picked.map(hex)
        self.accent = hex(accent)
        onAccent = Contrast.ratio(accent, bg) >= 3 ? hex(bg) : Contrast.luminance(accent) > 0.3 ? "#000000" : "#ffffff"
        isLight = Design.isLight(hex(bg))
    }
}

/// A row of color dots: a theme's swatches.
struct PaletteDots: View {
    let colors: [String]
    var size: CGFloat = 10

    var body: some View {
        HStack(spacing: size * 0.4) {
            ForEach(colors, id: \.self) { color in
                Circle().fill(Color(hex: color) ?? .clear)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.18), lineWidth: 0.5))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A short status in a tinted capsule.
struct Pill: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// A capsule button with a solid fill. A theme page's main button takes the theme's accent.
struct CapsuleButtonStyle: ButtonStyle {
    let fill: Color
    let label: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(label)
            .padding(.horizontal, 18)
            .frame(minHeight: 32)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .opacity(isEnabled ? 1 : 0.4)
            .brightness(configuration.isPressed ? -0.06 : 0)
    }
}

/// A theme's picture: its thumbnail, else its own background colors.
struct ThemePicture: View {
    let info: Inspection.ThemeInfo?
    /// The theme's id, for the picture Locky ships when `info` is not read yet.
    var id: String?

    var body: some View {
        if let image = info.flatMap(ThemeThumbnails.image) ?? id.flatMap(ThemeThumbnails.bundled) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            let color = { (role: String, fallback: String) in Color(hex: info?.palette[role] ?? fallback) ?? .black }
            LinearGradient(colors: [color("bg", "#000000"), color("surface", "#1c1c1e")], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// A theme's picture, blurred and dimmed, behind its page, so the page takes the theme's colors. It fades when the theme
/// changes.
struct AmbientBackground: View {
    let info: Inspection.ThemeInfo?
    let id: String
    let isLight: Bool

    var body: some View {
        ZStack {
            Color.clear.overlay { ThemePicture(info: info, id: id) }
                .clipped()
                .id(id)
                .transition(.opacity)
        }
        .blur(radius: 40, opaque: true)
        .overlay(isLight ? Color.white.opacity(0.55) : Color.black.opacity(0.5))
        .animation(.easeInOut(duration: 0.45), value: id)
        .ignoresSafeArea()
    }
}

/// Motion. Keyboard actions never animate.
enum Motion {
    /// The strong ease-out, cubic-bezier(0.23, 1, 0.32, 1), for AppKit fades. A new object each time: the type is not Sendable.
    static var easeOut: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) }
    /// The same curve for SwiftUI.
    static func easeOut(duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
    /// Rows that appear or leave because of the person's own change. None with Reduce Motion: the rows change at once.
    static func rows(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .smooth(duration: 0.2) }
}

extension EnvironmentValues {
    /// True while a `PressHighlightStyle` button is held down, for the picture inside it.
    @Entry var buttonPressed = false
}

/// A picture button's press as AppKit shows it: the picture changes while the pointer is down (`pressOverlay`). No scale,
/// no animation.
struct PressHighlightStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.buttonPressed, configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A warning: the orange symbol carries it, the text stays readable.
struct WarningLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Label { Text(text) } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

extension View {
    /// The pressed look of a picture inside a `PressHighlightStyle` button: 15% white over a dark picture, 15% black
    /// over a light one, so it shows on every theme.
    func pressOverlay(light: Bool, in shape: some Shape) -> some View { modifier(PressOverlay(light: light, shape: shape)) }

    /// The edge of a picture: `.primary` at 10%, 35% with Increase Contrast.
    func hairline(cornerRadius: CGFloat, lineWidth: CGFloat = 1) -> some View { modifier(Hairline(cornerRadius: cornerRadius, lineWidth: lineWidth)) }

    /// The frame of a live lock screen preview (the gallery header, the Customize canvas, the Welcome): its hairline on
    /// the stage's 10-pt corners, and a soft shadow.
    func previewFrame() -> some View { hairline(cornerRadius: 10).shadow(color: .black.opacity(0.25), radius: 12, y: 4) }
}

private struct PressOverlay<S: Shape>: ViewModifier {
    let light: Bool
    let shape: S
    @Environment(\.buttonPressed) private var pressed

    func body(content: Content) -> some View {
        content.overlay {
            if pressed { shape.fill(light ? Color.black.opacity(0.15) : Color.white.opacity(0.15)) }
        }
    }
}

private struct Hairline: ViewModifier {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.1), lineWidth: lineWidth)
        }
    }
}
