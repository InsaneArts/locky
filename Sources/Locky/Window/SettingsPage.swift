import SwiftUI

struct SettingsPage: View {
    @Bindable var model: AppModel

    var body: some View {
        ContentUnavailableView("Settings", systemImage: "hammer")
    }
}
