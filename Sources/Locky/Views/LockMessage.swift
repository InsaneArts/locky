import SwiftUI

/// The lock screen message ("If found, call ..."), in the password field's font and the theme's muted color.
/// It sits under the password field and stays visible while a theme hides the field.
struct LockMessage: View {
    let text: String
    let auth: Theme.Auth
    let style: LockyStyle

    var body: some View {
        Text(text)
            .font(style.font(size: 13 * auth.size / 14, weight: auth.font.weight ?? "medium",
                             design: auth.font.design ?? (auth.style == "terminal" ? "monospaced" : nil),
                             family: auth.font.family, mono: false, italic: false))
            .foregroundStyle(style.color("muted"))
            .multilineTextAlignment(auth.hintAlign == "leading" ? .leading : .center)
            .lineLimit(3)
    }
}
