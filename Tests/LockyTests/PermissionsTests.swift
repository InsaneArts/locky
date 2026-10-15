import AppKit
import PermissionFlow
import SwiftUI
import SystemSettingsKit
import Testing
@testable import Locky

@MainActor @Suite struct PermissionsTests {
    /// macOS as a test sets it: what it answers, and each read, prompt, panel, and page Locky asks for.
    @MainActor final class Mac {
        var states: [PermissionFlowPane: PermissionAuthorizationState] = [.accessibility: .notGranted, .camera: .notGranted]
        var loginItem = LoginItem.Status.notRegistered
        /// The camera prompt's answer; nil: answered before, so no prompt.
        var cameraAnswer: Bool?
        private(set) var reads = 0
        private(set) var prompts = 0
        private(set) var guides: [PermissionFlowPane] = []
        private(set) var closes: [Bool] = []
        private(set) var opened: [SystemSettingsDestination] = []

        var system: Permissions.System {
            Permissions.System(
                state: { self.reads += 1; return self.states[$0] ?? .unknown },
                loginItem: { self.loginItem },
                requestCamera: {
                    guard let answer = self.cameraAnswer else { return nil }
                    self.prompts += 1
                    self.states[.camera] = answer ? .granted : .notGranted
                    return answer
                },
                guide: { pane, _ in self.guides.append(pane) },
                closeGuide: { self.closes.append($0) },
                open: { self.opened.append($0) })
        }

        /// Nothing that asks the person or shows them anything happened.
        var quiet: Bool { prompts == 0 && guides.isEmpty && opened.isEmpty }
    }

    /// Polls `condition` on the main actor, which a full test run keeps busy for seconds at a time.
    private func wait(timeout: Double = 10, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }

    // MARK: States and words

    /// The login item in PermissionFlow's states: only waiting for approval asks for a Grant.
    @Test func theLoginItemMapsToPermissionFlowStates() {
        #expect(Permissions.state(.enabled) == .granted)
        #expect(Permissions.state(.requiresApproval) == .notGranted)
        #expect(Permissions.state(.notRegistered) == .unknown)
        #expect(Permissions.state(.unavailable("no")) == .unknown)
    }

    /// The buttons say what PermissionFlowButton says, in Locky's language.
    @Test func theButtonsUsePermissionFlowsWords() {
        #expect(Permissions.title(.granted) == "Granted")
        #expect(Permissions.title(.notGranted) == "Grant")
        #expect(Permissions.title(.unknown) == "Open")
        #expect(PermissionFlowButtonState.make(from: .granted).isGranted)
        #expect(!PermissionFlowButtonState.make(from: .notGranted).isGranted)
    }

