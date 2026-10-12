import Darwin
import Foundation
import QuartzCore
import IOKit.ps
import SystemConfiguration

/// What locky.sys and locky.date report. Every function is cheap enough to call from a widget every second.
enum SystemInfo {
    static func battery() -> LuaValue {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return .table(["present": .bool(false), "plugged": .bool(true)])
        }
        let onAC = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSACPowerValue
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let charged = description[kIOPSIsChargedKey] as? Bool ?? false
            let percent = Int((Double(current) / Double(maximum) * 100).rounded())
            var result: [String: LuaValue] = [
                "present": .bool(true),
                "percent": .int(percent),
                "charging": .bool(charging),
                "plugged": .bool(onAC),
                "state": .string(charging ? "charging" : charged || (onAC && percent >= 100) ? "charged" : onAC ? "plugged" : "discharging"),
            ]
            // Minutes; macOS reports -1 while it is still estimating.
            if !onAC, let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
                result["remaining"] = .int(minutes)
            }
            if charging, let minutes = description[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 {
                result["until_full"] = .int(minutes)
            }
            return .table(result)
        }
        return .table(["present": .bool(false), "plugged": .bool(true)])
    }

    /// CPU use across all cores since the previous reading, in percent.
    final class CPUMeter: @unchecked Sendable {
        private var previous: (busy: UInt64, total: UInt64)?
        private var last: (value: LuaValue, at: Double)?

        /// Readings closer than half a second share one sample: two widgets reading back to back would
        /// otherwise measure a millisecond and report noise.
        func read() -> LuaValue {
            let now = CACurrentMediaTime()
            if let last, now - last.at < 0.5 { return last.value }
            let value = sample()
            last = (value, now)
            return value
        }

        private func sample() -> LuaValue {
            var info = host_cpu_load_info()
            var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
            }
            guard result == KERN_SUCCESS else { return .table([:]) }
            let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1), idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
            let busy = user + system + nice, total = busy + idle
            defer { previous = (busy, total) }
            var usage = 0.0
            if let previous, total > previous.total {
                usage = Double(busy - previous.busy) / Double(total - previous.total) * 100
            }
            return .table(["usage": .double((usage * 10).rounded() / 10), "cores": .int(ProcessInfo.processInfo.activeProcessorCount)])
        }
    }

    static func memory() -> LuaValue {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return .table(["total": .int(Int(total))]) }
        let page = UInt64(getpagesize())
        // Activity Monitor's "Memory Used": app memory, wired, and compressed.
        let app = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return .table([
            "total": .int(Int(total)),
            "used": .int(Int(used)),
            "percent": .double((Double(used) / Double(total) * 1000).rounded() / 10),
        ])
    }

    /// Seconds since the Mac started, sleep included, like `uptime`.
    static func uptime() -> LuaValue {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return .int(Int(ProcessInfo.processInfo.systemUptime)) }
        return .int(Int(Date().timeIntervalSince1970) - boot.tv_sec)
    }

    static func hostname() -> LuaValue {
        let computer = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? Host.current().localizedName ?? ""
        let local = SCDynamicStoreCopyLocalHostName(nil) as String? ?? ""
        return .table(["name": .string(computer), "host": .string(local)])
    }

    static func user() -> LuaValue {
        .table(["name": .string(NSUserName()), "full_name": .string(NSFullUserName())])
    }

    static func os() -> LuaValue {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let names = [13: "Ventura", 14: "Sonoma", 15: "Sequoia", 26: "Tahoe"]
        var text = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { text += ".\(version.patchVersion)" }
        return .table([
            "name": .string("macOS"),
            "version": .string(text),
            "codename": .string(names[version.majorVersion] ?? ""),
            "build": .string(sysctlString("kern.osversion") ?? ""),
        ])
    }

    static func machine() -> LuaValue {
        .table([
            "model": .string(sysctlString("hw.model") ?? ""),
            "chip": .string(sysctlString("machdep.cpu.brand_string") ?? ""),
            "cores": .int(ProcessInfo.processInfo.processorCount),
            "memory": .int(Int(ProcessInfo.processInfo.physicalMemory)),
        ])
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    // MARK: Dates

    /// "time": the system's hours and minutes, without AM/PM (24- or 12-hour as `hour24` forces, when set).
    /// "date": weekday, month, and day, in the system's order. "skeleton:EEEEdMMMM": those fields, ordered and
    /// punctuated for the user's language. Anything else is a date pattern used as it is ("HH:mm",
    /// "EEE d MMM", "mm"), with month and weekday names in the user's language.
    static func format(_ date: Date, _ template: String, hour24: Bool? = nil) -> String {
        switch template {
        case "time" where hour24 != nil: return formatter(hour24 == true ? "HH:mm" : "h:mm").string(from: date)
        case "time": return date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
        case "date": return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        default: return formatter(template).string(from: date)
        }
    }

    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]
    private static let formattersLock = NSLock()

    private static func formatter(_ template: String) -> DateFormatter {
        formattersLock.lock()
        defer { formattersLock.unlock() }
        if let cached = formatters[template] { return cached }
        // A widget that builds templates from changing text would otherwise grow this without end.
        if formatters.count >= 64 { formatters.removeAll() }
        let formatter = DateFormatter()
        formatter.locale = .current
        if template.hasPrefix("skeleton:") {
            formatter.setLocalizedDateFormatFromTemplate(String(template.dropFirst("skeleton:".count)))
        } else {
            formatter.dateFormat = template
        }
        formatters[template] = formatter
        return formatter
    }

    static func locale() -> LuaValue {
        let calendar = Calendar.current
        let hour24 = !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
        let symbols = DateFormatter()
        symbols.locale = .current
        func list(_ values: [String]?) -> LuaValue { .array((values ?? []).map(LuaValue.string)) }
        return .table([
            "identifier": .string(Locale.current.identifier),
            "language": .string(Locale.current.language.languageCode?.identifier ?? "en"),
            "hour24": .bool(hour24),
            "first_weekday": .int(calendar.firstWeekday),
            "weekdays": list(symbols.standaloneWeekdaySymbols),
            "weekdays_short": list(symbols.veryShortStandaloneWeekdaySymbols),
            "weekdays_abbreviated": list(symbols.shortStandaloneWeekdaySymbols),
            "months": list(symbols.standaloneMonthSymbols),
            "months_short": list(symbols.shortStandaloneMonthSymbols),
        ])
    }
}
