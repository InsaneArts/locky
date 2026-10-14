import AppKit
import Carbon
import SwiftUI

/// A settings row for a shortcut: the label, and a button that shows the shortcut. A click records a new one: the
/// next key with ⌘, ⌃, or ⌥ (or an F-key) becomes the shortcut, Esc cancels, and Delete clears it.
/// `onRecordingChange` says when recording starts and ends, so the caller can free the global shortcut, which
/// would otherwise take the key before the recorder sees it.
struct ShortcutRecorder<Label: View>: View {
    @Binding private var shortcut: Shortcut?
    private let onRecordingChange: (Bool) -> Void
    private let label: Label
    @State private var recording = false
    /// A key that cannot be a shortcut came while recording: the rule shows under the label until recording stops.
    @State private var rejected = false
    @State private var monitor: Any?
    /// A click away from the button ends recording; a click on it is the button's own.
    @State private var hovering = false
    @Environment(\.appearsActive) private var appearsActive

    init(shortcut: Binding<Shortcut?>, onRecordingChange: @escaping (Bool) -> Void = { _ in }, @ViewBuilder label: () -> Label) {
        _shortcut = shortcut
        self.onRecordingChange = onRecordingChange
        self.label = label()
    }

    var body: some View {
        LabeledContent {
            let button = Button(recording ? "Press Shortcut…" : shortcut?.display ?? "Record Shortcut") {
                recording ? stop() : start()
            }
            // One container for both looks, so the pointer stays tracked when the button changes.
            HStack(spacing: 0) {
                if recording { button.buttonStyle(.borderedProminent) } else { button }
            }
            .onHover { hovering = $0 }
            .help("Click, then press the shortcut. Delete removes it. Esc cancels.")
        } label: {
            label
            if rejected {
                // A key press never animates: the rule comes on the beep's frame.
                Text("Use ⌘ or ⌃ with a key, or an F-key.")
                    .transaction { $0.animation = nil }
            }
        }
        // In another window or app, the recording would wait for a key that never comes, with the shortcut paused.
        .onChange(of: appearsActive) { if !appearsActive { stop() } }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
            guard event.type == .keyDown else {
                if !hovering { stop() }
                return event
            }
            switch RecordingOutcome(keyCode: event.keyCode, modifierFlags: event.modifierFlags) {
            case .cancel: stop()
            case .clear: shortcut = nil; stop()
            case .record(let recorded): shortcut = recorded; stop()
            case .reject:
                NSSound.beep()
                rejected = true
            }
            // Every key stays here while recording, so ⌘W or ⌘Q records instead of closing or quitting.
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        rejected = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onRecordingChange(false)
    }
}

extension ShortcutRecorder where Label == Text {
    init(_ title: some StringProtocol, shortcut: Binding<Shortcut?>, onRecordingChange: @escaping (Bool) -> Void = { _ in }) {
        self.init(shortcut: shortcut, onRecordingChange: onRecordingChange) { Text(title) }
    }
}

/// What a key does while a ShortcutRecorder records.
enum RecordingOutcome: Equatable {
    case cancel, clear, record(Shortcut), reject

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        let modifiers = Shortcut.Modifiers(modifierFlags)
        let shortcut = Shortcut(keyCode: keyCode, modifiers: modifiers)
        if modifiers.isEmpty, Int(keyCode) == kVK_Escape {
            self = .cancel
        } else if modifiers.isEmpty, [kVK_Delete, kVK_ForwardDelete].contains(Int(keyCode)) {
            self = .clear
        } else {
            self = shortcut.isValid ? .record(shortcut) : .reject
        }
    }
}