    /// The row names the page as System Settings does: Device Control and Data Access from macOS 27.
    @Test func accessibilityHasSystemSettingsName() {
        #expect(Permissions.accessibilityName(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)) == "Accessibility")
        #expect(Permissions.accessibilityName(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
            == "Device Control and Data Access")
    }

    /// The Touch ID button's switch takes a click with Accessibility, and without it only to turn off.
    @Test func theTouchIDSwitchWaitsForAccessibility() {
        #expect(LockKeyToggle.usable(granted: true, on: false))
        #expect(LockKeyToggle.usable(granted: true, on: true))
        #expect(!LockKeyToggle.usable(granted: false, on: false))
        #expect(LockKeyToggle.usable(granted: false, on: true))
    }

    /// The switch in its window: off and dimmed without Accessibility, and usable the moment Locky has it.
    @Test func theTouchIDSwitchTurnsUsableWhenGranted() async throws {
        _ = NSApplication.shared
        let mac = Mac()
        let model = AppModel(store: SettingsStore(config: try Sandbox().config), permissions: Permissions(system: mac.system))
        let view = NSHostingView(rootView: Form { LockKeyToggle(model: model) }.formStyle(.grouped))
        view.frame.size = CGSize(width: 520, height: 120)
        func enabled() -> Bool? {
            view.layoutSubtreeIfNeeded()
            func find(_ view: NSView) -> NSControl? { (view as? NSSwitch) ?? view.subviews.lazy.compactMap(find).first }
            return find(view)?.isEnabled
        }
        #expect(enabled() == false)
        mac.states[.accessibility] = .granted
        model.permissions.refresh()
        #expect(await wait { enabled() == true })
    }

    // MARK: Showing never asks

    /// The Welcome's page 2 and Settings › General read the states and ask for nothing: no prompt, no panel, no System
    /// Settings, also with every permission missing and the login item waiting.
    @Test func showingTheStatesAsksForNothing() throws {
        _ = NSApplication.shared
        let mac = Mac()
        mac.loginItem = .requiresApproval
        let model = AppModel(store: SettingsStore(config: try Sandbox().config), permissions: Permissions(system: mac.system))
        model.screenshots = true
        model.store.update { $0["intruder_photo"] = .int(3) }
        let visit = WelcomeVisit()
        visit.page = .lockScreen
        for root in [AnyView(WelcomeView(model: model, visit: visit, close: {})), AnyView(SettingsPage(model: model).frame(width: 600, height: 900))] {
            let view = NSHostingView(rootView: root)
            view.layoutSubtreeIfNeeded()
            #expect(view.fittingSize.height > 0)
        }
        #expect(mac.reads > 0)
        #expect(mac.quiet)
    }

    // MARK: Live states

    /// Back from System Settings, the states are read again; during a lock nothing is read.
    @Test func comingForwardReadsTheStatesAgain() async {
        let mac = Mac()
        let permissions = Permissions(system: mac.system)
        var changes = 0
        permissions.accessibilityChanged = { changes += 1 }
        mac.states = [.accessibility: .granted, .camera: .granted]
        mac.loginItem = .enabled
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(await wait { permissions.accessibility == .granted })
        #expect(permissions.camera == .granted && permissions.loginItem == .enabled)
        #expect(changes == 1)

        permissions.locked = true
        let reads = mac.reads
        mac.states[.accessibility] = .notGranted
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(mac.reads == reads && permissions.accessibility == .granted)
        #expect(mac.quiet)
    }

    /// Grant for Accessibility opens PermissionFlow's guide and reads the state while it shows, as the person grants it
    /// with Locky behind. Granted, the panel closes and Locky comes back; the reads stop.
    @Test func theGuideFollowsTheGrantLive() async {
        let mac = Mac()
        let permissions = Permissions(system: mac.system, pollInterval: .milliseconds(10))
        var changes = 0
        permissions.accessibilityChanged = { changes += 1 }
        permissions.grantAccessibility(from: nil)
        #expect(mac.guides == [.accessibility] && permissions.guiding)
        mac.states[.accessibility] = .granted
        #expect(await wait { permissions.accessibility == .granted })
        #expect(!permissions.guiding && mac.closes == [true] && changes == 1)
        let reads = mac.reads
        try? await Task.sleep(for: .milliseconds(100))
        #expect(mac.reads == reads)

        // Granted, the button opens the page without the panel.
        permissions.grantAccessibility(from: nil)
        #expect(mac.guides == [.accessibility] && mac.opened == [.privacy(anchor: .privacyAccessibility)])
    }

    /// The reads stop after the limit, granted or not.
    @Test func theGuideStopsReadingAfterItsLimit() async {
        let mac = Mac()
        let permissions = Permissions(system: mac.system, pollInterval: .milliseconds(10), pollLimit: .milliseconds(80))
        permissions.grantAccessibility(from: nil)
        #expect(await wait { !permissions.guiding })
        let reads = mac.reads
        try? await Task.sleep(for: .milliseconds(100))
        #expect(mac.reads == reads && permissions.accessibility == .notGranted)
    }

    /// A lock closes PermissionFlow's panel at its start and stops the reads, and no Grant opens one during it. Through
    /// AppModel.locked, as AppDelegate starts a lock.
    @Test func aLockClosesThePanel() async throws {
        _ = NSApplication.shared
        let mac = Mac()
        let model = AppModel(store: SettingsStore(config: try Sandbox().config),
                             permissions: Permissions(system: mac.system, pollInterval: .milliseconds(10)))
        model.permissions.grantAccessibility(from: nil)
        #expect(model.permissions.guiding)
        model.locked = true
        #expect(mac.closes == [false] && !model.permissions.guiding)
        let reads = mac.reads
        try? await Task.sleep(for: .milliseconds(100))
        #expect(mac.reads == reads)
        model.permissions.grantAccessibility(from: nil)
        model.permissions.grantCamera()
        model.permissions.approveLoginItem()
        #expect(mac.guides == [.accessibility] && mac.opened.isEmpty)
        model.locked = false
        #expect(mac.closes == [false])
    }

    /// Grant for the camera shows macOS's prompt when the person never answered it, and System Settings' Camera page
    /// when they did, the only place to change the answer.
    @Test func cameraGrantPromptsOnceThenOpensSettings() async {
        let mac = Mac()
        mac.cameraAnswer = true
        let first = Permissions(system: mac.system)
        first.grantCamera()
        #expect(await wait { first.camera == .granted })
        #expect(mac.prompts == 1 && mac.guides.isEmpty)
        first.grantCamera()
        #expect(mac.opened == [.privacy(anchor: .privacyCamera)])

        let denied = Mac()
        let second = Permissions(system: denied.system)
        second.grantCamera()
        #expect(await wait { denied.guides == [.camera] })
        #expect(denied.prompts == 0 && second.camera == .notGranted)
    }

    /// Turning Take a photo on asks with the prompt only: an answer given before opens nothing.
    @Test func takeAPhotoOnlyPrompts() async {
        let mac = Mac()
        let permissions = Permissions(system: mac.system)
        permissions.askForCamera()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(mac.quiet)
        mac.cameraAnswer = false
        permissions.askForCamera()
        #expect(await wait { mac.prompts == 1 })
        #expect(mac.guides.isEmpty && mac.opened.isEmpty)
    }

    /// The login item's Grant opens System Settings › General › Login Items.
    @Test func loginItemsGrantOpensLoginItems() {
        let mac = Mac()
        Permissions(system: mac.system).approveLoginItem()
        #expect(mac.opened == [.loginItems])
    }
}
