import AppKit
import PermissionFlow
import PermissionFlowCameraStatus
import SystemSettingsKit

/// What Locky asks macOS for, one model for the Welcome and Settings › General: Accessibility (the Touch ID button,
/// and the keyboard at the lock screen), the camera (a photo after wrong passwords), and the login item's approval.
/// Showing a state only reads it: nothing here prompts until the person clicks Grant. PermissionFlow does the asking: it
/// opens System Settings at the page, with its panel to drag Locky into the list where the page takes a drag.
@MainActor @Observable
final class Permissions {
    /// What Locky reads and does. Tests pass their own, so no test prompts or opens System Settings.
    struct System {
        /// Reads a pane's state. It never prompts.
        var state: @MainActor (PermissionFlowPane) -> PermissionAuthorizationState
        var loginItem: @MainActor () -> LoginItem.Status
        /// Shows the camera prompt if the person has not answered it yet: their answer. nil when they answered before,
        /// so no prompt showed.
        var requestCamera: @MainActor () async -> Bool?
        /// Opens System Settings at the pane, with PermissionFlow's panel where the pane takes a drag. `from` is where the
        /// click was, in screen points, where the panel starts its flight.
        var guide: @MainActor (PermissionFlowPane, _ from: CGRect?) -> Void
        /// Closes the panel. `returning` brings back the app that was in front when it opened.
        var closeGuide: @MainActor (_ returning: Bool) -> Void
        var open: @MainActor (SystemSettingsDestination) -> Void
    }

    private(set) var accessibility: PermissionAuthorizationState
    private(set) var camera: PermissionAuthorizationState
    private(set) var loginItem: LoginItem.Status
    /// True from a Grant for Accessibility until Locky has it, a lock starts, or `pollLimit` passes. Meanwhile Locky
    /// reads it each `pollInterval`, as the person may grant it in System Settings with Locky behind.
    var guiding: Bool { poll != nil }
    /// True for the length of a lock (AppModel sets it). As it turns true the panel closes, so it never shows over or
    /// during a lock. Nothing is read then: a lock activates Locky at its start and at each keyboard reclaim, and a slow
    /// answer about the login item must not hold the main thread, which runs the guard's heartbeat.
    var locked = false {
        didSet { if locked { stopGuide(returning: false) } }
    }
    /// Runs when Accessibility changes, so the Touch ID button's tap follows at once (AppDelegate sets it).
    @ObservationIgnored var accessibilityChanged: () -> Void = {}

    @ObservationIgnored private let system: System
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let pollLimit: Duration
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var activation: NSObjectProtocol?

    init(system: System = .live(), pollInterval: Duration = .seconds(1), pollLimit: Duration = .seconds(300)) {
        self.system = system
        self.pollInterval = pollInterval
        self.pollLimit = pollLimit
        accessibility = system.state(.accessibility)
        camera = system.state(.camera)
        loginItem = system.loginItem()
        // Back from System Settings: what the person changed there shows at once.
        activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let activation { NotificationCenter.default.removeObserver(activation) }
    }

    /// Reads every state again, unless a lock is on. A state that did not change is not written, so no view draws again.
    func refresh() {
        guard !locked else { return }
        let camera = system.state(.camera), loginItem = system.loginItem()
        if camera != self.camera { self.camera = camera }
        if loginItem != self.loginItem { self.loginItem = loginItem }
        readAccessibility()
    }

    /// Reads Accessibility again: alone during a guide, once a second.
    private func readAccessibility() {
        let trusted = system.state(.accessibility)
        guard trusted != accessibility else { return }
        accessibility = trusted
        accessibilityChanged()
        // Granted: the panel's work is done. During a guide the person comes back to Locky.
        if trusted == .granted { stopGuide(returning: guiding) }
    }

    /// Grant for Accessibility: System Settings › Privacy & Security › Accessibility, with the panel to drag Locky in.
    /// Once granted, the button opens the page without the panel.
    func grantAccessibility(from source: CGRect? = Permissions.clickFrame()) {
        guard !locked else { return }
        guard accessibility != .granted else { return system.open(.privacy(anchor: PermissionFlowPane.accessibility.privacyAnchor)) }
        system.guide(.accessibility, source)
        startPolling()
    }

