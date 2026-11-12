import AppKit
import LocalAuthentication
import SwiftUI

/// One pane of the Settings window: a grouped form. Each change saves to settings.json at once. While the file has an
/// error, every pane starts with it and the way out of it, and the pane's own rows wait.
struct SettingsPane<Content: View>: View {
    let model: AppModel
    /// Stays usable with a broken settings.json: Customization, whose folder is where the file is fixed.
    var live = false
    @ViewBuilder var content: Content
    /// Why the last Restore Last Good Settings failed, until one works.
    @State private var restoreError: String?

    var body: some View {
        let store = model.store
        // The settings.json error comes and goes at once: the grouped Form cannot slide the rows below a whole group, and
        // cross-fades the whole pane instead.
        Form {
            if let problem = store.problem {
                Section {
                    WarningLabel(problem)
                        .textSelection(.enabled)
                    Button("Restore Last Good Settings") {
                        do {
                            try store.resetBrokenFile()
                            restoreError = nil
                        } catch {
                            restoreError = "Could not restore: " + ((error as? LuaError)?.message ?? error.localizedDescription)
                        }
                    }
                    if let restoreError { WarningLabel(restoreError) }
                } footer: {
                    Text("Locky keeps using the last settings that worked. Restoring moves the broken file aside.")
                }
            }
            // While the file has an error, everything but the way out of it waits.
            content.disabled(!live && store.problem != nil)
        }
        .formStyle(.grouped)
    }
}

/// Settings › General: what lets Locky lock at all, and when it locks by itself. A row Lua also reads stores no key
/// while it shows init.lua's value, so the row is its own reset.
struct SettingsPage: View {
    let model: AppModel

    var body: some View {
        SettingsPane(model: model) {
            StartSection(model: model)
            AutoLockSection(model: model)
        }
    }

    // MARK: Rules the tests reach

    /// When inactive: Never, the usual times, and a stored time that is not one of them, as "For 7 minutes (custom)".
    nonisolated static func idleChoices(stored: Int?) -> [(minutes: Int?, title: String)] {
        choices("Never", [1, 2, 5, 10, 15, 30, 60], stored: stored) { $0 == 60 ? "For 1 hour" : "For \(plural($0, "minute"))" }
            .map { ($0.value, $0.title) }
    }

    /// Turn the display off: no key (the system's display sleep applies), the usual times, and a stored time that is not
    /// one of them, as "After 90 seconds (custom)".
    nonisolated static func displayOffChoices(stored: Int?) -> [(seconds: Int?, title: String)] {
        choices("Like the system", [10, 30, 60, 300], stored: stored) { seconds in
            seconds % 60 == 0 ? "After \(plural(seconds / 60, "minute"))" : "After \(plural(seconds, "second"))"
        }
        .map { ($0.value, $0.title) }
    }

    /// The one switch for the moment macOS treats as one ("Require password after screen saver begins or display is
    /// turned off"): it writes both keys, in place, so auto_lock's other keys stay.
    nonisolated static func setScreenSaverOrDisplay(_ on: Bool, in settings: inout Settings) {
        settings.setAutoLock("display_sleep", on ? .bool(true) : nil)
        settings.setAutoLock("screen_saver", on ? .bool(true) : nil)
    }

    /// Hide personal information. On always stores true, so privacy never depends on init.lua running: settings.json
    /// applies after it too. Off stores false only against init.lua's true, and no key otherwise.
    nonisolated static func setPrivacy(_ on: Bool, base: LuaValue, in settings: inout Settings) {
        settings["privacy"] = if on { .bool(true) } else if base == .bool(true) { .bool(false) } else { .nil }
    }

    /// The lock screen message as the lock reads it: trimmed, 200 characters at most. Whitespace that the cut leaves at
    /// the end goes too, so the text reads the same the second time.
    nonisolated static func messageText(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The Message field's save. init.lua's message is read as the lock reads it, so its own message stores no key, also
    /// with spaces around it or past 200 characters. An empty message over init.lua's stores "", which hides it.
    nonisolated static func setMessage(_ text: String, base: LuaValue, in settings: inout Settings) {
        let value = messageText(text), baseText = base.string.map(messageText)
        settings.setLuaValue("message", value.isEmpty && (baseText ?? "").isEmpty ? .nil : .string(value),
                             base: baseText.map(LuaValue.string) ?? .nil)
    }

    /// A stored time as its pop-up's whole number, rounded up: a billion at most, so no number in the file can stop the pane.
    nonisolated static func whole(_ value: Double?) -> Int? {
        value.map { Int(min($0.rounded(.up), 1e9)) }
    }

    /// A pop-up's items: `first` (no key), `usual` with their titles, and a stored value that is not one of them as a
    /// custom item (HIG Pop-up buttons). Titles are plain English: `Duration.formatted` rounds 90 s to "2 minutes" and
    /// follows the system language inside English strings.
    fileprivate nonisolated static func choices(_ first: String, _ usual: [Int], stored: Int?,
                                                title: (Int) -> String) -> [(value: Int?, title: String)] {
        var items: [(value: Int?, title: String)] = [(nil, first)]
        items += usual.map { ($0, title($0)) }
        if let stored, !usual.contains(stored) { items.append((stored, title(stored) + " (custom)")) }
        return items
    }

    /// "1 minute", "7 minutes".
    fileprivate nonisolated static func plural(_ number: Int, _ unit: String) -> String {
        number == 1 ? "1 \(unit)" : "\(number) \(unit)s"
    }
}

/// Settings › Lock Screen: what the lock screen says and hides, how it comes and goes, and when its display turns off.
struct LockScreenPage: View {
    let model: AppModel

