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
