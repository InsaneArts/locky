import AppKit
import LocalAuthentication
import SwiftUI

/// One visit to the Welcome: the page it shows, and the triggers its switch turned off. The window keeps it; closing
/// the window ends the visit, so the next one starts on the first page.
@MainActor @Observable
final class WelcomeVisit {
    var page = WelcomeView.Page.welcome
    /// The triggers the switch turned off during this visit, which turning it on again restores.
    var turnedOff: AutoLockSettings?

    func end() {
        page = .welcome
        turnedOff = nil
    }
}

/// The first launch's three pages: the lock screen in use with a real lock to try; what makes Locky lock instead of
/// macOS; and what happens if something goes wrong. Each switch saves at once. Done and the close button close the
/// window; Help › Welcome to Locky opens it again.
struct WelcomeView: View {
    let model: AppModel
    let visit: WelcomeVisit
    let close: () -> Void
    /// Whether this Mac can use Touch ID now, read when the window opens and each time it comes forward: an LAContext on
    /// every body pass is waste.
    @State private var biometrics = false
    /// Accessibility, which the keyboard row asks for, read at the same times.
    @State private var trusted = AXIsProcessTrusted()
    /// Whether this Mac has a Touch ID button, read at the same times.
    @State private var hasButton = false
    /// The first page's height, which the other pages keep, so the buttons stay in place.
    @State private var height: CGFloat = 0
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Page: Int, CaseIterable {
        case welcome, lockScreen, safety

        var next: Page? { Page(rawValue: rawValue + 1) }
        var previous: Page? { Page(rawValue: rawValue - 1) }
    }

    /// Set once the Welcome has opened by itself.
    static let shownKey = "welcomeShown"

    /// Whether this launch opens the Welcome: the first one that is not a tool run. Asking marks it shown, so it
    /// opens by itself only once.
    static func opensAtLaunch(_ defaults: UserDefaults, isTool: Bool) -> Bool {
        guard !isTool, !defaults.bool(forKey: shownKey) else { return false }
        defaults.set(true, forKey: shownKey)
        return true
    }

    /// What turning on "Lock automatically" stores when it has nothing of its own to restore.
    static let defaultAutoLock = AutoLockSettings(idleMinutes: 5, systemSleep: true)

