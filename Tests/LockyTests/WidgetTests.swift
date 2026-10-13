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

    /// A location stays one part of wttr.in's path: it cannot add to the query or leave the path.
    @Test func weatherLocationsAreEncoded() throws {
        let runtime = runtime(try Sandbox())
        defer { runtime.stop() }
        let urls = try runtime.eval("local url = require('locky.weather').url return url(''), url('New York'), url('41.7,-44.8'), url('Zürich'), url('x?format=1#a/../b%')")
        #expect(urls == [.string("https://wttr.in/?format=j1"), .string("https://wttr.in/New+York?format=j1"),
                         .string("https://wttr.in/41.7,-44.8?format=j1"), .string("https://wttr.in/Z%C3%BCrich?format=j1"),
                         .string("https://wttr.in/x%3Fformat%3D1%23a%2F..%2Fb%25?format=j1")])
    }
}

@Suite struct TimeModuleTests {
    private func eval(_ source: String) throws -> [LuaValue] {
        let runtime = LuaRuntime(path: try Sandbox().path(), delegate: Recorder().delegate)
        _ = runtime.bootForTest()
        defer { runtime.stop() }
        return try runtime.eval("local time = require('locky.time') " + source)
    }

    @Test func theTimeInWords() throws {
        #expect(try eval("return time.fuzzy(4, 9), time.fuzzy(8, 44), time.fuzzy(23, 58), time.fuzzy(11, 59), time.fuzzy(12, 31), time.fuzzy(0, 1)")
                == [.string("ten past four"), .string("quarter to nine"), .string("midnight"), .string("noon"),
                    .string("half past twelve"), .string("midnight")])
    }

    @Test func progressAndDays() throws {
        // Noon on 2 July 2026, local time: half the day, about half the year.
        let values = try eval("""
            local now = os.time({ year = 2026, month = 7, day = 2, hour = 12 })
            local p = time.progress(now, 2)
            return p.day, math.floor(p.year * 100), p.days_left_in_year,
              time.days_between(now, time.parse_date('2026-12-25')), time.days_between(now, time.parse_date('2026-07-01 23:00'))
            """)
        #expect(values[0] == .double(0.5) && values[1] == .int(50) && values[2] == .int(182), "\(values)")
        #expect(values[3] == .int(176) && values[4] == .int(-1))
        #expect(try eval("return time.parse_date('soon')") == [.nil])
    }

    @Test func bitsAndBeats() throws {
        #expect(try eval("local b = time.bits(5, 4) return b[1], b[2], b[3], b[4]") == [.bool(false), .bool(true), .bool(false), .bool(true)])
        // Midnight UTC is 01:00 in Biel: @041.
        #expect(try eval("return time.beat(0)") == [.string("@041")])
    }
}

@Suite struct CoreWidgetSmokeTests {
    /// Every core widget starts and draws with its defaults, and with each of its styles, without an error.
    @Test func everyCoreWidgetDrawsWithoutAnError() async throws {
        let sandbox = try Sandbox()
        let names = try FileManager.default.contentsOfDirectory(atPath: RuntimePath.builtInRuntime.appending(path: "plugin").path)
            .filter { $0.hasSuffix(".lua") }.map { String($0.dropLast(4)) }.sorted()
        // The theme runs after every plugin script, so it sees every widget.
        try sandbox.write("themes/all.lua", """
        local list = {}
        for _, name in ipairs(locky.widget.list()) do
          local def = locky.widget.get(name)
          list[#list + 1] = { name }
          for _, style in ipairs(def.choices and def.choices.style or {}) do
            list[#list + 1] = { name, opts = { style = style } }
          end
        end
        return { widgets = list }
        """)
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        let started = await runtime.start(theme: "all")
        defer { runtime.stop() }
        #expect(started.problems.isEmpty, "\(started.problems)")
        #expect(Set(started.theme.widgets.map(\.widget)).isSuperset(of: names))
        try await Task.sleep(for: .seconds(2))
        #expect(recorder.failures.isEmpty, "\(recorder.failures)")
    }
}
