import AppKit
import Sparkle

/// Updates of Locky itself, through Sparkle. Once a day Locky reads the feed of its latest release (SUFeedURL in the
/// app's Info.plist, which Scripts/package_app.sh writes), and it asks before it installs a new version. Sparkle
/// installs one only if its EdDSA signature matches SUPublicEDKey. A tool run never starts this.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    private let isLocked: () -> Bool

    init(isLocked: @escaping () -> Bool) {
        self.isLocked = isLocked
    }

    /// Starts Sparkle once, at launch. The bare binary has no feed in an Info.plist, and so no updates.
    func start() {
        guard controller == nil, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    /// Locky › Check for Updates…: Sparkle shows its own windows, "You're up to date" included.
    func check() {
        controller?.checkForUpdates(nil)
    }

    /// False before Sparkle starts, during a lock, and while a check runs.
    var canCheck: Bool {
        controller?.updater.canCheckForUpdates == true && refusal() == nil
    }

    /// Why no check may start now, or nil. During a lock, Sparkle's windows would open behind the lock.
    func refusal() -> NSError? {
        guard isLocked() else { return nil }
        return NSError(domain: "Locky.Updater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Locky checks for updates when the Mac is not locked."])
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if let refusal = refusal() { throw refusal }
    }
}
