import SwiftUI

struct DashboardPage: View {
    @Bindable var model: AppModel

    var body: some View {
        ContentUnavailableView("Dashboard", systemImage: "hammer")
    }
}
