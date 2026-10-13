import LocalAuthentication
import SwiftUI

/// The first launch's one screen: the lock screen in use, a real lock to try, the two switches that make Locky lock by
/// itself, and where Locky lives. Each switch saves at once. Done and the close button close the window; Help › Welcome
/// to Locky opens it again.
struct WelcomeView: View {
    let model: AppModel
    let close: () -> Void
    /// The triggers the switch turned off, which turning it on again restores. The window is kept between visits, and so
    /// is this.
    @State private var turnedOff: AutoLockSettings?
    /// Whether this Mac can use Touch ID, read once: an LAContext on every body pass is waste.
    @State private var biometrics = false

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

    var body: some View {
        let theme = model.activeTheme
        let info = model.inspection.theme(theme)
        let stored = model.store.settings.autoLock
        VStack(spacing: 0) {
            Text("Welcome to Locky")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 12)
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
            Form {
                Section {
                    Toggle(isOn: autoLock) {
                        Text("Lock automatically")
                        // While it is off: what turning it on stores.
                        Text(Self.autoLockSummary(stored != AutoLockSettings() ? stored : turnedOff ?? Self.defaultAutoLock))
                    }
                    OpenAtLoginToggle(model: model, subtitle: "Locky locks by itself only while it's open.")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .frame(width: 520)
            HStack {
                // The symbol is the menu bar icon's.
                Text("Find Locky in the menu bar \(Image(systemName: "lock.fill"))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Find Locky in the menu bar")
                Spacer()
                Button("Done") { close() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
        .frame(width: 560)
        .onAppear { biometrics = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) }
    }

    /// On while any trigger is stored. A change goes to the file as it is now, through `setAutoLock(_:in:turnedOff:)`.
    private var autoLock: Binding<Bool> {
        Binding(get: { model.store.settings.autoLock != AutoLockSettings() },
                set: { on in model.store.update { Self.setAutoLock(on, in: &$0, turnedOff: &turnedOff) } })
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
