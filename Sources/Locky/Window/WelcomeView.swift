import SwiftUI

/// The first launch's three steps: pick a theme, try it, and turn on what locks by itself. Skip or Finish
/// goes to the Dashboard; the menu's Welcome… opens it again.
struct WelcomeView: View {
    @Bindable var model: AppModel
    @State private var step = Step.theme
    @State private var login = LoginItem.status
    @State private var loginError: String?

    enum Step: Int, CaseIterable {
        case theme, tryIt, protect

        var title: String {
            switch self {
            case .theme: "Pick a Theme"
            case .tryIt: "Try It"
            case .protect: "Make It Protect You"
            }
        }

        var subtitle: String {
            switch self {
            case .theme: "This is what your Mac shows while it is locked. You can change it any time on the Themes page."
            case .tryIt: "See the theme full size, or lock the screen for real."
            case .protect: "Locky locks only when you ask, unless you choose when it locks by itself."
            }
        }
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

    private var store: SettingsStore { model.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)").font(.callout).foregroundStyle(.secondary)
                Text(step.title).font(.largeTitle.weight(.semibold))
                Text(step.subtitle).foregroundStyle(.secondary)
            }
            switch step {
            case .theme: themes
            case .tryIt: tryIt
            case .protect: protect
            }
            HStack {
                Button("Skip") { model.section = .dashboard }
                Spacer()
                if step != .theme {
                    Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .theme }
                }
                Button(step == .protect ? "Finish" : "Continue") {
                    if let next = Step(rawValue: step.rawValue + 1) { step = next } else { model.section = .dashboard }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(24)
        .pageWidth()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Steps

    private var themes: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                ForEach(model.inspection.themes.filter { $0.error == nil }) { info in
                    let selected = info.id == model.activeTheme
                    Button { store.update { $0["theme"] = .string(info.id) } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack {
                                Color.secondary.opacity(0.15)
                                if let image = ThemeThumbnails.image(for: info) { Image(nsImage: image).resizable().scaledToFill() }
                            }
                            .aspectRatio(1.6, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1)
                            }
                            Text(info.name).font(.callout.weight(selected ? .semibold : .regular)).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(2)
        }
    }

    private var tryIt: some View {
        let id = model.activeTheme
        return VStack(alignment: .leading, spacing: 14) {
            ThemePreview(theme: id, settings: store.settings, sources: model.inspection.sources, config: store.config,
                         alwaysLive: model.screenshots)
                .aspectRatio(1.6, contentMode: .fit)
                .frame(maxWidth: 480)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            HStack(spacing: 10) {
                Button("Preview") { model.preview(nil) }
                Button { model.lockNow() } label: { Label("Lock Now to Test", systemImage: "lock.fill") }
            }
            .controlSize(.large)
            .fixedSize()
            Text("Touch ID or your Mac's login password unlocks it.").foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var protect: some View {
        let auto = store.settings.autoLock
        return VStack(alignment: .leading, spacing: 12) {
            Text("Lock automatically").font(.headline)
            autoLockToggle("When the Mac is idle for \(Int(auto.idleMinutes ?? 5)) min", auto.idleMinutes != nil) { $0.idleMinutes = $1 ? 5 : nil }
            autoLockToggle("When the display sleeps", auto.displaySleep) { $0.displaySleep = $1 }
            autoLockToggle("Before the Mac sleeps, as when you close the lid", auto.systemSleep) { $0.systemSleep = $1 }
            autoLockToggle("When the screen saver starts", auto.screenSaver) { $0.screenSaver = $1 }
            Text("Start").font(.headline).padding(.top, 8)
            row("Open Locky at login, so it can lock by itself", isOn: Binding(get: { login == .enabled || login == .requiresApproval }, set: { on in
                do {
                    try LoginItem.set(on)
                    loginError = nil
                } catch {
                    loginError = error.localizedDescription
                }
                login = LoginItem.status
            }))
            .disabled({ if case .unavailable = login { return true } else { return false } }())
            if let loginError {
                Label(loginError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if case .unavailable(let message) = login {
                Label(message, systemImage: "info.circle").foregroundStyle(.secondary)
            } else if login == .requiresApproval {
                HStack {
                    Label("Allow Locky in System Settings › Login Items", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Button("Open Login Items") { LoginItem.openSystemSettings() }
                }
            }
            Text("Settings has these, the Lock Now shortcut, and more.").foregroundStyle(.secondary).padding(.top, 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Back from System Settings, where Login Items may have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login = LoginItem.status }
    }

    private func autoLockToggle(_ title: String, _ on: Bool, _ set: @escaping (inout AutoLockSettings, Bool) -> Void) -> some View {
        row(title, isOn: Binding(get: { on }, set: { value in store.update { set(&$0.autoLock, value) } }))
    }

    /// A switch, lined up with the others at the end of its row.
    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
        .frame(maxWidth: 460)
    }
}
