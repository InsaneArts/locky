import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Locky

/// locky.weather against Open-Meteo replies saved in Fixtures (Reykjavík, October 2026), run in a real Lua state. The
/// module's fetch reads the fixtures instead of the network, and locky.location() gives made-up coordinates: no test
/// sends a request or a real location anywhere.
@Suite struct WeatherTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")

    static func fixture(_ name: String) throws -> String {
        try String(contentsOf: fixtures.appending(path: name), encoding: .utf8)
    }

    /// Where locky.location() says the Mac is, in the tests that ask.
    static let testville = MacLocation.Place(lat: 10, lon: 20, name: "Testville")

    /// A runtime whose weather module answers from the fixtures and keeps its cache in the sandbox, which the caller keeps. `urls` lists what it
    /// asked for; `offline = true` makes every request fail; `watch(opts)` runs a widget's watch once and returns its data.
    private func runtime(_ sandbox: Sandbox, location: MacLocation.Place? = nil, privacy: Bool = false) throws -> LuaRuntime {
        if privacy { try sandbox.write("init.lua", "locky.setup({ privacy = true })") }
        let environment = LuaRuntime.Environment()
        environment.location = { location }
        let runtime = LuaRuntime(path: sandbox.path(), environment: environment, delegate: Recorder().delegate)
        #expect(runtime.bootForTest().isEmpty)
        let cache = sandbox.root.appending(path: "cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        _ = try runtime.eval("""
            local weather = require('locky.weather')
            weather.cache_dir = '\(cache.path)'
            replies = {
              celsius = [==[\(try Self.fixture("open-meteo-forecast.json"))]==],
              fahrenheit = [==[\(try Self.fixture("open-meteo-forecast-fahrenheit.json"))]==],
              geocoding = [==[\(try Self.fixture("open-meteo-geocoding.json"))]==],
            }
            urls, offline = {}, false
            weather.fetch = function(self, url, done)
              urls[#urls + 1] = url
              if offline then return done(self, nil) end
              if url:find('geocoding', 1, true) then return done(self, replies.geocoding) end
              done(self, url:find('temperature_unit=fahrenheit', 1, true) and replies.fahrenheit or replies.celsius)
            end
            function watch(opts)
              local data
              weather.watch({ every = function(self, _, fn) fn(self) end }, opts, function(_, d) data = d end)
              return data
            end
            """)
        return runtime
    }

    /// Minutes after midnight on this Mac's clock, as the module counts sunrise and sunset.
    private func minutes(_ time: TimeInterval) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: time))
        return parts.hour! * 60 + parts.minute!
    }

    @Test func aForecastFillsTheWholeTable() throws {
        let sandbox = try Sandbox()
        let runtime = try runtime(sandbox)
        defer { runtime.stop() }
        let values = try runtime.eval("""
            local w = require('locky.weather').parse(replies.celsius, 1792076400)
            return w.temp, w.feels, w.unit, w.condition, w.symbol, w.night, w.humidity, w.wind, w.wind_unit, w.wind_dir, w.uv,
              w.high, w.low, w.code, w.sunrise, w.sunset, #w.days, w.days[1].date, w.days[1].condition, w.days[3].symbol,
              #w.hours, w.hours[1].at, w.hours[1].temp, w.moon_phase ~= nil, w.moon_illumination ~= nil
            """)
        #expect(Array(values[0...10]) == [.int(4), .int(0), .string("C"), .string("Cloudy"), .string("cloud.fill"), .bool(false), .int(59),
                                          .int(8), .string("km/h"), .string("NW"), .int(1)])
        #expect(Array(values[11...15]) == [.int(6), .int(2), .int(3), .int(minutes(1792052257)), .int(minutes(1792087663))])
        #expect(Array(values[16...19]) == [.int(3), .string("2026-10-15"), .string("Drizzle"), .string("cloud.rain.fill")])
        #expect(Array(values[20...24]) == [.int(5), .int(1792076400), .int(4), .bool(true), .bool(true)])
        let fahrenheit = try runtime.eval("""
            local w = require('locky.weather').parse(replies.fahrenheit, 1792076400)
            return w.temp, w.feels, w.unit, w.wind, w.wind_unit, w.high, w.low
            """)
        #expect(fahrenheit == [.int(39), .int(32), .string("F"), .int(5), .string("mph"), .int(44), .int(35)])
        #expect(try runtime.eval("return require('locky.weather').parse('<html>')") == [.nil])
    }

    @Test(arguments: [
        (0, false, "Sunny", "sun.max.fill"), (0, true, "Clear", "moon.stars.fill"), (2, true, "Partly Cloudy", "cloud.moon.fill"),
        (3, true, "Cloudy", "cloud.fill"), (45, false, "Fog", "cloud.fog.fill"), (55, false, "Drizzle", "cloud.drizzle.fill"),
        (65, false, "Heavy Rain", "cloud.heavyrain.fill"), (67, false, "Freezing Rain", "cloud.sleet.fill"),
        (75, false, "Heavy Snow", "cloud.snow.fill"), (80, true, "Showers", "cloud.moon.rain.fill"),
        (95, false, "Thunderstorms", "cloud.bolt.rain.fill"), (1234, false, "", "cloud.fill"),
    ])
    func wmoCodesReadAsAppleWeatherDoes(_ code: Int, _ night: Bool, _ words: String, _ symbol: String) throws {
        let sandbox = try Sandbox()
        let runtime = try runtime(sandbox)
        defer { runtime.stop() }
        #expect(try runtime.eval("return require('locky.weather').condition(\(code), \(night))") == [.string(words), .string(symbol)])
    }

    /// Celsius and Fahrenheit as chosen; Automatic follows the Mac's temperature setting, not its region.
    @Test func unitsFollowTheOptionThenTheMac() throws {
        let sandbox = try Sandbox()
        let runtime = try runtime(sandbox)
        defer { runtime.stop() }
        let mac = UnitTemperature(forLocale: .current, usage: .weather) == .fahrenheit
        #expect(try runtime.eval("return locky.date.locale().temperature") == [.string(mac ? "F" : "C")])
        #expect(try runtime.eval("""
            local imperial = require('locky.weather').imperial
            return imperial('fahrenheit'), imperial('celsius'), imperial('imperial'), imperial('metric'), imperial('automatic'), imperial(nil)
            """) == [.bool(true), .bool(false), .bool(true), .bool(false), .bool(mac), .bool(mac)])
        let data = try runtime.eval("local w = watch({ location = '64.1355,-21.8954', units = 'fahrenheit' }) return w.unit, w.temp, urls[1]")
        #expect(data[0] == .string("F") && data[1] == .int(39))
        #expect(data[2].string?.hasSuffix("&temperature_unit=fahrenheit&wind_speed_unit=mph") == true)
        let celsius = try runtime.eval("local w = watch({ location = '64.1355,-21.8954', units = 'celsius' }) return w.unit, urls[2]")
        #expect(celsius[0] == .string("C") && celsius[1].string?.contains("temperature_unit") == false)
    }

    @Test func placeNamesGeocode() throws {
        let sandbox = try Sandbox()
        let runtime = try runtime(sandbox)
        defer { runtime.stop() }
        #expect(try runtime.eval("local p = require('locky.weather').parse_place(replies.geocoding, 'Reykjavik') return p.lat, p.lon, p.name")
                == [.double(64.13548), .double(-21.89541), .string("Reykjavik")])
        // After a comma, the state or country picks among places of one name.
        let paris = #"{"results":[{"name":"Paris","latitude":48.85,"longitude":2.35,"country":"France","admin1":"Île-de-France"},{"name":"Paris","latitude":33.66,"longitude":-95.56,"country":"United States","admin1":"Texas"}]}"#
        #expect(try runtime.eval("""
            local parse = require('locky.weather').parse_place
            local json = [==[\(paris)]==]
            return parse(json, 'Paris').lat, parse(json, 'Paris, Texas').lat, parse(json, 'Paris, Mars').lat, parse('{"generationtime_ms":1}', 'Nowhere')
            """) == [.double(48.85), .double(33.66), .double(48.85), .nil])
        // The name stays one value of the query: "&" and "#" cannot add to it.
        #expect(try runtime.eval("local url = require('locky.weather').geocode_url return url('São Paulo, Brazil', 'pt'), url('a&b=c#d')") == [
            .string("https://geocoding-api.open-meteo.com/v1/search?name=S%C3%A3o%20Paulo&count=10&language=pt&format=json"),
            .string("https://geocoding-api.open-meteo.com/v1/search?name=a%26b%3Dc%23d&count=10&language=en&format=json"),
        ])
        #expect(try runtime.eval("return require('locky.weather').coordinates(' 41.7151 , 44.8271 ')") == [.double(41.7151), .double(44.8271)])
        #expect(try runtime.eval("local c = require('locky.weather').coordinates return c('91,0') == nil, c('Tbilisi') == nil") == [.bool(true), .bool(true)])
    }

    /// "lat,lon" first, then a place's name, then the Mac's location; nothing at all without one.
    @Test func aLocationResolvesInOrder() throws {
        let sandbox = try Sandbox()
        let runtime = try runtime(sandbox, location: Self.testville)
        defer { runtime.stop() }
        let coordinates = try runtime.eval("local w = watch({ location = '64.1355,-21.8954', place_name = 'Reykjavík' }) return w.place, #urls, urls[1]")
        #expect(coordinates[0] == .string("Reykjavík") && coordinates[1] == .int(1))
        #expect(coordinates[2].string?.contains("latitude=64.1355&longitude=-21.8954") == true)

        // The name finds the same coordinates: their forecast, kept from the first widget, serves this one too.
        let named = try runtime.eval("urls = {} local w = watch({ location = 'Reykjavik' }) return w.place, w.temp, #urls, urls[1]")
        #expect(Array(named[0...2]) == [.string("Reykjavik"), .int(4), .int(1)])
        #expect(named[3].string?.hasPrefix("https://geocoding-api.open-meteo.com/v1/search?name=Reykjavik&") == true)
        // The place is kept too: the next lock asks for nothing.
        #expect(try runtime.eval("urls = {} local w = watch({ location = 'Reykjavik' }) return w.place, #urls") == [.string("Reykjavik"), .int(0)])

        let mac = try runtime.eval("urls = {} local w = watch({ location = '' }) return w.place, #urls, urls[1]")
        #expect(mac[0] == .string("Testville") && mac[1] == .int(1))
        #expect(mac[2].string?.contains("latitude=10.0000&longitude=20.0000") == true)
        #expect(try runtime.eval("urls = {} local w = watch({ location = 'Current' }) return w.place, #urls") == [.string("Testville"), .int(0)])

        let other = try Sandbox()
        let nowhere = try self.runtime(other)
        defer { nowhere.stop() }
        #expect(try nowhere.eval("return watch({ location = '' }), #urls") == [.bool(false), .int(0)])
    }

    /// A reply is kept for `every` minutes and shared; an old one shows at once, and stays when the network is down.
    @Test func theCacheKeepsAndSharesReplies() throws {
        let sandbox = try Sandbox()
        let runtime = try runtime(sandbox)
        defer { runtime.stop() }
        let first = try runtime.eval("local w = watch({ location = '64.1355,-21.8954' }) return w.temp, w.fetched, #urls")
        #expect(first[0] == .int(4) && first[2] == .int(1))
        #expect(try runtime.eval("local w = watch({ location = '64.1355,-21.8954' }) return w.fetched, #urls") == [first[1], .int(1)])

        // Two hours old, with every = 30: it shows, then a new reply replaces it.
        let file = "forecast-64.14,-21.90-c.json"
        let stale = "local f = io.open(require('locky.weather').cache_dir .. '/\(file)', 'w') f:write(locky.json.encode({ fetched = os.time() - 7200, json = replies.celsius })) f:close()"
        let refreshed = try runtime.eval("\(stale) local w = watch({ location = '64.1355,-21.8954' }) return os.time() - w.fetched < 60, #urls")
        #expect(refreshed == [.bool(true), .int(2)])

        // Offline: the old reply stays; with none, there is no weather.
        let offline = try runtime.eval("\(stale) offline = true local w = watch({ location = '64.1355,-21.8954' }) return os.time() - w.fetched >= 7200, #urls")
        #expect(offline == [.bool(true), .int(3)])
        #expect(try runtime.eval("offline = true return watch({ location = '1,1' })") == [.bool(false)])
    }

    /// Privacy mode leaves the place's name out of the weather and of locky.location().
    @Test func privacyHidesThePlace() throws {
        let sandbox = try Sandbox()
        let runtime = try runtime(sandbox, location: Self.testville, privacy: true)
        defer { runtime.stop() }
        #expect(try runtime.eval("local w = watch({ location = '64.1355,-21.8954', place_name = 'Reykjavík' }) return w.place, w.temp") == [.nil, .int(4)])
        #expect(try runtime.eval("local w = watch({ location = '' }) return w.place, w.temp") == [.nil, .int(4)])
        #expect(try runtime.eval("local p = locky.location() return p.lat, p.lon, p.name") == [.double(10), .double(20), .nil])
    }
}

/// Where the Mac is without Location Services: its time zone's city, from macOS's zone table.
@Suite struct MacLocationTests {
    /// Lines in zone.tab's form, the second with seconds.
    static let table = """
        # comment
        GE\t+4143+04449\tAsia/Tbilisi
        US\t+404251-0740023\tAmerica/New_York\tEastern (most areas)
        """

    @Test func aZoneNamesItsCity() throws {
        let tbilisi = try #require(MacLocation.city(of: "Asia/Tbilisi", in: Self.table))
        #expect(tbilisi.name == "Tbilisi" && abs(tbilisi.lat - 41.7167) < 0.001 && abs(tbilisi.lon - 44.8167) < 0.001)
        let york = try #require(MacLocation.city(of: "America/New_York", in: Self.table))
        #expect(york.name == "New York" && abs(york.lat - 40.7142) < 0.001 && abs(york.lon + 74.0064) < 0.001)
        #expect(MacLocation.city(of: "GMT", in: Self.table) == nil)
    }

    /// The last fix first, then the time zone's city.
    @Test func theLastFixComesBeforeTheTimeZone() throws {
        let sandbox = try Sandbox()
        let cache = sandbox.root.appending(path: "location.json"), table = sandbox.root.appending(path: "zone.tab")
        try Self.table.write(to: table, atomically: true, encoding: .utf8)
        let zone = try #require(TimeZone(identifier: "Asia/Tbilisi"))
        #expect(MacLocation.current(cache: cache, zone: zone, table: table)?.name == "Tbilisi")
        MacLocation.save(WeatherTests.testville, to: cache)
        #expect(MacLocation.current(cache: cache, zone: zone, table: table) == WeatherTests.testville)
        MacLocation.forget(cache)
        #expect(MacLocation.current(cache: cache, zone: try #require(TimeZone(identifier: "GMT")), table: table) == nil)
        // The real table has every zone this Mac can be in.
        #expect(MacLocation.current(cache: cache, zone: zone)?.name == "Tbilisi")
    }

    @Test func locationServicesStatesReadAsPermissionRows() {
        #expect(LocationAccess.state(.authorizedAlways) == .granted)
        #expect(LocationAccess.state(.denied) == .notGranted && LocationAccess.state(.restricted) == .notGranted)
        #expect(LocationAccess.state(.notDetermined) == .notGranted)
    }
}

/// Customize's Location row: what it says, what it saves, and that it lays out with and without its permission row.
@MainActor @Suite struct LocationOptionTests {
    @Test func theRowNamesThePlace() {
        #expect(LocationOption.title(location: "", placeName: nil) == "Current Location")
        #expect(LocationOption.title(location: "current", placeName: "Old") == "Current Location")
        #expect(LocationOption.title(location: "64.1355,-21.8954", placeName: "Reykjavík") == "Reykjavík")
        #expect(LocationOption.title(location: "64.1355,-21.8954", placeName: nil) == "64.1355, -21.8954")
        #expect(LocationOption.title(location: "Tokyo", placeName: nil) == "Tokyo")
        #expect(LocationOption.value(latitude: 64.135483, longitude: -21.895412) == "64.1355,-21.8954")
    }

    @Test(arguments: ["", "64.1355,-21.8954"])
    func theRowLaysOut(_ location: String) {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: Form {
            LocationOption(location: location, placeName: "Reykjavík", permission: .notGranted, grant: {}, commit: { _, _ in })
        }.formStyle(.grouped).frame(width: 300))
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.height > 0)
    }
}
