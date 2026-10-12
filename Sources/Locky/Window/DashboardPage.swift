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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    configCard
                    pluginsCard
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
            ThemePreview(theme: id, generation: model.revision, alwaysLive: model.screenshots)
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
        return StatusCard(symbol: "puzzlepiece.extension.fill", tint: missing > 0 ? .orange : .blue, title: "Plugins",
                          value: packs.isEmpty ? "None added" : packs.count == 1 ? "1 plugin" : "\(packs.count) plugins",
                          detail: missing > 0 ? "\(missing) not installed yet" : "\(model.inspection.themes.count) themes, \(model.inspection.widgets.count) widgets") {
            model.section = .plugins
        }
    }

    private var autoLockCard: some View {
        let auto = settings["auto_lock"]
        var triggers: [String] = []
        if let minutes = auto["idle_minutes"].number { triggers.append("after \(Int(minutes)) min idle") }
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
        return StatusCard(symbol: touchID ? "touchid" : "key.fill", tint: .pink, title: "Unlock",
                          value: touchID ? "Touch ID or password" : "Password",
                          detail: safety > 0 ? "Prototype: opens by itself after \(SettingsPage.duration(safety))." : "The safety timer is off.") {
            model.section = .settings
        }
    }

    private var lockScreenCard: some View {
        var notes: [String] = []
        let config = model.inspection.config
        if config["privacy"].bool == true { notes.append("privacy mode") }
        if let message = config["message"].string { notes.append("message “\(message)”") }
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