    // The last page's lines. docs/security.md opens with the same words, and a test keeps the two the same.
    static let guardLine = "If Locky crashes, hangs, or is killed during a lock, a second process shows the macOS lock screen within 8 seconds."
    static let wayOutLine = "On the lock screen, press ⌃⌥⌘Q to switch to the macOS lock screen."
    static let unlockOnlyLine = "Locky unlocks only with your login password or Touch ID, never after a time."

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                switch visit.page {
                case .welcome:
                    welcomePage
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
                case .lockScreen: lockScreenPage
                case .safety: safetyPage
                }
            }
            .frame(minHeight: height, alignment: .top)
            buttons
        }
        .frame(width: 560)
        .onAppear(perform: readSystem)
        // onAppear runs once for the window's life, so read again each time the window comes forward: the lid may have
        // closed, a Touch ID keyboard gone, or Accessibility changed in System Settings since the last read.
        .onChange(of: appearsActive) { if appearsActive { readSystem() } }
    }

    // MARK: Pages

    private var welcomePage: some View {
        let theme = model.activeTheme
        let info = model.inspection.theme(theme)
        return VStack(spacing: 0) {
            title("Welcome to Locky")
            Text("Locky is a lock screen for your Mac, with themes and widgets you choose.")
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            ThemePreview(theme: theme, settings: model.store.settings, sources: model.inspection.sources, config: model.store.config,
                         alwaysLive: model.screenshots, info: info)
                .frame(width: 480, height: 300)
                .previewFrame()
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel("Lock screen preview")
                .accessibilityValue(info?.name ?? theme)
                .padding(.top, 16)
            Button { model.lockNow() } label: { Label("Lock Now", systemImage: "lock.fill") }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, 16)
            // The lock screen's own rule, so the line says what the next lock offers.
            Text(Self.unlockLine(touchID: biometrics && model.store.settings["touch_id"].bool != false))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
    }

    /// What makes Locky lock instead of macOS, and what stays Apple's.
    private var lockScreenPage: some View {
        let stored = model.store.settings.autoLock
        let broken = model.store.problem != nil
        return VStack(spacing: 0) {
            Spacer(minLength: 16)
            hero("lock.laptopcomputer")
            title("Make Locky Your Lock Screen")
            Form {
                Section {
                    Toggle(isOn: autoLock) {
                        Text("Lock automatically")
                        if broken {
                            // The store saves nothing while the file has an error. The switch shows what Locky still uses.
                            // In the subtitle's font and color, as the Form gives a Text here, so the row keeps its height.
                            HStack(spacing: 8) {
                                WarningLabel("settings.json has an error, so this can't change.")
                                    .foregroundStyle(.secondary)
                                Button("Open Settings") { model.openWindow(.settings) }
                                    .buttonStyle(.link)
                                    // The row is disabled, but not the way out of it.
                                    .environment(\.isEnabled, true)
                            }
                            .font(.subheadline)
                        } else {
                            // While it is off: what turning it on stores.
                            Text(Self.autoLockSummary(stored != AutoLockSettings() ? stored : visit.turnedOff ?? Self.defaultAutoLock))
                        }
                    }
                    .disabled(broken)
                    OpenAtLoginToggle(model: model, subtitle: "Locky locks only while it's open.")
                    ShortcutRecorder("Lock Now shortcut", shortcut: Binding(get: { model.store.settings.shortcut }, set: { shortcut in
                        model.store.update { $0.shortcut = shortcut }
                    }), onRecordingChange: model.recordingShortcut)
                    .disabled(broken)
                    if let problem = model.shortcutProblem {
                        WarningLabel(problem)
                    }
                    // The Touch ID button's row asks for Accessibility for both: one Allow… on the page.
                    if hasButton {
                        LockKeyToggle(model: model, trusted: $trusted)
                            .disabled(broken)
                    } else {
                        KeyboardAccess(trusted: $trusted)
                    }
                } footer: {
                    Text(Self.lockScreenFooter(hasButton: hasButton, buttonLocks: model.store.settings.lockKey && trusted))
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .frame(width: 520)
            // At its rows' height, so the spacers center it: a Form takes all the height it is offered.
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 16)
        }
        .frame(maxHeight: .infinity)
    }

    /// The safety net, in the words docs/security.md opens with.
    private var safetyPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            hero("lifepreserver")
            title("If Something Goes Wrong")
            VStack(alignment: .leading, spacing: 24) {
                row("lock.trianglebadge.exclamationmark", Self.guardLine)
                // The lock's own rule: settings.json can turn the way out off.
                if model.store.settings["emergency_exit"].bool != false {
                    row("keyboard", Self.wayOutLine)
                }
                row("touchid", Self.unlockOnlyLine)
            }
            .padding(.horizontal, 48)
            .padding(.top, 28)
            Spacer(minLength: 16)
        }
        .frame(maxHeight: .infinity)
    }

    /// The large symbol over a page's title, where page 1 has its preview: the page and its title read as one group.
    private func hero(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 56))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.largeTitle.bold())
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 12)
    }

    /// A symbol and one sentence, read by VoiceOver as the sentence.
    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 40)
                .accessibilityHidden(true)
            Text(text)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Back, and Continue or Done at the bottom right. Return is Continue and Done, ⌘[ is Back, and Esc closes (the window's).
    private var buttons: some View {
        HStack {
            if visit.page == .safety {
                // The symbol is the menu bar icon's.
                Text("Find Locky in the menu bar \(Image(systemName: "lock.fill"))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Find Locky in the menu bar")
            }
            Spacer()
            // The actions read the page when they run: a keyboard shortcut can keep the action of the page it was made on.
            if visit.page.previous != nil {
                Button("Back") { go(to: visit.page.previous) }
                    .controlSize(.large)
                    .keyboardShortcut("[")
            }
            Group {
                if visit.page.next != nil {
                    Button("Continue") { go(to: visit.page.next) }
                } else {
                    Button("Done") { close() }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
    }

    /// A short cross-fade for a click; none for a key (Motion) or with Reduce Motion.
    private func go(to page: Page?) {
        guard let page else { return }
        let key = NSApp.currentEvent?.type == .keyDown
        withAnimation(key || reduceMotion ? nil : Motion.easeOut(duration: 0.25)) { visit.page = page }
    }

    private func readSystem() {
        biometrics = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        trusted = AXIsProcessTrusted()
        hasButton = LockKeyToggle.hasButton()
    }

    /// What still shows the macOS lock screen: the Touch ID button too, while Locky does not take it.
    static func lockScreenFooter(hasButton: Bool, buttonLocks: Bool) -> String {
        let others = hasButton && !buttonLocks ? "The Apple menu's Lock Screen, ⌃⌘Q, and the Touch ID button" : "The Apple menu's Lock Screen and ⌃⌘Q"
        return "\(others) still show the macOS lock screen. Locky does not change the macOS password setting."
    }

    /// On while any trigger is stored. A change goes to the file as it is now, through `setAutoLock(_:in:turnedOff:)`.
    private var autoLock: Binding<Bool> {
        Binding(get: { model.store.settings.autoLock != AutoLockSettings() },
                set: { on in model.store.update { Self.setAutoLock(on, in: &$0, turnedOff: &visit.turnedOff) } })
    }

    /// Turns "Lock automatically" on or off in `settings`. Off keeps the triggers it clears in `turnedOff`; on restores
    /// those, else stores the default. Both edit auto_lock in place, so its other keys stay.
    static func setAutoLock(_ on: Bool, in settings: inout Settings, turnedOff: inout AutoLockSettings?) {
        if on {
            // A trigger set elsewhere a moment ago stays as it is.
            guard settings.autoLock == AutoLockSettings() else { return }
            settings.setAutoLock(turnedOff ?? defaultAutoLock)
        } else {
            // Nothing stored, as after an edit elsewhere that no file event has reported yet: nothing to keep, so on
            // still stores the default.
            guard settings.autoLock != AutoLockSettings() else { return }
            turnedOff = settings.autoLock
            settings.setAutoLock(AutoLockSettings())
        }
    }

    /// The triggers in the words Settings uses, as one sentence: "After 5 minutes of inactivity and when the Mac sleeps."
    /// None: what turning the switch on stores by default.
    static func autoLockSummary(_ triggers: AutoLockSettings) -> String {
        guard triggers != AutoLockSettings() else { return autoLockSummary(defaultAutoLock) }
        var parts: [String] = []
        if let minutes = triggers.idleMinutes {
            // settings.json may hold any positive number; Int(exactly:) never traps on one.
            let count = Int(exactly: minutes).map { "\($0)" } ?? "\(minutes)"
            parts.append(minutes == 1 ? "after 1 minute of inactivity" : "after \(count) minutes of inactivity")
        }
        if triggers.screenSaver || triggers.displaySleep { parts.append("when the screen saver starts or the display turns off") }
        if triggers.systemSleep { parts.append("when the Mac sleeps") }
        let list = parts.count < 3 ? parts.joined(separator: " and ") : "\(parts[0]), \(parts[1]), and \(parts[2])"
        return list.capitalizedFirst + "."
    }

    /// The line under Lock Now: Touch ID only when the next lock offers it.
    static func unlockLine(touchID: Bool) -> String {
        touchID ? "Unlock with Touch ID or your password." : "Unlock with your password."
    }
}
