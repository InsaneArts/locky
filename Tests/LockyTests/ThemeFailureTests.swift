import AppKit
import Foundation
import Testing
@testable import Locky

@Suite struct ThemeFailureTests {
    @Test func aThemeThatFailsNamesItselfAndItsFirstProblem() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/broken.lua", "return { widgets = { { 'clock', anchor = 'nowhere' } } }")
        try sandbox.write("themes/fine.lua", "return { background = { color = '#101010' } }")
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        let started = await runtime.start(theme: "broken")
        runtime.stop()
        #expect(started.theme.id == "default")
        #expect(started.failed?.theme == "broken")
        #expect(started.failed?.problem.contains("anchor") == true)

        let other = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        let fine = await other.start(theme: "fine")
        other.stop()
        #expect(fine.failed == nil)
    }

    @Test func theRecordIsAJSONDictionary() throws {
        let name = "locky-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        ThemeFailure(theme: "broken", fallback: "default", message: "theme broken: boom", date: 1_000_000).record(in: defaults)
        let data = try #require(defaults.data(forKey: "lastThemeFailure"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["theme"] as? String == "broken")
        #expect(object["fallback"] as? String == "default")
        #expect(object["message"] as? String == "theme broken: boom")
        #expect(object["date"] as? Double == 1_000_000)
    }

    /// Only a real lock records: the theme editor's preview of a broken theme leaves the record alone.
    @MainActor @Test func aPreviewRecordsNothing() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/broken.lua", "error('boom')")
        let before = UserDefaults.standard.data(forKey: ThemeFailure.key)
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var options = LockSession.Options(theme: "broken", container: container)
        options.path = sandbox.path()
        let session = LockSession(mode: .embedded, options: options)
        session.begin()
        defer { session.end("test") }
        let deadline = Date().addingTimeInterval(3)
        while !session.shows(theme: "default"), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(session.shows(theme: "default"))
        #expect(UserDefaults.standard.data(forKey: ThemeFailure.key) == before)
    }
}
