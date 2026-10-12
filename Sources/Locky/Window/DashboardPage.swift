import SwiftUI

/// The overview: the theme a lock uses now, live, with Lock Now; then one card per area that needs
/// attention or is worth knowing, each opening its page.
struct DashboardPage: View {
    @Bindable var model: AppModel

    private var settings: Settings { model.store.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                // Screenshots never show someone's photo.
                if !model.screenshots { IntruderPhotos(revision: model.revision) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    configCard
                    pluginsCard
                    startCard
                    autoLockCard
                    unlockCard
                    lockScreenCard
                }
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: The theme

    private var hero: some View {
        let id = model.activeTheme
        let info = model.inspection.theme(id)
        return HStack(alignment: .center, spacing: 24) {
            ThemePreview(theme: id, settings: model.store.settings, sources: model.inspection.sources, alwaysLive: model.screenshots)
                .aspectRatio(1.6, contentMode: .fit)
                .frame(width: 400)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("Locks with").font(.callout).foregroundStyle(.secondary)
                Text(info?.name ?? id).font(.largeTitle.weight(.semibold))
                if let description = info?.description {
                    Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let schedule = settings.schedule {
                    Label(Self.describe(schedule, model.inspection), systemImage: "clock.arrow.2.circlepath")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button { model.lockNow() } label: {
                        Label("Lock Now", systemImage: "lock.fill").padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button("Preview") { model.preview(nil) }
                        .controlSize(.large)
                    Button("Themes…") { model.section = .themes }
                        .controlSize(.large)
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Cards

    private var configCard: some View {
        let problems = model.inspection.problems
        return StatusCard(symbol: problems.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                          tint: problems.isEmpty ? .green : .orange, title: "Config",
                          value: problems.isEmpty ? "No problems" : problems.count == 1 ? "1 problem" : "\(problems.count) problems",
                          detail: problems.first.map { LuaError($0).summary } ?? "init.lua, plugins, and settings.json load cleanly.") {
            model.section = .config
        }
    }

    private var pluginsCard: some View {
        let packs = model.inspection.packs
        let missing = packs.filter { !$0.installed }.count
        let updates = model.available.count
        let detail = missing > 0 ? "\(missing) not installed yet"
            : updates > 0 ? (updates == 1 ? "1 update available" : "\(updates) updates available")
            : "\(model.inspection.themes.count) themes, \(model.inspection.widgets.count) widgets"
        return StatusCard(symbol: "puzzlepiece.extension.fill", tint: missing > 0 ? .orange : .blue, title: "Plugins",
                          value: packs.isEmpty ? "None added" : packs.count == 1 ? "1 plugin" : "\(packs.count) plugins", detail: detail) {
            model.section = .plugins
        }
    }

    private var startCard: some View {
        let login = LoginItem.status
        let shortcut = settings.shortcut.map { "Lock Now: \($0.display)" } ?? "No Lock Now shortcut"
        let value: String
        switch login {
        case .enabled: value = "Opens at login"
        case .requiresApproval: value = "Login item needs approval"
        case .notRegistered: value = "Not at login"
        case .unavailable: value = "Login item unavailable"
        }
        return StatusCard(symbol: "power", tint: login == .enabled ? .green : .orange, title: "Start and Shortcut", value: value,
                          detail: login == .enabled ? shortcut : "Locky locks by itself only while it runs. \(shortcut).") {
            model.section = .settings
        }
    }

    private var autoLockCard: some View {
        let auto = settings["auto_lock"]
        var triggers: [String] = []
        if let minutes = auto["idle_minutes"].number, minutes.isFinite { triggers.append("after \(Int(min(max(minutes, 1), 1440))) min idle") }
        if auto["display_sleep"].bool == true { triggers.append("display sleep") }
        if auto["system_sleep"].bool == true { triggers.append("Mac sleep") }
        if auto["screen_saver"].bool == true { triggers.append("screen saver") }
        return StatusCard(symbol: "timer", tint: triggers.isEmpty ? .gray : .purple, title: "Lock Automatically",
                          value: triggers.isEmpty ? "Off" : "On",
                          detail: triggers.isEmpty ? "Locky locks only when you ask." : triggers.joined(separator: ", ").capitalizedFirst) {
            model.section = .settings
        }
    }

    private var unlockCard: some View {
        let touchID = settings["touch_id"].bool != false
        let safety = (settings["auto_unlock"].isNil ? model.inspection.base["auto_unlock"] : settings["auto_unlock"]).number ?? 60
        let duration = SettingsPage.duration(safety)
        return StatusCard(symbol: touchID ? "touchid" : "key.fill", tint: .pink, title: "Unlock",
                          value: touchID ? "Touch ID or password" : "Password",
                          detail: duration != "Off" ? "Prototype: opens by itself after \(duration)." : "The safety timer is off.") {
            model.section = .settings
        }
    }

    private var lockScreenCard: some View {
        var notes: [String] = []
        let config = model.inspection.config
        if config["privacy"].bool == true { notes.append("privacy mode") }
        // A cleared message is an empty one that overrides init.lua's: no message, no change to list.
        if let message = config["message"].string?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            notes.append("message “\(message)”")
        }
        if let hour24 = config["hour24"].bool { notes.append(hour24 ? "24-hour clock" : "12-hour clock") }
        return StatusCard(symbol: "rectangle.on.rectangle", tint: .teal, title: "Lock Screen",
                          value: notes.isEmpty ? "As the theme has it" : notes.count == 1 ? "1 change" : "\(notes.count) changes",
                          detail: notes.isEmpty ? "No message, privacy mode off." : notes.joined(separator: ", ").capitalizedFirst) {
            model.section = .settings
        }
    }

    static func describe(_ schedule: ThemeSchedule, _ inspection: Inspection) -> String {
        let name = { (id: String?) in id.flatMap { inspection.theme($0)?.name ?? $0 } ?? "the usual theme" }
        switch schedule.mode {
        case .time:
            return "Day: \(name(schedule.day)) from \(ThemeSchedule.clock(schedule.dayStarts)) · Night: \(name(schedule.night)) from \(ThemeSchedule.clock(schedule.nightStarts))"
        case .appearance:
            return "Light: \(name(schedule.light)) · Dark: \(name(schedule.dark))"
        }
    }
}

/// One area at a glance. The whole card opens its page.
struct StatusCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    let detail: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.callout).foregroundStyle(.secondary)
                    Text(value).font(.title3.weight(.semibold)).lineLimit(1)
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension String {
    /// "after 5 min idle" → "After 5 min idle".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Photos the camera took after too many wrong passwords, newest first. Shown only when there are some.
private struct IntruderPhotos: View {
    let revision: Int
    @State private var photos: [(url: URL, date: Date)] = []
    @State private var confirmingDelete = false

    var body: some View {
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(photos.count == 1 ? "Someone typed wrong passwords" : "Someone typed wrong passwords \(photos.count) times",
                          systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Delete All", role: .destructive) { confirmingDelete = true }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(photos, id: \.url) { photo in
                            VStack(alignment: .leading, spacing: 4) {
                                Button { NSWorkspace.shared.open(photo.url) } label: {
                                    AsyncThumbnail(url: photo.url)
                                        .frame(width: 160, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Open in Preview")
                                HStack {
                                    Text(photo.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button { delete(photo.url) } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                        .help("Delete this photo")
                                }
                                .frame(width: 160)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .padding(16)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .confirmationDialog("Delete every photo?", isPresented: $confirmingDelete) {
                Button("Delete All", role: .destructive) {
                    try? IntruderLog().deleteAll()
                    load()
                }
            }
        }
        Color.clear.frame(height: 0)
            .task(id: revision) { load() }
    }

    private func load() {
        photos = IntruderLog().photos()
    }

    private func delete(_ url: URL) {
        try? IntruderLog().delete(url)
        load()
    }
}

/// A photo file as a thumbnail, loaded off the main thread.
private struct AsyncThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            if let image { Image(nsImage: image).resizable().scaledToFill() }
        }
        .task(id: url) {
            let url = url
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            image = data.flatMap(NSImage.init(data:))
        }
    }
}
