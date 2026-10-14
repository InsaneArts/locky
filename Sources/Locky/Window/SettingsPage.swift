import AppKit
import AVFoundation
import LocalAuthentication
import SwiftUI

/// Settings › General: when the Mac locks, how it unlocks, and what the lock screen says. Each change saves to
/// settings.json at once. A row Lua also reads stores no key while it shows init.lua's value, so the row is its own reset;
/// Hide personal information is the exception, and stores on all the same.
struct SettingsPage: View {
    let model: AppModel
    /// The intruder photos, newest first. They are read when the pane is built, when a lock ends, and after each config
    /// read. The window opens after the lock that took them, so they are on its first frame; a photo still saving when
    /// the lock ended comes with the next config read.
    @State private var photos: [(url: URL, date: Date)]

    init(model: AppModel) {
        self.model = model
        _photos = State(initialValue: Self.photos(for: model))
    }

    private var store: SettingsStore { model.store }

    var body: some View {
        // The settings.json error and Photos groups come and go at once: the grouped Form cannot slide the rows below a
        // whole group, and cross-fades the whole pane instead.
        Form {
            if let problem = store.problem {
                Section {
                    WarningLabel(problem)
                        .textSelection(.enabled)
                    Button("Restore Last Good Settings") { try? store.resetBrokenFile() }
                } footer: {
                    Text("Locky keeps using the last settings that worked. Restoring moves the broken file aside.")
                }
            }
            // While the file has an error, everything but the way out of it waits.
            Group {
                if !photos.isEmpty {
                    PhotosSection(photos: photos, delete: delete, deleteAll: deleteAll)
                }
                StartSection(model: model)
                AutoLockSection(model: model)
                LockScreenSection(model: model)
                UnlockSection(model: model)
            }
            .disabled(store.problem != nil)
        }
        .formStyle(.grouped)
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

    /// The lock screen message as the lock reads it: trimmed, 200 characters at most.
    nonisolated static func messageText(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
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

/// Runs `action` when a lock ends, also while the Settings window is closed. `model.locked` is read here and not in the
/// page's body, so a lock's start does not build the page again: building UnlockSection reads the Touch ID, Accessibility,
/// and camera states, and during a lock the main thread runs the guard's heartbeat.
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
                        Text("This can't be undone.")
                    }
            }
        } footer: {
            Text("Locky took these when someone typed wrong passwords.")
        }
    }
}

/// Open at login and the Lock Now shortcut: what lets Locky lock at all.
private struct StartSection: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            OpenAtLoginToggle(model: model, subtitle: waitsOnLocky ? "Auto-lock and the shortcut work only while Locky is open." : nil)
            ShortcutRecorder("Lock Now shortcut", shortcut: Binding(get: { model.store.settings.shortcut }, set: { shortcut in
                model.store.update { $0.shortcut = shortcut }
            }), onRecordingChange: model.recordingShortcut)
            if let problem = model.shortcutProblem {
                WarningLabel(problem)
            }
        }
        .animation(Motion.rows(reduceMotion), value: model.loginItem)
    }

    /// Locky does not open at login, and auto-lock or the shortcut needs it running.
    private var waitsOnLocky: Bool {
        let settings = model.store.settings
        return model.loginItem == .notRegistered && (settings.autoLock != AutoLockSettings() || settings.shortcut != nil)
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

/// What the lock screen says and hides, and when its display turns off.
private struct LockScreenSection: View {
    let model: AppModel

    private var store: SettingsStore { model.store }

    /// settings.json's value, else init.lua's: only true hides, as Lua reads it.
    private var privacy: Bool {
        (store.settings["privacy"].isNil ? model.inspection.base["privacy"] : store.settings["privacy"]).bool == true
    }

    var body: some View {
        let displayOff = SettingsPage.whole(store.settings.displayOff)
        Section("Lock Screen") {
            MessageField(model: model)
            Toggle(isOn: Binding(get: { privacy }, set: { on in
                store.update { SettingsPage.setPrivacy(on, base: model.inspection.base["privacy"], in: &$0) }
            })) {
                Text("Hide personal information")
                Text("Your name and picture, this Mac's name and location, network addresses, and what you are working on.")
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
    @State private var trusted = AXIsProcessTrusted()
    @State private var cameraStatus = CameraAccess.status
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: SettingsStore { model.store }
    /// The wrong password that takes a photo, as the lock reads it; nil is Never.
    private var photoThreshold: Int? { store.settings["intruder_photo"].int.flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        let threshold = photoThreshold
        Section {
            if hasTouchID {
                Toggle("Unlock with Touch ID", isOn: store.bool("touch_id", default: true))
            }
            Picker(selection: Binding(get: { threshold }, set: { value in
                withAnimation(Motion.rows(reduceMotion)) {
                    store.update { $0["intruder_photo"] = value.map(LuaValue.int) ?? .nil }
                }
                if value != nil { askForCamera() }
            })) {
                ForEach(SettingsPage.choices("Never", [2, 3, 5, 10], stored: threshold) { "After \(SettingsPage.plural($0, "wrong password"))" },
                        id: \.value) { Text($0.title).tag($0.value) }
            } label: {
                Text("Take a photo")
                if threshold != nil { Text("Photos stay on this Mac for up to 30 days.") }
            }
            if threshold != nil {
                CameraStatus(status: cameraStatus, ask: askForCamera)
            }
            KeyboardAccess(trusted: $trusted)
        } header: {
            Text("Unlock")
        } footer: {
            if store.settings["emergency_exit"].bool != false {
                Text("If something goes wrong on the lock screen, press ⌃⌥⌘Q to switch to the macOS lock screen.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // A lock activates Locky at its start and at each keyboard reclaim: nothing is read then.
            guard !model.locked else { return }
            let touchID = Self.touchIDHardware(), keyboard = AXIsProcessTrusted(), camera = CameraAccess.status
            withAnimation(Motion.rows(reduceMotion)) {
                hasTouchID = touchID
                trusted = keyboard
                cameraStatus = camera
            }
        }
    }

    /// Whether this Mac has Touch ID, also with its lid closed or in lockout: `biometryType` "is set no matter what the
    /// call returns".
    static func touchIDHardware() -> Bool {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID
    }

    /// Asks for the camera now, while the person is here: during a lock the camera never asks.
    private func askForCamera() {
        guard CameraAccess.status == .notDetermined else { return }
        let animation = Motion.rows(reduceMotion)
        Task {
            _ = await CameraAccess.request()
            let status = CameraAccess.status
            withAnimation(animation) { cameraStatus = status }
        }
    }
}

/// The camera, while Locky may not use it: a way to ask, or the way to System Settings. Nothing once it may.
private struct CameraStatus: View {
    let status: AVAuthorizationStatus
    let ask: () -> Void

    var body: some View {
        switch status {
        case .authorized:
            EmptyView()
        case .notDetermined:
            LabeledContent("Needs camera access.") {
                Button("Allow…", action: ask)
            }
        default:
            LabeledContent {
                Button("Open Camera Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            } label: {
                WarningLabel("Camera access is off.")
            }
        }
    }
}

/// Accessibility, which lets the lock screen keep the keyboard when another app takes it, while Locky does not have it.
/// Nothing once it does.
private struct KeyboardAccess: View {
    @Binding var trusted: Bool

    var body: some View {
        if !trusted {
            LabeledContent {
                Button("Allow…") {
                    // Shows macOS's prompt, which leads to Privacy & Security › Accessibility.
                    trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                }
            } label: {
                Text("Keep the keyboard on the lock screen")
                Text("Needs Accessibility access.")
            }
        }
    }
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
