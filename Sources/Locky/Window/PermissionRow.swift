import PermissionFlow
import SwiftUI

/// PermissionFlow's grant button as PermissionFlowButton draws it: Granted with a green seal, or Grant with an arrow, in
/// the library's words. Locky does not use PermissionFlowButton itself, which keeps a controller and a state of its own:
/// a lock could not close its panel, and its state would not reach the switch that waits for the permission.
struct PermissionButton: View {
    let state: PermissionAuthorizationState
    let action: () -> Void

    var body: some View {
        let look = PermissionFlowButtonState.make(from: state)
        Button(action: action) {
            Label {
                Text(Permissions.title(state))
            } icon: {
                // Green once granted; else the label's own color: the text's in a push button, the link's in a link.
                if look.isGranted {
                    Image(systemName: look.systemImage).foregroundStyle(.green)
                } else {
                    Image(systemName: look.systemImage)
                }
            }
        }
    }
}

/// A permission where Locky uses it: the System Settings page's name, why Locky asks in one line, and the button with
/// its live state.
struct PermissionRow: View {
    let title: String
    let reason: String
    let state: PermissionAuthorizationState
    let grant: () -> Void

    var body: some View {
        LabeledContent {
            PermissionButton(state: state, action: grant)
        } label: {
            Text(title)
            Text(reason)
        }
    }
}

/// Accessibility, over the Touch ID button's switch, which waits for it.
struct AccessibilityRow: View {
    let permissions: Permissions
    /// Whether this Mac has a Touch ID button, which the line then names.
    let hasButton: Bool

    static let reason = "For the Touch ID button and the keyboard on the lock screen."
    static let keyboardReason = "Keeps the keyboard on the lock screen."

    var body: some View {
        PermissionRow(title: Permissions.accessibilityName(), reason: hasButton ? Self.reason : Self.keyboardReason,
                      state: permissions.accessibility) { permissions.grantAccessibility() }
    }
}