    var body: some View {
        SettingsPane(model: model) { LockScreenSections(model: model) }
    }
}

/// Settings › Unlock: how the lock screen lets people in, and what it does about the ones it should not. The photos it
/// took come first, while there are any.
struct UnlockPage: View {
    let model: AppModel
    /// The intruder photos, newest first. They are read when the pane is built, when a lock ends, and after each config
    /// read. The window opens after the lock that took them, so they are on its first frame; a photo still saving when
    /// the lock ended comes with the next config read.
    @State private var photos: [(url: URL, date: Date)]

    init(model: AppModel) {
        self.model = model
        _photos = State(initialValue: Self.photos(for: model))
    }

    var body: some View {
        // The Photos group comes and goes at once, as the settings.json error does.
        SettingsPane(model: model) {
            if !photos.isEmpty {
                PhotosSection(model: model, photos: photos, delete: delete, deleteAll: deleteAll)
            }
            UnlockSection(model: model)
        }
        .task(id: model.revision) { loadPhotos() }
        .modifier(WhenLockEnds(model: model, action: loadPhotos))
    }

    private func loadPhotos() {
        photos = Self.photos(for: model)
    }

    /// The photos to show. A screenshot run shows none.
    private static func photos(for model: AppModel) -> [(url: URL, date: Date)] {
        model.screenshots ? [] : IntruderLog().photos()
    }

    private func delete(_ photo: URL) {
        try? IntruderLog().delete(photo)
        loadPhotos()
    }

    private func deleteAll() {
        try? IntruderLog().deleteAll()
        loadPhotos()
    }
}

/// Settings › Customization: the config folder, new themes and widgets, the agent skill, and the log.
struct CustomizationPage: View {
    let model: AppModel

    var body: some View {
        SettingsPane(model: model, live: true) { CustomizationSection(model: model) }
    }
}

/// Runs `action` when a lock ends, also while the Settings window is closed. `model.locked` is read here and not in the
/// page's body, so a lock's start does not build the page again: building UnlockSection reads the Touch ID state, and
/// during a lock the main thread runs the guard's heartbeat.
private struct WhenLockEnds: ViewModifier {
    let model: AppModel
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: model.locked) { _, locked in
            if !locked { action() }
        }
    }
}

/// The photos the camera took after wrong passwords, first in the pane while there are any.
private struct PhotosSection: View {
    let model: AppModel
    let photos: [(url: URL, date: Date)]
    let delete: (URL) -> Void
    let deleteAll: () -> Void
    @State private var confirming = false

    var body: some View {
        Section {
            IntruderPhotos(photos: photos, delete: delete)
        } header: {
            HStack {
                Text("Photos")
                Spacer()
                Button("Delete All…") { confirming = true }
                    .buttonStyle(.link)
                    // The person asked for it, so the button is the default one and not destructive.
                    .alert("Delete all photos?", isPresented: $confirming) {
                        Button("Delete All", action: deleteAll)
                            .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This can’t be undone.")
                    }
            }
        } footer: {
            Text("Locky took these when someone typed wrong passwords.")
        }
        // A lock cancels the alert: Return at the lock must not delete the photos. Read here, not in the page's body.
        .onChange(of: model.locked) { if model.locked { confirming = false } }
    }
}

