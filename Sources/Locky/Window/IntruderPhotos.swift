import AppKit
import SwiftUI

/// The intruder photos as a strip, newest first: each opens in Preview, and its menu shows it in Finder or deletes it.
/// The page loads them and deletes them.
struct IntruderPhotos: View {
    let photos: [(url: URL, date: Date)]
    let delete: (URL) -> Void

    private let shape = RoundedRectangle(cornerRadius: Design.Radius.thumbnail, style: .continuous)

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(photos, id: \.url) { photo in
                    let date = photo.date.formatted(date: .abbreviated, time: .shortened)
                    VStack(alignment: .leading, spacing: 4) {
                        Button { open(photo.url) } label: {
                            // The hairline keeps a bright photo's edge on the light card (1.2:1 without it).
                            AsyncThumbnail(url: photo.url)
                                .frame(width: 120, height: 90)
                                .clipShape(shape)
                                .pressOverlay(light: false, in: shape)
                                .hairline(cornerRadius: Design.Radius.thumbnail)
                        }
                        .buttonStyle(PressHighlightStyle())
                        .help("Open in Preview")
                        .accessibilityLabel("Photo, \(date)")
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .contextMenu {
                        Button("Open in Preview") { open(photo.url) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
                        Divider()
                        Button("Delete") { delete(photo.url) }
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    /// Opens the photo in Preview, as the tooltip says, whichever app this Mac opens JPEGs with.
    private func open(_ photo: URL) {
        guard let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") else {
            NSWorkspace.shared.open(photo)
            return
        }
        NSWorkspace.shared.open([photo], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// A photo file as a thumbnail, loaded off the main thread.
fileprivate struct AsyncThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            if let image { Image(nsImage: image).resizable().scaledToFill() }
        }
        .task(id: url) {
            image = await Self.data(at: url).flatMap(NSImage.init(data:))
        }
    }

    @concurrent nonisolated private static func data(at url: URL) async -> Data? {
        try? Data(contentsOf: url)
    }
}
