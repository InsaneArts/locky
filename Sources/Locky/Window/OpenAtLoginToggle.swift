import SwiftUI

/// Open at login, with what stands in its way: approval in Login Items, an error, or a build that cannot open at login.
/// The line under the switch takes the subtitle's place, so the row keeps its height.
struct OpenAtLoginToggle: View {
    let model: AppModel
    /// What the switch is for, under it, while nothing stands in its way. nil: no line.
    let subtitle: String?
    @State private var error: String?

    var body: some View {
        Toggle(isOn: Binding(get: { model.loginItem == .enabled || model.loginItem == .requiresApproval }, set: { on in
            do {
                try model.setLoginItem(on)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        })) {
            Text("Open at login")
            status
        }
        .disabled(model.loginItem.isUnavailable)
    }

    @ViewBuilder private var status: some View {
        if let error {
            WarningLabel(error)
        } else if case .unavailable(let message) = model.loginItem {
            Text(message)
        } else if model.loginItem == .requiresApproval {
            HStack(spacing: 4) {
                WarningLabel("Allow Locky in Login Items.")
                Button("Open Login Items") { LoginItem.openSystemSettings() }
                    .buttonStyle(.link)
            }
        } else if let subtitle {
            Text(subtitle)
        }
    }
}
