import SwiftUI

/// The lock screen message ("If found, call ..."), in the password field's font and the theme's quiet color. A lock
/// with ⌃⌥⌘Q adds the way out once someone looks stuck (AuthModel.stuck): from the third wrong password, from a wait,
/// or once one password check has run for 5 seconds. It sits under the password field and stays visible while a theme
/// hides the field.
struct LockMessage: View {
    let text: String?
    let model: AuthModel?
    /// The lock offers ⌃⌥⌘Q (settings.json's emergency_exit).
    let exit: Bool
    let auth: Theme.Auth
    let style: LockyStyle

    var body: some View {
        VStack(alignment: auth.hintAlign == "leading" ? .leading : .center, spacing: 4 * style.scale) {
            if let text { Text(text).lineLimit(3) }
            if exit, model?.stuck == true {
                Text("Press ⌃⌥⌘Q to switch to the macOS lock screen")
                    .accessibilityLabel(AuthPanel.wayOut)
            }
        }
        .font(style.font(size: 13 * auth.size / 14, weight: auth.font.weight ?? "medium",
                         design: auth.font.design ?? (auth.style == "terminal" ? "monospaced" : nil),
                         family: auth.font.family, mono: false, italic: false))
        .foregroundStyle(style.quiet(on: nil))
        .multilineTextAlignment(auth.hintAlign == "leading" ? .leading : .center)
    }
}
