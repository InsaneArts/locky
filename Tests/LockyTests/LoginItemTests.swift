import Foundation
import ServiceManagement
import Testing
@testable import Locky

/// Never registers or unregisters: that would change the Mac's login items.
@Suite struct LoginItemTests {
    private let app = URL(fileURLWithPath: "/Applications/Locky.app")

    @Test func serviceStatusesMapOneToOne() {
        #expect(LoginItem.status(.enabled, bundle: app) == .enabled)
        #expect(LoginItem.status(.requiresApproval, bundle: app) == .requiresApproval)
        #expect(LoginItem.status(.notRegistered, bundle: app) == .notRegistered)
        #expect(LoginItem.status(.notFound, bundle: app) == .unavailable("macOS cannot find Locky.app's login item"))
    }

    @Test func aBareExecutableCannotOpenAtLogin() {
        let bare = URL(fileURLWithPath: "/Users/me/locky/.build/debug")
        for status: SMAppService.Status in [.enabled, .requiresApproval, .notRegistered, .notFound] {
            #expect(LoginItem.status(status, bundle: bare) == .unavailable("Open at Login works only in Locky.app"))
        }
    }
}
