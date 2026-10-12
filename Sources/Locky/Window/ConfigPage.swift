import SwiftUI

struct ConfigPage: View {
    @Bindable var model: AppModel

    var body: some View {
        ContentUnavailableView("Config", systemImage: "hammer")
    }
}
