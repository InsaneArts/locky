import Foundation
import Testing
@testable import Locky

/// The core widgets' helpers, run in a real Lua state.
@Suite struct WidgetTests {
    private func runtime(_ sandbox: Sandbox) -> LuaRuntime {
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        _ = runtime.bootForTest()
        return runtime
    }

    @Test func aDateShowsInAnotherTimeZone() throws {
        let runtime = runtime(try Sandbox())
        defer { runtime.stop() }
        // 2026-01-15 12:00 UTC.
        #expect(try runtime.eval("return locky.date.format('HH:mm', 1768478400, 'Asia/Tokyo')") == [.string("21:00")])
        #expect(try runtime.eval("return locky.date.format('HH:mm', 1768478400, 'America/New_York')") == [.string("07:00")])
        #expect(try runtime.eval("return locky.date.format('ZZZZZ', 1768478400, 'Asia/Kolkata')") == [.string("+05:30")])
        #expect(throws: (any Error).self) { try runtime.eval("return locky.date.format('HH:mm', 0, 'Mars/Olympus')") }
    }

    /// Known 2024 phases: new moon 11 January 11:57 UTC, full moon 25 January 17:54 UTC.
    @Test func theMoonMatchesKnownPhases() throws {
        let runtime = runtime(try Sandbox())
        defer { runtime.stop() }
        let new = try runtime.eval("local m = require('locky.sky').moon(1704974220) return m.name, m.illumination")
        #expect(new[0] == .string("New Moon") && (new[1].int ?? 99) <= 1)
        let full = try runtime.eval("local m = require('locky.sky').moon(1706205240) return m.name, m.illumination, m.days_to_full")
        #expect(full[0] == .string("Full Moon") && (full[1].int ?? 0) >= 99 && full[2] == .int(0))
        let quarter = try runtime.eval("return require('locky.sky').moon(1704974220 + 7.4 * 86400).name")
        #expect(quarter == [.string("First Quarter")])
    }

    @Test func wttrRepliesParse() throws {
        let runtime = runtime(try Sandbox())
        defer { runtime.stop() }
        let json = #"{"current_condition":[{"temp_C":"16","temp_F":"61","FeelsLikeC":"15","FeelsLikeF":"59","weatherCode":"113","weatherDesc":[{"value":"Sunny "}],"humidity":"70","windspeedKmph":"4","windspeedMiles":"2","winddir16Point":"SSE","uvIndex":"3"}],"nearest_area":[{"areaName":[{"value":"Tbilisi"}]}],"weather":[{"date":"2026-10-13","maxtempC":"23","mintempC":"15","maxtempF":"73","mintempF":"59","astronomy":[{"sunrise":"07:11 AM","sunset":"06:23 PM","moon_phase":"Waxing Crescent","moon_illumination":"6"}],"hourly":[{"weatherCode":"116","weatherDesc":[{"value":"Partly cloudy"}]}]}]}"#
        let source = "local w = require('locky.weather').parse(...) return w.temp, w.unit, w.condition, w.symbol, w.sunrise, w.sunset, w.place, w.days[1].symbol"
        let values = try runtime.eval("local json = [==[\(json)]==] \(source.replacingOccurrences(of: "(...)", with: "(json, false)"))")
        #expect(values[0] == .int(16) && values[1] == .string("C") && values[2] == .string("Sunny"))
        #expect(values[3] == .string("sun.max.fill") || values[3] == .string("moon.stars.fill"))
        #expect(values[4] == .int(431) && values[5] == .int(1103) && values[6] == .string("Tbilisi"))
        #expect(values[7] == .string("cloud.sun.fill"))
        let imperial = try runtime.eval("local json = [==[\(json)]==] local w = require('locky.weather').parse(json, true) return w.temp, w.unit, w.wind, w.wind_unit")
        #expect(imperial == [.int(61), .string("F"), .int(2), .string("mph")])
        #expect(try runtime.eval("return require('locky.weather').parse('<html>', false)") == [.nil])
    }
}
