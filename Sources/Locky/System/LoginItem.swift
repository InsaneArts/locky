import Foundation
import ServiceManagement

/// Open at Login: Locky.app as a login item (SMAppService.mainApp). It is listed in System Settings › General ›
/// Login Items, where the user can switch it off too.
enum LoginItem {
    enum Status: Equatable, Sendable {
        case enabled
        /// Registered, but switched off in System Settings, the only place it can be switched back on.
        case requiresApproval
        case notRegistered
        /// Locky cannot open at login as it runs now; the message says why.
        case unavailable(String)
    }

    struct Unavailable: LocalizedError {
        let errorDescription: String?
    }

    static var status: Status { status(SMAppService.mainApp.status, bundle: Bundle.main.bundleURL) }

    /// Only an app bundle can be a login item: `swift run` and the tests run a bare executable.
    static func status(_ status: SMAppService.Status, bundle: URL) -> Status {
        guard bundle.pathExtension == "app" else { return .unavailable("Open at Login works only in Locky.app") }
        switch status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .unavailable("macOS cannot find Locky.app's login item")
        @unknown default: return .unavailable("macOS reports a login item status Locky does not know")
        }
    }

    /// Registers or unregisters Locky.app. Throws when it is unavailable, and SMAppService's errors (for an app
    /// that is not signed, for one). Asking for what is already so does nothing: SMAppService would throw.
    static func set(_ enabled: Bool) throws {
        let current = status
        if case .unavailable(let message) = current { throw Unavailable(errorDescription: message) }
        switch (enabled, current) {
        case (true, .enabled), (false, .notRegistered): return
        case (true, _): try SMAppService.mainApp.register()
        case (false, _): try SMAppService.mainApp.unregister()
        }
    }

    /// For `.requiresApproval`: the Login Items list, where the user switches Locky back on.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
