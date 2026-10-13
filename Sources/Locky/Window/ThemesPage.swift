import AppKit
import SwiftUI

/// The Themes window's page: the gallery, or Customize for the theme `model.editingTheme` names. The two swap at once,
/// like every other change of view.
struct ThemesPage: View {
    let model: AppModel

    var body: some View {
        if let id = model.editingTheme, let info = model.inspection.theme(id) {
            ThemeEditorPage(model: model, info: info)
        } else if model.editingTheme != nil {
            // Read before it shows: a theme just duplicated or imported, or the first read of the config.
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Themes")
        } else {
            ThemeGallery(model: model)
                .navigationTitle("Themes")
        }
    }
}

/// Theme thumbnails: a theme's own preview.png or preview.jpg, else the one Locky ships for a built-in theme.
@MainActor
enum ThemeThumbnails {
    private static var cache: [String: NSImage?] = [:]

    static func image(for info: Inspection.ThemeInfo) -> NSImage? {
        if let cached = cache[info.id] { return cached }
        var candidates: [URL] = []
        if let directory = info.directory {
            candidates += ["preview.png", "preview.jpg"].map { directory.appending(path: $0) }
        }
        candidates += ["png", "jpg"].map { RuntimePath.resources.appending(path: "thumbnails/\(info.id).\($0)") }
        let image = candidates.lazy.compactMap { NSImage(contentsOf: $0) }.first
        cache[info.id] = image
        return image
    }
}
