import AppKit
import SwiftUI
import Testing
@testable import Locky

@MainActor
@Suite(.serialized) struct AuthFieldFocusTests {
    /// The field a rebuild makes during the wait after wrong passwords (a display plugged in, the power changing)
    /// is disabled when it asks for focus; it must take the keyboard when the wait ends. The window sits far
    /// off the screen.
    @Test func aFieldMadeDuringTheWaitTakesTheKeyboardAfterIt() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let model = AuthModel()
        model.wrong = 3
        model.checking = true
        window.contentView = NSHostingView(rootView: AuthPanel(auth: Theme.Auth(), style: LockyStyle(), touchID: nil, model: model,
                                                               unlock: {}, failed: {}))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(700))  // the field asks for focus at 250 ms, while disabled
        model.checking = false
        try await Task.sleep(for: .milliseconds(500))
        let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        #expect(responder.contains("Text"), "the first responder is \(responder)")
    }
}

@Suite struct PasswordAttemptsTests {
    /// UserDefaults of their own, so no test touches the app's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "locky-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func threeFreeTriesThenWaitsThatDoubleUpTo30SecondsThen5Minutes() {
        #expect((0...12).map(PasswordAttempts.wait(after:)) == [0, 0, 0, 1, 2, 4, 8, 16, 30, 30, 300, 300, 300])
    }

    @Test func theNextTryWaitsFromTheLastWrongPassword() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var attempts = PasswordAttempts()
        for second in 0..<3 { attempts.fail(at: start.addingTimeInterval(Double(second))) }
        #expect(attempts.count == 3)
        #expect(attempts.nextTry == start.addingTimeInterval(3))
        attempts = PasswordAttempts(count: 2, last: start)
        #expect(attempts.nextTry == nil)
    }

    @Test func theCountOutlastsTheLockAndEndsAfter15QuietMinutes() {
        withDefaults { defaults in
            let start = Date(timeIntervalSince1970: 1_000_000)
            var attempts = PasswordAttempts.load(defaults, now: start)
            for _ in 0..<4 { attempts.fail(at: start) }
            attempts.save(defaults)
            #expect(PasswordAttempts.load(defaults, now: start.addingTimeInterval(60)) == PasswordAttempts(count: 4, last: start))
            #expect(PasswordAttempts.load(defaults, now: start.addingTimeInterval(15 * 60)) == PasswordAttempts())
            // A wrong password after the quiet time counts as the first.
            attempts.fail(at: start.addingTimeInterval(15 * 60))
            #expect(attempts.count == 1)
        }
    }

    @Test func aLastFailureInTheFutureCountsAsNow() {
        withDefaults { defaults in
            let now = Date(timeIntervalSince1970: 1_000_000)
            PasswordAttempts(count: 10, last: now.addingTimeInterval(86_400)).save(defaults)
            let loaded = PasswordAttempts.load(defaults, now: now)
            #expect(loaded.nextTry == now.addingTimeInterval(300))
        }
    }

    @MainActor @Test func theWaitCountsDownAndEnds() async {
        let model = AuthModel()
        for _ in 0..<4 { model.failed() }
        #expect(model.waitLeft == 2)
        try? await Task.sleep(for: .milliseconds(1500))
        #expect(model.waitLeft == 1)
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(model.waitLeft == 0)
    }

    @MainActor @Test func aSuccessStartsTheCountAgainAndANewModelKeepsTheWait() async {
        withDefaults { defaults in
            let model = AuthModel(defaults: defaults)
            for _ in 0..<3 { model.failed() }
            #expect(model.wrong == 3)
            #expect(model.waitLeft == 1)
            // The next lock, or a relaunch, waits too; its own count of wrong passwords starts at 0.
            let next = AuthModel(defaults: defaults)
            #expect(next.waitLeft == 1)
            #expect(next.wrong == 0)
            next.failed()
            #expect(next.waitLeft == 2)
            next.succeeded()
            #expect(PasswordAttempts.load(defaults) == PasswordAttempts())
            #expect(AuthModel(defaults: defaults).waitLeft == 0)
        }
    }
}
