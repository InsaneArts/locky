import AppKit
import SwiftUI

/// Photos the camera took after too many wrong passwords, newest first. Shown only when there are some.
struct IntruderPhotos: View {
    let revision: Int
    @State private var photos: [(url: URL, date: Date)] = []
    @State private var confirmingDelete = false

    var body: some View {
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(photos.count == 1 ? "Someone typed wrong passwords" : "Someone typed wrong passwords \(photos.count) times",
                          systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Delete All", role: .destructive) { confirmingDelete = true }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(photos, id: \.url) { photo in
                            VStack(alignment: .leading, spacing: 4) {
                                Button { NSWorkspace.shared.open(photo.url) } label: {
                                    AsyncThumbnail(url: photo.url)
                                        .frame(width: 160, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Open in Preview")
                                HStack {
                                    Text(photo.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button { delete(photo.url) } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                        .help("Delete this photo")
                                }
                                .frame(width: 160)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .padding(16)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .confirmationDialog("Delete every photo?", isPresented: $confirmingDelete) {
                Button("Delete All", role: .destructive) {
                    try? IntruderLog().deleteAll()
                    load()
                }
            }
        }
        Color.clear.frame(height: 0)
            .task(id: revision) { load() }
    }

    private func load() {
        photos = IntruderLog().photos()
    }

    private func delete(_ url: URL) {
        try? IntruderLog().delete(url)
        load()
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
