import SwiftUI

/// The Themes window's home, while no theme is being customized.
struct ThemeGallery: View {
    let model: AppModel

    var body: some View {
        ContentUnavailableView("Themes", systemImage: "paintpalette")
    }
}
