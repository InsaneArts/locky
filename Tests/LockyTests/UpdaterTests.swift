import Foundation
import Testing
@testable import Locky

@MainActor
@Suite struct UpdaterTests {
    @Test func noCheckStartsDuringALock() {
        var locked = true
        let updater = Updater(isLocked: { locked })
        #expect(updater.refusal() != nil)
        locked = false
        #expect(updater.refusal() == nil)
    }

    /// Sparkle never starts in the tests (the test binary has no feed), so the menu item stays dimmed.
    @Test func withoutAFeedNothingStarts() {
        let updater = Updater(isLocked: { false })
        updater.start()
        #expect(!updater.canCheck)
    }
}
