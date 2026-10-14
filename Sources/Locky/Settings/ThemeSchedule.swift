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

    /// Every field, the other mode's too, so switching modes back and forth keeps both.
    var settingsValue: LuaValue {
        var table: [String: LuaValue] = ["mode": .string(mode.rawValue)]
        table["day"] = day.map(LuaValue.string)
        table["night"] = night.map(LuaValue.string)
        table["day_starts"] = .string(Self.clock(dayStarts))
        table["night_starts"] = .string(Self.clock(nightStarts))
        table["light"] = light.map(LuaValue.string)
        table["dark"] = dark.map(LuaValue.string)
        return .table(table)
    }

    /// The theme for a lock at `date`, with the system in dark mode or not. nil leaves the choice to
    /// settings.json's theme and init.lua: for a slot with no theme set.
    func theme(at date: Date, dark isDark: Bool, calendar: Calendar = .current) -> String? {
        switch mode {
        case .appearance:
            return isDark ? dark : light
        case .time:
            return isDay(at: date, calendar: calendar) ? day : night
        }
    }

    /// Makes `theme` the one the slot that shows at `date` names: light or dark by `dark`, else day or night by the time.
    mutating func setTheme(_ theme: String, at date: Date, dark isDark: Bool, calendar: Calendar = .current) {
        switch mode {
        case .appearance:
            if isDark { dark = theme } else { light = theme }
        case .time:
            if isDay(at: date, calendar: calendar) { day = theme } else { night = theme }
        }
    }

    /// Empties every slot that names `theme`: those slots show the usual theme.
    mutating func forget(_ theme: String) {
        let slots: [WritableKeyPath<ThemeSchedule, String?>] = [\.day, \.night, \.light, \.dark]
        for slot in slots where self[keyPath: slot] == theme { self[keyPath: slot] = nil }
    }

    /// "Day: Aurora from 07:00 · Night: Matrix from 19:00", or "Light: Aurora · Dark: Matrix". A slot with no theme
    /// reads "the usual theme". The times read as the Mac's clock reads them, as the Schedule popover's do: "7:00 PM"
    /// with a 12-hour clock.
    func summary(_ inspection: Inspection, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let name = { (id: String?) in id.flatMap { inspection.theme($0)?.name ?? $0 } ?? "the usual theme" }
        let time = { (minutes: Int) in Self.time(minutes, locale: locale, calendar: calendar) }
        switch mode {
        case .time:
            return "Day: \(name(day)) from \(time(dayStarts)) · Night: \(name(night)) from \(time(nightStarts))"
        case .appearance:
            return "Light: \(name(light)) · Dark: \(name(dark))"
        }
    }

    /// Minutes after midnight in `locale`'s short time style, as the popover's time pickers show them: "19:00", or
    /// "7:00 PM". `clock(_:)` is settings.json's form.
    static func time(_ minutes: Int, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: calendar.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: .now) ?? .now)
    }

    private func isDay(at date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // Day runs from day_starts up to night_starts, across midnight when night comes first.
        return dayStarts <= nightStarts ? (dayStarts..<nightStarts).contains(now) : !(nightStarts..<dayStarts).contains(now)
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
