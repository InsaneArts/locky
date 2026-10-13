import Foundation
import ServiceManagement
import Testing
@testable import Locky

/// Never registers or unregisters: that would change the Mac's login items.
@Suite struct LoginItemTests {
    private let app = URL(fileURLWithPath: "/Applications/Locky.app")

    @Test func serviceStatusesMap() {
        #expect(LoginItem.status(.enabled, bundle: app) == .enabled)
        #expect(LoginItem.status(.requiresApproval, bundle: app) == .requiresApproval)
        #expect(LoginItem.status(.notRegistered, bundle: app) == .notRegistered)
        // What macOS 26 reports for an app never registered: register() must stay possible.
        #expect(LoginItem.status(.notFound, bundle: app) == .notRegistered)
    }

    @Test func aBareExecutableCannotOpenAtLogin() {
        let bare = URL(fileURLWithPath: "/Users/me/locky/.build/debug")
        for status: SMAppService.Status in [.enabled, .requiresApproval, .notRegistered, .notFound] {
            #expect(LoginItem.status(status, bundle: bare) == .unavailable("Open at login works only in Locky.app."))
        }
        #expect(LoginItem.Status.unavailable("").isUnavailable && !LoginItem.Status.notRegistered.isUnavailable)
    }
}
