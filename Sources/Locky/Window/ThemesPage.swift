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
            // Read before it shows: a theme just duplicated or imported, or the first read of the config. Customize's
            // Done is already there, so the toolbar keeps its height when the editor comes.
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Themes")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Done") { model.finishEditing() }
                            .buttonStyle(.borderedProminent)
                    }
                }
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

    /// The thumbnail Locky ships for a built-in theme, by its id alone: what a preview shows before the config's first
    /// read gives the theme's info. Only a plain id, so no path leads out of the thumbnails folder.
    static func bundled(_ id: String) -> NSImage? {
        guard !id.isEmpty, !id.contains("/"), !id.hasPrefix(".") else { return nil }
        return ["png", "jpg"].lazy.compactMap { NSImage(contentsOf: RuntimePath.resources.appending(path: "thumbnails/\(id).\($0)")) }.first
    }
}

/// Pictures of the animated backgrounds Customize offers: one frame of each shader, made once per run.
@MainActor
enum ShaderThumbnails {
    private static var cache: [String: CGImage] = [:]

    /// A frame of `choice`'s shader, 30 seconds in, 320 by 200 pixels; nil when it does not draw.
    static func image(for choice: Inspection.ShaderChoice, path: RuntimePath) async -> CGImage? {
        if let cached = cache[choice.id] { return cached }
        let background = choice.background
        guard let name = background["shader"].string, let url = path.find("shaders/\(name).metal") else { return nil }
        let image = await render(url: url, colors: background["colors"].array?.compactMap(\.string) ?? [],
                                 params: background["params"].array?.compactMap(\.number) ?? [],
                                 seconds: 30 * (background["speed"].number ?? 1))
        cache[choice.id] = image
        return image
    }

    @concurrent nonisolated private static func render(url: URL, colors: [String], params: [Double], seconds: Double) async -> CGImage? {
        try? ShaderView.still(url: url, colors: colors, params: params, seconds: seconds, width: 320, height: 200)
    }
}
