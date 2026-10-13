import SwiftUI

/// The theme schedule, from the Themes toolbar: a different theme by time of day, or with Light and Dark mode. Each
/// change saves at once, so the popover has no Done: it closes when the person clicks outside it.
struct SchedulePopover: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: SettingsStore { model.store }
    private var schedule: ThemeSchedule? { store.settings.schedule }

    var body: some View {
        Form {
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
        }
        .formStyle(.columns)
        // While settings.json has an error nothing saves it, here as everywhere else.
        .disabled(store.problem != nil)
        .padding(20)
        .frame(width: 420)
        .animation(Motion.rows(reduceMotion), value: schedule?.mode)
    }

    /// Turning a schedule on fills both of its slots with the theme in use. Switching modes keeps the other mode's themes.
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

    /// The usual theme, then every theme that loads by name. A slot that names one that does not load still shows it.
    /// One width for every slot, so the times line up whichever themes the slots name: it fits "The usual theme" and
    /// every built-in name; a longer one shortens in the button and shows whole in the menu.
    private func themeMenu(_ theme: WritableKeyPath<ThemeSchedule, String?>) -> some View {
        let chosen = schedule?[keyPath: theme]
        return Picker("Theme", selection: Binding(get: { chosen }, set: { value in update { $0[keyPath: theme] = value } })) {
            Text("The usual theme").tag(String?.none)
            ForEach(model.inspection.themesByName.filter { $0.error == nil || $0.id == chosen }) { Text($0.name).tag(String?.some($0.id)) }
        }
        .labelsHidden()
        .frame(width: 150, alignment: .leading)
    }

    private func update(_ change: (inout ThemeSchedule) -> Void) {
        guard var schedule else { return }
        change(&schedule)
        store.update { $0.schedule = schedule }
    }
}
