import SwiftUI

struct PluginsPage: View {
    @Bindable var model: AppModel

    var body: some View {
        ContentUnavailableView("Plugins", systemImage: "hammer")
    }
}
