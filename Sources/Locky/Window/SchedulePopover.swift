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
                    slot("Day theme", theme: \.day, starts: \.dayStarts, startsTitle: "Day starts")
                    slot("Night theme", theme: \.night, starts: \.nightStarts, startsTitle: "Night starts")
                case .appearance:
                    themePicker("Light mode theme", \.light)
                    themePicker("Dark mode theme", \.dark)
                }
            }
        }
        .formStyle(.columns)
        // The form at its own width from the leading edge, so its label column stays put when the mode adds or removes
        // rows: centered, the pop-up just used would move sideways under the pointer.
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        // While settings.json has an error nothing saves it, here as everywhere else.
        .disabled(store.problem != nil)
        .padding(20)
        // Room for a time row with a 12-hour clock, whose "7:00 PM" makes the time picker 20 to 30 pt wider. From the
        // leading edge too: a row wider still ends nearer the right edge, and the label column stays put.
        .frame(width: 440, alignment: .leading)
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

    /// A row of a theme and its start. The hidden labels name the row, so VoiceOver tells the day's controls from the night's.
    private func slot(_ title: String, theme: WritableKeyPath<ThemeSchedule, String?>, starts: WritableKeyPath<ThemeSchedule, Int>,
                      startsTitle: String) -> some View {
        LabeledContent(title) {
            HStack {
                themeMenu(title, theme)
                Text("from").foregroundStyle(.secondary)
                DatePicker(startsTitle, selection: Binding(get: {
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
        LabeledContent(title) { themeMenu(title, theme) }
    }

    /// The usual theme, then every theme that loads by name. A slot that names one that does not load still shows it.
    /// One width for every slot, so the times line up whichever themes the slots name: it fits "The usual theme" and
    /// every built-in name; a longer one shortens in the button and shows whole in the menu.
    private func themeMenu(_ title: String, _ theme: WritableKeyPath<ThemeSchedule, String?>) -> some View {
        let chosen = schedule?[keyPath: theme]
        return Picker(title, selection: Binding(get: { chosen }, set: { value in update { $0[keyPath: theme] = value } })) {
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