/// Open at login, then the two ways to lock now: the shortcut and the Touch ID button. Accessibility comes just before
/// the button's switch, which waits for it, as on the Welcome.
private struct StartSection: View {
    let model: AppModel
    @State private var hasButton = LockKeyToggle.hasButton()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section("App") {
            OpenAtLoginToggle(model: model, subtitle: waitsOnLocky ? "Locky locks only while it’s open." : nil)
        }
        .animation(Motion.rows(reduceMotion), value: model.loginItem)
        Section("Lock Now") {
            ShortcutRecorder("Lock Now shortcut", shortcut: Binding(get: { model.store.settings.shortcut }, set: { shortcut in
                model.store.update { $0.shortcut = shortcut }
            }), onRecordingChange: model.recordingShortcut)
            if let problem = model.shortcutProblem {
                WarningLabel(problem)
            }
            AccessibilityRow(permissions: model.permissions, hasButton: hasButton)
            if hasButton {
                LockKeyToggle(model: model)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // A lock activates Locky at its start and at each keyboard reclaim: nothing is read then.
            guard !model.locked else { return }
            hasButton = LockKeyToggle.hasButton()
        }
    }

    /// Locky does not open at login, and auto-lock, the shortcut, or the Touch ID button needs it running.
    private var waitsOnLocky: Bool {
        let settings = model.store.settings
        return model.loginItem == .notRegistered && (settings.autoLock != AutoLockSettings() || settings.shortcut != nil || settings.lockKey)
    }
}

/// When Locky locks by itself. Each control writes its auto_lock key in place, so keys a newer Locky knows stay.
private struct AutoLockSection: View {
    let model: AppModel

    private var store: SettingsStore { model.store }

    var body: some View {
        let triggers = store.settings.autoLock
        let idle = SettingsPage.whole(triggers.idleMinutes)
        Section {
            Picker("When inactive", selection: Binding(get: { idle }, set: { minutes in
                store.update { $0.setAutoLock("idle_minutes", minutes.map(LuaValue.int)) }
            })) {
                ForEach(SettingsPage.idleChoices(stored: idle), id: \.minutes) { Text($0.title).tag($0.minutes) }
            }
            Toggle("When the screen saver starts or the display turns off", isOn: Binding(get: { triggers.displaySleep || triggers.screenSaver }, set: { on in
                store.update { SettingsPage.setScreenSaverOrDisplay(on, in: &$0) }
            }))
            Toggle("When the Mac sleeps", isOn: Binding(get: { triggers.systemSleep }, set: { on in
                store.update { $0.setAutoLock("system_sleep", on ? .bool(true) : nil) }
            }))
        } header: {
            Text("Lock Automatically")
        } footer: {
            Text("A video, call, or presentation that keeps the display on pauses the inactivity count. If macOS also asks for your password when the display turns off, you may unlock twice.")
        }
    }
}

