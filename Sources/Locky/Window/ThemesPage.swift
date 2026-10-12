import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Every theme as a card, the selected one live, and its editor: background and widgets. Changes save to
/// settings.json at once and the preview follows.
struct ThemesPage: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            strip
            Divider()
            if let id = model.selectedTheme, let info = model.inspection.theme(id) {
                HStack(spacing: 0) {
                    stage(info)
                    Divider()
                    ThemeEditor(model: model, theme: info)
                        .frame(width: 360)
                }
            } else {
                ContentUnavailableView(model.inspection.loaded ? "No Themes" : "Loading Themes…", systemImage: "paintpalette")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(model.inspection.themes) { info in
                        ThemeCard(info: info, selected: info.id == model.selectedTheme, active: info.id == model.activeTheme)
                            .id(info.id)
                            .onTapGesture { model.selectedTheme = info.id }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.never)
            // The selected card in view: after the page opens on a theme, or the list loads.
            .onChange(of: model.inspection.themes.count, initial: true) { proxy.scrollTo(model.selectedTheme, anchor: .center) }
        }
    }

    private func stage(_ info: Inspection.ThemeInfo) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = info.error {
                ContentUnavailableView("This Theme Does Not Load", systemImage: "exclamationmark.triangle", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ThemePreview(theme: info.id, generation: model.revision, alwaysLive: model.screenshots)
                    .aspectRatio(1.6, contentMode: .fit)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(info.name).font(.title2.weight(.semibold))
                    if info.id == model.activeTheme { Tag("In Use", color: .green) }
                    if !model.store.settings["themes"][info.id].isNil { Tag("Changed", color: .orange) }
                }
                Text(info.description ?? info.id).foregroundStyle(.secondary).lineLimit(2)
                if let author = info.author { Text("By \(author)").font(.caption).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Preview", systemImage: "play.rectangle") { model.preview(info.id) }
                    .help("Show this theme full size in a window")
            }
            ToolbarItem(placement: .primaryAction) {
                if info.id == model.activeTheme {
                    Label("In Use", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                        .help("Locky locks with this theme")
                } else {
                    Button("Use This Theme") { model.store.update { $0["theme"] = .string(info.id) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(info.error != nil)
                        .help("Lock with this theme from now on")
                }
            }
        }
    }
}

/// A theme's thumbnail (its preview image, or its palette) and name.
private struct ThemeCard: View {
    let info: Inspection.ThemeInfo
    let selected: Bool
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
                .frame(width: 168, height: 105)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .font(.system(size: 17))
                            .padding(6)
                    }
                }
            Text(info.name)
                .font(.callout.weight(selected ? .semibold : .regular))
                .lineLimit(1)
        }
        .frame(width: 168)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = ThemeThumbnails.image(for: info) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            let color = { (role: String, fallback: String) in Color(hex: info.palette[role] ?? fallback) ?? .black }
            ZStack {
                LinearGradient(colors: [color("bg", "#000000"), color("surface", "#1c1c1e")], startPoint: .top, endPoint: .bottom)
                Text("12:00")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(color("fg", "#ffffff"))
                Circle().fill(color("accent", "#0a84ff")).frame(width: 8).offset(y: 30)
            }
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

/// A small colored label, such as "In Use".
struct Tag: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}
