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

    static let approvalLine = "Allow Locky in Login Items."

    /// The row's second line. A grouped Form styles a Text there as the subtitle and nothing else, so a warning takes the
    /// subtitle's font and color itself and the row keeps its height; the orange symbol and the link keep their colors.
    @ViewBuilder private var status: some View {
        if let error {
            WarningLabel(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if case .unavailable(let message) = model.loginItem {
            Text(message)
        } else if model.loginItem == .requiresApproval {
            // PermissionFlow's button, small, in the line: it opens System Settings › General › Login Items.
            HStack(spacing: 8) {
                WarningLabel(Self.approvalLine)
                    .foregroundStyle(.secondary)
                PermissionButton(state: Permissions.state(model.loginItem)) { model.permissions.approveLoginItem() }
                    .buttonStyle(.link)
            }
            .font(.subheadline)
        } else if let subtitle {
            Text(subtitle)
        }
    }
}