    /// Grant for the camera: macOS's prompt if the person never answered it, else the Camera page in System Settings,
    /// the only place to change the answer.
    func grantCamera() {
        guard !locked else { return }
        guard camera != .granted else { return system.open(.privacy(anchor: PermissionFlowPane.camera.privacyAnchor)) }
        Task {
            if await system.requestCamera() == nil { system.guide(.camera, nil) }
            refresh()
        }
    }

    /// The prompt only, when Take a photo turns on, while the person is here: during a lock the camera never asks.
    func askForCamera() {
        Task {
            if await system.requestCamera() != nil { refresh() }
        }
    }

    /// Grant for the login item: System Settings › General › Login Items, where the person switches Locky on.
    func approveLoginItem() {
        guard !locked else { return }
        system.open(.loginItems)
    }

    private func startPolling() {
        poll?.cancel()
        let interval = pollInterval, deadline = ContinuousClock.now + pollLimit
        poll = Task { [weak self] in
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                readAccessibility()
                // readAccessibility() ended the guide once Locky had it.
                guard guiding else { return }
            }
            self?.poll = nil
        }
    }

    private func stopGuide(returning: Bool) {
        poll?.cancel()
        poll = nil
        system.closeGuide(returning)
    }

    // MARK: Rules the tests reach

    /// The login item as PermissionFlow's states: waiting for approval is not granted.
    nonisolated static func state(_ status: LoginItem.Status) -> PermissionAuthorizationState {
        switch status {
        case .enabled: .granted
        case .requiresApproval: .notGranted
        case .notRegistered, .unavailable: .unknown
        }
    }

    /// The language of PermissionFlow's words in Locky's windows: Locky's own, which is English. The panel next to
    /// System Settings follows the system's language instead, as System Settings does.
    nonisolated static let language = "en"

    /// A button's title in PermissionFlow's words: Grant, Granted, Open, Checking...
    nonisolated static func title(_ state: PermissionAuthorizationState) -> String {
        let look = PermissionFlowButtonState.make(from: state)
        return PermissionFlowResources.localizedString(for: look.titleKey, defaultValue: look.defaultTitle, localeIdentifier: language)
    }

    /// The name System Settings gives Accessibility: Device Control and Data Access from macOS 27.
    nonisolated static func accessibilityName(_ version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> String {
        let key = PermissionFlowResources.accessibilityName(operatingSystemVersion: version)
        let english = key == PermissionFlowResources.deviceControlAndDataAccessNameKey ? "Device Control and Data Access" : "Accessibility"
        return PermissionFlowResources.localizedString(for: key, defaultValue: english, localeIdentifier: language)
    }

    /// Where the click that starts a guide was, as PermissionFlowButton reads it: the panel flies out from there.
    static func clickFrame() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x - 16, y: mouse.y - 16, width: 32, height: 32)
    }
}

extension Permissions.System {
    /// macOS. One PermissionFlow controller serves every Grant, so a lock can close the one panel there is.
    /// `notGranted` shows every permission as not granted, for screenshots of those rows (a tool run only).
    @MainActor static func live(notGranted: Bool = false) -> Self {
        PermissionFlowCameraStatus.register()
        let guide = Guide()
        return Self(
            state: { notGranted ? .notGranted : PermissionStatusRegistry.provider(for: $0).authorizationState() },
            loginItem: { notGranted ? .requiresApproval : LoginItem.status },
            requestCamera: { CameraAccess.status == .notDetermined ? await CameraAccess.request() : nil },
            guide: guide.start,
            closeGuide: guide.close,
            open: { SystemSettings.open($0) })
    }
}

/// The PermissionFlow controller, made at the first Grant.
@MainActor
private final class Guide {
    private var controller: PermissionFlowController?

    func start(_ pane: PermissionFlowPane, from source: CGRect?) {
        let controller = controller ?? PermissionFlow.makeController()
        self.controller = controller
        controller.authorize(pane: pane, suggestedAppURLs: [Bundle.main.bundleURL], sourceFrameInScreen: source)
    }

    func close(returning: Bool) {
        controller?.closePanel(returnToPreviousApp: returning)
    }
}
