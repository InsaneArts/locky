import CoreLocation
import Foundation
import Observation
import PermissionFlow
import SystemSettingsKit

/// Where the Mac is, for locky.location() and the weather's Current Location: the last fix Location Services gave,
/// else the city of the Mac's time zone, from macOS's own zone table. Reading never prompts and needs no permission.
enum MacLocation {
    struct Place: Codable, Equatable, Sendable {
        var lat: Double
        var lon: Double
        var name: String?

        var lua: LuaValue {
            var table: [String: LuaValue] = ["lat": .double(lat), "lon": .double(lon)]
            if let name { table["name"] = .string(name) }
            return .table(table)
        }
    }

    /// The last fix, kept with the caches rather than in settings.json: it is where the Mac was, not a setting.
    static let cache = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Caches/Locky/location.json")
    /// Every time zone's main city and its coordinates (ISO 3166 zone.tab), part of macOS.
    static let zoneTable = URL(fileURLWithPath: "/usr/share/zoneinfo/zone.tab")

    /// The last fix, else the time zone's city, else nil (a zone such as GMT names no city).
    static func current(cache: URL = cache, zone: TimeZone = .current, table: URL = zoneTable) -> Place? {
        if let data = try? Data(contentsOf: cache), let place = try? JSONDecoder().decode(Place.self, from: data) { return place }
        guard let text = try? String(contentsOf: table, encoding: .utf8) else { return nil }
        return city(of: zone.identifier, in: text)
    }

    /// A zone's city from zone.tab's lines ("GE<tab>+4143+04449<tab>Asia/Tbilisi"): "Asia/Tbilisi" → Tbilisi at
    /// 41.72, 44.82. Coordinates are ±DDMM or ±DDMMSS, then ±DDDMM or ±DDDMMSS.
    static func city(of zone: String, in table: String) -> Place? {
        for line in table.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 3, fields[2] == zone else { continue }
            let text = String(fields[1])
            guard let split = text.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }),
                  let lat = degrees(text[..<split], degreeDigits: 2), let lon = degrees(text[split...], degreeDigits: 3) else { return nil }
            let name = zone.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
            return Place(lat: lat, lon: lon, name: name)
        }
        return nil
    }

    /// "+4143" → 41.7167; "-0734530" (with seconds) → -73.7583.
    private static func degrees(_ text: Substring, degreeDigits: Int) -> Double? {
        guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let digits = Array(text.dropFirst())
        guard digits.count == degreeDigits + 2 || digits.count == degreeDigits + 4, digits.allSatisfy(\.isNumber) else { return nil }
        func number(_ range: Range<Int>) -> Double { Double(String(digits[range])) ?? 0 }
        var value = number(0..<degreeDigits) + number(degreeDigits..<degreeDigits + 2) / 60
        if digits.count == degreeDigits + 4 { value += number(degreeDigits + 2..<degreeDigits + 4) / 3600 }
        return sign == "-" ? -value : value
    }

    static func save(_ place: Place, to cache: URL = cache) {
        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(place).write(to: cache, options: .atomic)
    }

    static func forget(_ cache: URL = cache) {
        try? FileManager.default.removeItem(at: cache)
    }
}

/// Location Services, for the weather's Current Location. macOS asks only when the person picks Current Location in
/// Customize, never during a lock. Once allowed, Locky takes a fix at launch and as each lock starts, and keeps it with
/// its city's name in MacLocation.cache. A refusal forgets the last fix: the weather then follows the time zone.
@MainActor @Observable
final class LocationAccess: NSObject, CLLocationManagerDelegate {
    private(set) var state: PermissionAuthorizationState = .unknown
    /// True for the length of a lock: nothing asks then.
    @ObservationIgnored private let isLocked: () -> Bool
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let geocoder = CLGeocoder()

    init(isLocked: @escaping () -> Bool) {
        self.isLocked = isLocked
        super.init()
        manager.delegate = self
        state = Self.state(manager.authorizationStatus)
    }

    /// Current Location picked: macOS's prompt if the person never answered, else a new fix if allowed.
    func request() {
        guard !isLocked() else { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            refresh()
        }
    }

    /// A new fix, only if allowed: it never prompts. The state read is the one kept, so a lock waits for nothing.
    func refresh() {
        if state == .granted { manager.requestLocation() }
    }

    /// Grant: macOS's prompt if the person never answered, else System Settings › Privacy & Security › Location
    /// Services, the only place to change the answer.
    func grant() {
        guard !isLocked() else { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            SystemSettings.open(.privacy(anchor: .privacyLocationServices))
        }
    }

    nonisolated static func state(_ status: CLAuthorizationStatus) -> PermissionAuthorizationState {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: .granted
        default: .notGranted
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            state = Self.state(status)
            if state == .granted { refresh() }
            if state == .notGranted { MacLocation.forget() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let lat = location.coordinate.latitude, lon = location.coordinate.longitude
        MainActor.assumeIsolated {
            // The city's name for the widget; the place saves without it if the lookup fails.
            geocoder.cancelGeocode()
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                // A newer fix replaced this one.
                if (error as? CLError)?.code == .geocodeCanceled { return }
                let name = placemarks?.first.flatMap { $0.locality ?? $0.administrativeArea }
                MacLocation.save(MacLocation.Place(lat: lat, lon: lon, name: name))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}
