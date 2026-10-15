import Foundation

/// ~/Library/Caches/Locky, where locky.weather keeps its replies.
enum WeatherCache {
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Caches/Locky")

    /// Deletes wttr.in's replies, which Locky kept before the weather came from Open-Meteo: weather-*.json files, and
    /// nothing else. After the first launch there are none, so each later launch reads one folder listing.
    static func removeOldReplies(in folder: URL = folder) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasPrefix("weather-") && name.hasSuffix(".json") {
            let url = folder.appending(path: name)
            // A file only: a folder or a link with the name stays.
            guard (try? fm.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeRegular else { continue }
            try? fm.removeItem(at: url)
        }
    }
}
