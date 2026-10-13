import AppKit
import Foundation
import Testing
@testable import Locky

/// The windows' shared API: what the Themes, Settings, and Welcome windows, the menus, and the command line call.
@MainActor
@Suite struct ShellTests {
    /// Light content takes the dark press overlay, as the lock window's appearance does.
    @Test(arguments: [("#F1EFE8", true), ("#02040a", false), (nil, false)] as [(String?, Bool)])
    func aColorIsLightByTheLockWindowsRule(_ hex: String?, _ light: Bool) {
        #expect(Design.isLight(hex) == light)
    }
}