/// The lock screen's rows, in two groups: what it says and hides, then how it comes and goes and when its display turns
/// off.
private struct LockScreenSections: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: SettingsStore { model.store }

    var body: some View {
        let displayOff = SettingsPage.whole(store.settings.displayOff)
        Section("Message and Privacy") {
            MessageField(model: model)
            Toggle(isOn: Binding(get: { model.privacy }, set: { on in
                store.update { SettingsPage.setPrivacy(on, base: model.inspection.base["privacy"], in: &$0) }
            })) {
                Text("Hide personal information")
                Text("Your name and picture, this Mac’s name and location, network addresses, and project and task names.")
            }
        }
        Section("Animation and Display") {
            Picker("Lock animation", selection: Binding(get: { store.settings.lockAnimation }, set: { style in
                withAnimation(Motion.rows(reduceMotion)) { store.update { $0.lockAnimation = style } }
            })) {
                Text("None").tag(LockTransition.Style?.none)
                Divider()
                ForEach(LockTransition.Style.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            if let style = store.settings.lockAnimation {
                LockAnimationPreview(model: model, style: style, reduceMotion: reduceMotion)
            }
            // Only while locked and nobody touches the Mac; it turns the display off even when the system's display
            // sleep is Never or another app keeps the display on.
            Picker("Turn the display off", selection: Binding(get: { displayOff }, set: { seconds in
                store.update { $0.displayOff = seconds.map(Double.init) }
            })) {
                ForEach(SettingsPage.displayOffChoices(stored: displayOff), id: \.seconds) { Text($0.title).tag($0.seconds) }
            }
        }
    }
}

/// The chosen lock animation in miniature, on the theme in use, under its pop-up. With Reduce Motion, a still picture and
/// the style Locky uses then.
private struct LockAnimationPreview: View {
    let model: AppModel
    let style: LockTransition.Style
    let reduceMotion: Bool

    var body: some View {
        let theme = model.activeTheme
        VStack(spacing: 6) {
            TransitionPreview(style: style, theme: theme, settings: model.store.settings, config: model.store.config,
                              info: model.inspection.theme(theme), reduceMotion: reduceMotion)
                .frame(width: 260, height: 162.5)
            if reduceMotion {
                Text("Reduce Motion is on, so Locky uses Fade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The lock screen message. It saves on Return and when the field loses focus.
private struct MessageField: View {
    let model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool

    /// settings.json's message, else init.lua's.
    private var saved: String {
        model.store.settings["message"].string ?? model.inspection.base["message"].string ?? ""
    }

    var body: some View {
        LabeledContent("Message") {
            TextField("Message", text: $text, prompt: Text("If found, please call…"))
                .labelsHidden()
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { if !focused { save() } }
                .frame(maxWidth: 320)
        }
        .onAppear { text = saved }
        .onChange(of: saved) { if !focused { text = saved } }
    }

    private func save() {
        let value = SettingsPage.messageText(text)
        text = value
        // Focus that leaves without an edit writes nothing.
        guard value != SettingsPage.messageText(saved) else { return }
        model.store.update { SettingsPage.setMessage(value, base: model.inspection.base["message"], in: &$0) }
    }
}

/// How the lock screen lets people in, and what it does about the ones it should not. Its rows come and go inside
/// `withAnimation`, which animates the whole Form: with `.animation(_:value:)` on the Section, a new row came at once and
/// the footer slid down through it.
private struct UnlockSection: View {
    let model: AppModel
    @State private var hasTouchID = Self.touchIDHardware()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: SettingsStore { model.store }
    /// The wrong password that takes a photo, as the lock reads it; nil is Never.
    private var photoThreshold: Int? { store.settings["intruder_photo"].int.flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        let threshold = photoThreshold
        if hasTouchID {
            Section("Touch ID") {
                Toggle("Unlock with Touch ID", isOn: store.bool("touch_id", default: true))
            }
        }
        Section {
            Picker(selection: Binding(get: { threshold }, set: { value in
                withAnimation(Motion.rows(reduceMotion)) {
                    store.update { $0["intruder_photo"] = value.map(LuaValue.int) ?? .nil }
                }
                // Asks for the camera now, while the person is here: during a lock the camera never asks.
                if value != nil { model.permissions.askForCamera() }
            })) {
                ForEach(SettingsPage.choices("Never", [2, 3, 5, 10], stored: threshold) { "After \(SettingsPage.plural($0, "wrong password"))" },
                        id: \.value) { Text($0.title).tag($0.value) }
            } label: {
                Text("Take a photo")
                if threshold != nil { Text("Photos stay on this Mac for up to 30 days.") }
            }
            if threshold != nil {
                PermissionRow(title: Self.cameraName, reason: Self.cameraReason, state: model.permissions.camera) {
                    model.permissions.grantCamera()
                }
            }
        } header: {
            Text("Wrong Passwords")
        } footer: {
            if store.settings.emergencyExit {
                Text("If something goes wrong on the lock screen, press ⌃⌥⌘Q to switch to the macOS lock screen.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // A lock activates Locky at its start and at each keyboard reclaim: nothing is read then.
            guard !model.locked else { return }
            let touchID = Self.touchIDHardware()
            withAnimation(Motion.rows(reduceMotion)) { hasTouchID = touchID }
        }
    }

    static let cameraName = "Camera"
    static let cameraReason = "Lets Locky take a photo after wrong passwords."

    /// Whether this Mac has Touch ID, also with its lid closed or in lockout: `biometryType` "is set no matter what the
    /// call returns".
    static func touchIDHardware() -> Bool {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID
    }
}

/// Lock with the Touch ID button (settings.json's lock_key). It waits for Accessibility, whose row comes just before it:
/// the switch takes a click the moment Locky has it. One that is on stays free to turn off.
struct LockKeyToggle: View {
    let model: AppModel

    static let title = "Lock with the Touch ID button"
    static let subtitle = "Pressing the Touch ID button shows Locky instead of the macOS lock screen."

    var body: some View {
        let on = model.store.bool("lock_key", default: false)
        Toggle(isOn: on) {
            Text(Self.title)
            Text(Self.subtitle)
        }
        .disabled(!Self.usable(granted: model.permissions.accessibility == .granted, on: on.wrappedValue))
    }

    /// Whether the switch takes a click: with Accessibility, or to turn it off.
    nonisolated static func usable(granted: Bool, on: Bool) -> Bool { granted || on }

    /// Whether this Mac has a Touch ID button: also with its lid closed, as Unlock with Touch ID reads it.
    static func hasButton() -> Bool { UnlockSection.touchIDHardware() }
}

extension SettingsStore {
    /// A switch for an app setting whose default is `fallback`. The default is stored as no key, so
    /// settings.json holds only what differs.
    func bool(_ key: String, default fallback: Bool) -> Binding<Bool> {
        Binding(get: { self.settings[key].bool ?? fallback }, set: { value in
            self.update { $0[key] = value == fallback ? .nil : .bool(value) }
        })
    }
}
