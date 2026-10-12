import AppKit
import SwiftUI

/// The app's settings. Each change saves to settings.json at once. Settings Lua also reads (the safety
/// timer, the clock, privacy, the message) show init.lua's value until changed here, then offer a Reset.
struct SettingsPage: View {
    @Bindable var model: AppModel

    private var store: SettingsStore { model.store }

    var body: some View {
        Form {
            if let problem = store.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Button("Move the Broken File Aside and Start Over") { try? store.resetBrokenFile() }
                } footer: {
                    Text("Locky does not change settings.json while it has an error. Fix it in an editor, or start over.")
                }
            }
            GeneralSettings(model: model)
            autoLock
            unlock
            lockScreen
            ScheduleSettings(model: model)
            power
            security
            Section("Plugins") {
                Toggle("Check for plugin updates once a day", isOn: store.bool("update_check", default: true))
            }
        }
        .formStyle(.grouped)
        .disabled(store.problem != nil)
    }

    // MARK: Sections

    private var autoLock: some View {
        Section {
            let idle = store.settings["auto_lock"]["idle_minutes"].number
            Toggle(isOn: Binding(get: { idle != nil }, set: { setAutoLock("idle_minutes", $0 ? .int(5) : nil) })) {
                HStack {
                    Text("After the Mac is idle for")
                    Picker("Minutes", selection: Binding(get: { Int(idle ?? 5) }, set: { setAutoLock("idle_minutes", .int($0)) })) {
                        ForEach([1, 2, 3, 5, 10, 15, 20, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(idle == nil)
                }
            }
            Toggle("When the display sleeps", isOn: autoLockBinding("display_sleep"))
            Toggle("Before the Mac sleeps", isOn: autoLockBinding("system_sleep"))
            Toggle("When the screen saver starts", isOn: autoLockBinding("screen_saver"))
        } header: {
            Text("Lock Automatically")
        } footer: {
            Text("Idle time does not count while a video, a call, or a presentation keeps the display awake. If macOS also asks for your password after sleep, you unlock twice.")
        }
    }

    private var unlock: some View {
        Section {
            Toggle("Unlock with Touch ID", isOn: store.bool("touch_id", default: true))
            LabeledContent {
                Picker("Safety timer", selection: luaNumber("auto_unlock", fallback: 60)) {
                    ForEach(safetyChoices, id: \.self) { seconds in
                        Text(seconds == 0 ? "Off" : Self.duration(seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .fixedSize()
            } label: {
                Text("Safety timer")
                Text("Prototype: the lock opens by itself after this time.")
                LuaNote(model: model, key: "auto_unlock") { $0.number.map { $0 == 0 ? "off" : Self.duration($0) } }
            }
            Toggle(isOn: store.bool("emergency_exit", default: true)) {
                Text("Quit with ⌃⌥⌘Q")
                Text("Ends the lock at once: for when something goes wrong.")
            }
            if (effective("auto_unlock").number ?? 60) == 0, store.settings["emergency_exit"].bool == false {
                Label("With both off, a bug in Locky could keep you locked out until you restart the Mac.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Unlock")
        }
    }

    private var lockScreen: some View {
        Section("Lock Screen") {
            MessageField(model: model)
            LabeledContent {
                Picker("Clock", selection: Binding(get: { effective("hour24").bool }, set: { value in
                    store.update { $0["hour24"] = value.map(LuaValue.bool) ?? .nil }
                })) {
                    Text("Like the system").tag(Bool?.none)
                    Text("12-hour").tag(Bool?.some(false))
                    Text("24-hour").tag(Bool?.some(true))
                }
                .labelsHidden()
                .fixedSize()
            } label: {
                Text("Clock")
                LuaNote(model: model, key: "hour24") { $0.bool.map { $0 ? "24-hour" : "12-hour" } ?? "like the system" }
            }
            Toggle(isOn: Binding(get: { effective("privacy").bool ?? false }, set: { value in store.update { $0["privacy"] = .bool(value) } })) {
                Text("Privacy mode")
                Text("Hides agent titles and workspaces, your name and picture, and the computer's name.")
                LuaNote(model: model, key: "privacy") { $0.bool == true ? "on" : "off" }
            }
        }
    }

    private var power: some View {
        Section("Power") {
            Toggle(isOn: store.bool("battery_saver", default: false)) {
                Text("Battery saver")
                Text("On battery or in Low Power Mode, backgrounds stop moving and animations turn off.")
            }
            LabeledContent {
                Picker("Turn the display off", selection: Binding(get: { store.settings["display_off"].int ?? 0 }, set: { value in
                    store.update { $0["display_off"] = value == 0 ? .nil : .int(value) }
                })) {
                    Text("Never").tag(0)
                    ForEach([10, 15, 30, 60, 120, 300], id: \.self) { Text(Self.duration(Double($0))).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            } label: {
                Text("Turn the display off after")
                Text("While locked, when nobody touches the Mac.")
            }
        }
    }

    private var security: some View {
        Section {
            LabeledContent {
                Picker("Photo", selection: Binding(get: { store.settings["intruder_photo"].int ?? 0 }, set: { value in
                    store.update { $0["intruder_photo"] = value == 0 ? .nil : .int(value) }
                    // Ask now: during a lock, the camera never asks.
                    if value > 0, CameraAccess.status == .notDetermined { Task { _ = await CameraAccess.request() } }
                })) {
                    Text("Off").tag(0)
                    ForEach([2, 3, 5, 10], id: \.self) { Text("After \($0) wrong passwords").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            } label: {
                Text("Take a photo")
                Text("With the camera, once per lock. The Dashboard shows the photos after you unlock.")
            }
            if store.settings["intruder_photo"].int != nil { CameraStatus() }
        } header: {
            Text("Security")
        } footer: {
            Text("Photos stay on this Mac, in ~/Library/Application Support/Locky/Intruders.")
        }
    }

    // MARK: Helpers

    private var safetyChoices: [Double] {
        let choices: [Double] = [0, 30, 60, 120, 300, 600]
        let current = effective("auto_unlock").number ?? 60
        return choices.contains(current) ? choices : (choices + [current]).sorted()
    }

    /// settings.json's value, else init.lua's (or the default).
    private func effective(_ key: String) -> LuaValue {
        store.settings[key].isNil ? model.inspection.base[key] : store.settings[key]
    }

    private func luaNumber(_ key: String, fallback: Double) -> Binding<Double> {
        Binding(get: { effective(key).number ?? fallback }, set: { value in store.update { $0[key] = .double(value) } })
    }

    private func autoLockBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { store.settings["auto_lock"][key].bool ?? false }, set: { setAutoLock(key, $0 ? .bool(true) : nil) })
    }

    private func setAutoLock(_ key: String, _ value: LuaValue?) {
        store.update { settings in
            var table = settings["auto_lock"].table ?? [:]
            table[key] = value
            settings["auto_lock"] = table.isEmpty ? .nil : .table(table)
        }
    }

    static func duration(_ seconds: Double) -> String {
        seconds < 60 || seconds.truncatingRemainder(dividingBy: 60) != 0 ? "\(Int(seconds)) s" : "\(Int(seconds / 60)) min"
    }
}

/// Under a setting Lua also reads: where its value comes from, and a Reset to init.lua's.
private struct LuaNote: View {
    let model: AppModel
    let key: String
    let describe: (LuaValue) -> String?

    var body: some View {
        if !model.store.settings[key].isNil {
            HStack(spacing: 4) {
                Text("Set here; init.lua or the default says \(describe(model.inspection.base[key]) ?? "nothing").")
                Button("Reset") { model.store.update { $0[key] = .nil } }
                    .buttonStyle(.link)
            }
        }
    }
}

/// The lock screen message. It saves when editing ends.
private struct MessageField: View {
    let model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool

    private var saved: String {
        model.store.settings["message"].string ?? model.inspection.base["message"].string ?? ""
    }

    var body: some View {
        LabeledContent {
            TextField("Message", text: $text, prompt: Text("If found, please call …"))
                .labelsHidden()
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { if !focused { save() } }
                .frame(maxWidth: 320)
        } label: {
            Text("Message")
            Text("Shown under the password field.")
            LuaNote(model: model, key: "message") { $0.string.map { "“\($0)”" } }
        }
        .onAppear { text = saved }
        .onChange(of: saved) { if !focused { text = saved } }
    }

    private func save() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != saved else { return }
        model.store.update { $0["message"] = value.isEmpty ? .nil : .string(String(value.prefix(200))) }
    }
}

/// Launch at login and the Lock Now shortcut.
private struct GeneralSettings: View {
    let model: AppModel
    @State private var login = LoginItem.status
    @State private var loginError: String?

    var body: some View {
        Section("General") {
            Toggle(isOn: Binding(get: { login == .enabled || login == .requiresApproval }, set: { on in
                do {
                    try LoginItem.set(on)
                    loginError = nil
                } catch {
                    loginError = error.localizedDescription
                }
                login = LoginItem.status
            })) {
                Text("Open Locky at login")
                Text("Locky has to run to lock by itself and to answer the shortcut.")
            }
            .disabled({ if case .unavailable = login { return true } else { return false } }())
            switch login {
            case .requiresApproval:
                HStack {
                    Label("Allow Locky in System Settings › Login Items", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Spacer()
                    Button("Open Login Items") { LoginItem.openSystemSettings() }
                }
            case .unavailable(let message):
                Label(message, systemImage: "info.circle").foregroundStyle(.secondary)
            default:
                EmptyView()
            }
            if let loginError {
                Label(loginError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            ShortcutRecorder(shortcut: Binding(get: { model.store.settings.shortcut }, set: { shortcut in
                model.store.update { $0.shortcut = shortcut }
            }), onRecordingChange: model.recordingShortcut) {
                Text("Lock Now shortcut")
                Text("Works in every app. Click to record; Delete clears it.")
            }
            if let problem = model.shortcutProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login = LoginItem.status }
    }
}

/// A different theme by time of day, or with Light and Dark mode.
private struct ScheduleSettings: View {
    let model: AppModel

    private var store: SettingsStore { model.store }
    private var schedule: ThemeSchedule? { store.settings.schedule }

    var body: some View {
        Section {
            Picker("Change the theme", selection: Binding(get: { schedule?.mode }, set: { setMode($0) })) {
                Text("Never").tag(ThemeSchedule.Mode?.none)
                Text("By time of day").tag(ThemeSchedule.Mode?.some(.time))
                Text("With Light and Dark mode").tag(ThemeSchedule.Mode?.some(.appearance))
            }
            if let schedule {
                switch schedule.mode {
                case .time:
                    slot("Day theme", theme: \.day, starts: \.dayStarts)
                    slot("Night theme", theme: \.night, starts: \.nightStarts)
                case .appearance:
                    themePicker("Light mode theme", \.light)
                    themePicker("Dark mode theme", \.dark)
                }
            }
        } header: {
            Text("Theme Schedule")
        } footer: {
            if schedule != nil {
                Text("The schedule picks each lock's theme. Now: \(model.inspection.theme(model.activeTheme)?.name ?? model.activeTheme).")
            }
        }
    }

    private func setMode(_ mode: ThemeSchedule.Mode?) {
        let current = model.activeTheme
        store.update { settings in
            guard let mode else {
                settings.schedule = nil
                return
            }
            var schedule = settings.schedule ?? ThemeSchedule(mode: mode)
            schedule.mode = mode
            if mode == .time {
                schedule.day = schedule.day ?? current
                schedule.night = schedule.night ?? current
            } else {
                schedule.light = schedule.light ?? current
                schedule.dark = schedule.dark ?? current
            }
            settings.schedule = schedule
        }
    }

    private func slot(_ title: String, theme: WritableKeyPath<ThemeSchedule, String?>, starts: WritableKeyPath<ThemeSchedule, Int>) -> some View {
        LabeledContent(title) {
            HStack {
                themeMenu(theme)
                Text("from").foregroundStyle(.secondary)
                DatePicker("Starts", selection: Binding(get: {
                    let minutes = schedule?[keyPath: starts] ?? 0
                    return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
                }, set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    update { $0[keyPath: starts] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) }
                }), displayedComponents: .hourAndMinute)
                .labelsHidden()
            }
        }
    }

    private func themePicker(_ title: String, _ theme: WritableKeyPath<ThemeSchedule, String?>) -> some View {
        LabeledContent(title) { themeMenu(theme) }
    }

    private func themeMenu(_ theme: WritableKeyPath<ThemeSchedule, String?>) -> some View {
        Picker("Theme", selection: Binding(get: { schedule?[keyPath: theme] }, set: { value in update { $0[keyPath: theme] = value } })) {
            Text("The usual theme").tag(String?.none)
            ForEach(model.inspection.themes) { Text($0.name).tag(String?.some($0.id)) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func update(_ change: (inout ThemeSchedule) -> Void) {
        guard var schedule else { return }
        change(&schedule)
        store.update { $0.schedule = schedule }
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

/// Whether Locky may use the camera, with the way to change it.
private struct CameraStatus: View {
    @State private var status = CameraAccess.status

    var body: some View {
        HStack {
            switch status {
            case .authorized:
                Label("Locky may use the camera", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .notDetermined:
                Label("Locky needs your permission to use the camera", systemImage: "camera").foregroundStyle(.secondary)
                Spacer()
                Button("Allow…") {
                    Task {
                        _ = await CameraAccess.request()
                        status = CameraAccess.status
                    }
                }
            default:
                Label("Locky may not use the camera, so it takes no photo", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Spacer()
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            }
        }
        .onAppear { status = CameraAccess.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in status = CameraAccess.status }
    }
}
