import AppKit
import Foundation
import Testing
@testable import Locky

/// The Add Widget sheet's cards and the Plugins pane.
@MainActor
@Suite struct PluginsPageTests {
    /// Every card shows the sizes in one order: the Lock Screen ones, then the desktop ones.
    @Test func sizesShowInOneOrder() {
        #expect(FamilyPicker.sorted(["small", "inline", "circular", "large"]) == ["circular", "inline", "small", "large"])
        #expect(FamilyPicker.order == ["circular", "rectangular", "inline", "small", "medium", "large"])
    }
}
