import Foundation

/// settings.json's "schedule": a different theme by time of day, or with Light and Dark mode. When it is on,
/// it picks the theme each lock uses, over settings.json's theme and init.lua's.
///
///   "schedule": { "mode": "time", "day": "glass", "night": "default", "day_starts": "07:00", "night_starts": "19:00" }
///   "schedule": { "mode": "appearance", "light": "glass", "dark": "default" }
struct ThemeSchedule: Equatable, Sendable {
    enum Mode: String, Sendable { case time, appearance }

    var mode: Mode
    var day: String?
    var night: String?
    /// Minutes after midnight.
    var dayStarts = 7 * 60
    var nightStarts = 19 * 60
    var light: String?
    var dark: String?

    init(mode: Mode) {
        self.mode = mode
    }

    init?(settings value: LuaValue) {
        guard let mode = value["mode"].string.flatMap(Mode.init(rawValue:)) else { return nil }
        self.mode = mode
        day = value["day"].string
        night = value["night"].string
        dayStarts = Self.minutes(value["day_starts"].string) ?? dayStarts
        nightStarts = Self.minutes(value["night_starts"].string) ?? nightStarts
        light = value["light"].string
        dark = value["dark"].string
    }

    var settingsValue: LuaValue {
        var table: [String: LuaValue] = ["mode": .string(mode.rawValue)]
        switch mode {
        case .time:
            table["day"] = day.map(LuaValue.string)
            table["night"] = night.map(LuaValue.string)
            table["day_starts"] = .string(Self.clock(dayStarts))
            table["night_starts"] = .string(Self.clock(nightStarts))
        case .appearance:
            table["light"] = light.map(LuaValue.string)
            table["dark"] = dark.map(LuaValue.string)
        }
        return .table(table)
    }

    /// The theme for a lock at `date`, with the system in dark mode or not. nil leaves the choice to
    /// settings.json's theme and init.lua: for a slot with no theme set.
    func theme(at date: Date, dark isDark: Bool, calendar: Calendar = .current) -> String? {
        switch mode {
        case .appearance:
            return isDark ? dark : light
        case .time:
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            // Day runs from day_starts up to night_starts, across midnight when night comes first.
            let isDay = dayStarts <= nightStarts ? (dayStarts..<nightStarts).contains(now) : !(nightStarts..<dayStarts).contains(now)
            return isDay ? day : night
        }
    }

    /// "07:30" → 450.
    static func minutes(_ text: String?) -> Int? {
        guard let parts = text?.split(separator: ":"), parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}

extension Settings {
    var schedule: ThemeSchedule? {
        get { ThemeSchedule(settings: self["schedule"]) }
        set { self["schedule"] = newValue?.settingsValue ?? .nil }
    }
}
