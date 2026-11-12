import Accessibility
import AppKit
import Collaboration
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import OpenDirectory
import SwiftUI

enum Auth {
    /// Checks the login password with Open Directory, the same check the login window makes.
    static func verify(_ password: String) async -> Bool {
        await Task.detached {
            do {
                let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
                let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
                try record.verifyPassword(password)
                return true
            } catch {
                return false
            }
        }.value
    }

    struct User {
        var name: String
        var login: String
        var host: String
        var picture: NSImage?
    }

    /// The login user. In privacy mode: no name or picture, and "user@mac" for the terminal prompt.
    static func user(privacy: Bool) -> User {
        if privacy { return User(name: "", login: "user", host: "mac", picture: nil) }
        let identity = CBIdentity(name: NSUserName(), authority: CBIdentityAuthority.default())
        let host = (SystemInfo.hostname()["host"].string ?? "mac").replacingOccurrences(of: ".local", with: "")
        return User(name: identity?.fullName ?? NSUserName(), login: NSUserName(), host: host, picture: identity?.image)
    }
}

/// What is typed, shared by every version of the password field: the theme can restyle the field (or a
/// display change rebuild it) without losing it.
@MainActor @Observable
final class AuthModel {
    var password = "" {
        didSet { if !password.isEmpty { wrongShown = false } }
    }
    /// Bumped to put the keyboard focus back in the field.
    var focusRequest = 0
    /// Caps Lock is on: the field shows ⇪. The lock sets it from each modifier change it sees.
    var capsLock = false
    /// Wrong passwords in this lock, and whether a check runs. Here and not in the field, so a rebuilt field (a
    /// display added, the power changed) keeps them.
    var wrong = 0
    var checking = false
    /// The last check was a wrong password, and nothing has been typed since: the field says "Wrong Password".
    private(set) var wrongShown = false
    /// One check has run for `slowAfter`: the lock names the way out, since the field stays disabled until it ends.
    private(set) var slowCheck = false
    /// Called when `slowCheck` turns true.
    @ObservationIgnored var onSlowCheck: () -> Void = {}
    /// Whole seconds left in the wait before the next try (0: none). Waits outlast the lock: see PasswordAttempts.
    private(set) var waitLeft = 0
    /// A wait has disabled the field in this lock: one after its wrong passwords, or one that a count carried over from
    /// an earlier lock (after ⌃⌥⌘Q, or a relaunch) starts, at once or at this lock's first wrong password.
    private(set) var waited = false
    /// The user the field shows; privacy mode can change it while the field stays.
    var user = Auth.User(name: "", login: "user", host: "mac", picture: nil)
    /// Where wrong passwords count across locks and relaunches. nil (the theme editor's preview) counts in memory.
    private let defaults: UserDefaults?
    private let slowAfter: Duration
    private var attempts: PasswordAttempts
    private var waiting: Task<Void, Never>?
    private var slowTimer: Task<Void, Never>?

    init(defaults: UserDefaults? = nil, slowAfter: Duration = .seconds(5)) {
        self.defaults = defaults
        self.slowAfter = slowAfter
        attempts = defaults.map { PasswordAttempts.load($0) } ?? PasswordAttempts()
        // Saved as loaded: a last failure in the future becomes now, so the 15 minutes run from here.
        if let defaults { attempts.save(defaults) }
        wait(until: attempts.nextTry)
    }

    /// Someone may be stuck: the third wrong password in this lock, a wait, or one check that runs past `slowAfter`. A
    /// lock with ⌃⌥⌘Q names it from then on.
    var stuck: Bool { wrong >= 3 || waited || slowCheck }

    /// Starts a password check, unless one runs or the wait after wrong passwords does. Here, so no view can skip
    /// the wait. false: no check may start.
    func beginCheck() -> Bool {
        guard waitLeft == 0, !checking else { return false }
        checking = true
        slowTimer = Task { [weak self, slowAfter] in
            try? await Task.sleep(for: slowAfter)
            guard !Task.isCancelled, let self, checking else { return }
            slowCheck = true
            onSlowCheck()
        }
        return true
    }

    /// The check has its answer.
    func endCheck() {
        checking = false
        slowTimer?.cancel()
        slowTimer = nil
        slowCheck = false
    }

    /// A wrong password: counted here and across locks, and the next try waits as the policy says.
    func failed() {
        wrong += 1
        wrongShown = true
        if let defaults { attempts = PasswordAttempts.load(defaults) }
        attempts.fail()
        if let defaults { attempts.save(defaults) }
        wait(until: attempts.nextTry)
    }

    /// The password or Touch ID unlocked: the count starts again.
    func succeeded() {
        attempts = PasswordAttempts()
        if let defaults { attempts.save(defaults) }
    }

    private func wait(until date: Date?) {
        waiting?.cancel()
        waitLeft = date.map { Int(max(0, $0.timeIntervalSinceNow).rounded(.up)) } ?? 0
        guard let date, waitLeft > 0 else { return }
        waited = true
        waiting = Task { [weak self] in
            while !Task.isCancelled {
                let left = date.timeIntervalSinceNow
                guard let self, left > 0 else { break }
                waitLeft = Int(left.rounded(.up))
                // Until the shown number changes.
                try? await Task.sleep(for: .seconds(left - Double(waitLeft - 1) + 0.01))
            }
            if !Task.isCancelled { self?.waitLeft = 0 }
        }
    }
}

/// Wrong passwords in a row, kept in UserDefaults with the time of the last one, so neither a new lock nor a
/// relaunch starts the count again. A success, or 15 minutes without a wrong password, does.
struct PasswordAttempts: Equatable {
    var count = 0
    var last: Date?

    /// Seconds before the next try after `failures` wrong passwords in a row. Like the login window: three free
    /// tries, then 1, 2, 4, ... seconds up to 30; from the tenth, 5 minutes.
    static func wait(after failures: Int) -> Double {
        if failures < 3 { return 0 }
        if failures >= 10 { return 300 }
        return min(30, pow(2, Double(failures - 3)))
    }

    static let forgetAfter = 15.0 * 60

    /// When the next try may start; nil without a wait.
    var nextTry: Date? {
        guard let last, Self.wait(after: count) > 0 else { return nil }
        return last.addingTimeInterval(Self.wait(after: count))
    }

    mutating func fail(at date: Date = Date()) {
        if let last, date.timeIntervalSince(last) >= Self.forgetAfter { count = 0 }
        count += 1
        last = date
    }

    /// The count as saved, or none once 15 minutes passed. A last failure in the future (the clock went back)
    /// counts as now, so it cannot stretch the wait.
    static func load(_ defaults: UserDefaults, now: Date = Date()) -> PasswordAttempts {
        let count = defaults.integer(forKey: "wrongPasswords"), time = defaults.double(forKey: "lastWrongPassword")
        guard count > 0, time > 0 else { return PasswordAttempts() }
        let last = min(Date(timeIntervalSince1970: time), now)
        guard now.timeIntervalSince(last) < forgetAfter else { return PasswordAttempts() }
        return PasswordAttempts(count: count, last: last)
    }

    func save(_ defaults: UserDefaults) {
        if let last, count > 0 {
            defaults.set(count, forKey: "wrongPasswords")
            defaults.set(last.timeIntervalSince1970, forKey: "lastWrongPassword")
        } else {
            defaults.removeObject(forKey: "wrongPasswords")
            defaults.removeObject(forKey: "lastWrongPassword")
        }
    }
}

/// Touch ID drawn inside Locky's window. LAAuthenticationView takes the place of the system's Touch ID sheet,
/// which could open under the shield, so evaluation starts only once that view exists.
@MainActor @Observable
final class TouchID {
    private(set) var context = LAContext()
    /// Changes with every new context; the glyph view is made again for it.
    private(set) var generation = 0
    /// Touch ID stopped listening (fingers that did not match, or too many restarts) until the next restart: the
    /// glyph goes, and the field asks for the password alone.
    private(set) var gaveUp = false
    private var wanted = false
    private var running = false
    private var readyGeneration = -1
    private var restarts = 0
    private var pendingRestart: Task<Void, Never>?
    private var onSuccess: (@Sendable @MainActor () -> Void)?

    var isAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) }

    /// Starts evaluating as soon as the glyph view for the current context exists.
    func start(onSuccess: @escaping @Sendable @MainActor () -> Void) {
        self.onSuccess = onSuccess
        wanted = true
        evaluateIfReady()
    }

    func glyphAppeared(_ generation: Int) {
        readyGeneration = generation
        evaluateIfReady()
    }

    private func evaluateIfReady() {
        // Never once Touch ID gave up: its glyph is out of the window then, and a hidden one makes macOS show its own
        // prompt.
        guard wanted, !running, !gaveUp, readyGeneration == generation else { return }
        running = true
        let generation = generation
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "unlock your Mac") { [weak self] success, error in
            let code = (error as? LAError)?.code
            let description = error?.localizedDescription
            Task { @MainActor in self?.finished(success, code, description, generation) }
        }
    }

    private func finished(_ success: Bool, _ code: LAError.Code?, _ description: String?, _ generation: Int) {
        guard generation == self.generation else { return }
        running = false
        LogFile.shared.write(level: "info", message: "Touch ID: \(success ? "matched" : "no match")\(description.map { " (\($0))" } ?? "")", source: "locky")
        if success {
            onSuccess?()
            return
        }
        // Cancelled by the system (sleep, another app, a lost context), not by a finger that did not match:
        // try again with a new context. After failed matches, the password is needed, as on the login window.
        if let code, [.systemCancel, .appCancel, .invalidContext, .notInteractive].contains(code), restarts < 10 {
            restarts += 1
            restart(after: 1)
        } else {
            gaveUp = true
        }
    }

    /// A new context (and glyph), evaluated again if it was wanted: after a display wake or a rebuilt window. It
    /// brings back a glyph that gave up, with the new context.
    func restart(after delay: Double = 0) {
        context.invalidate()
        running = false
        // A restart replaces one still waiting (a wake after the system cancelled Touch ID): a second swap would put a
        // new context in under the evaluation the first one started.
        pendingRestart?.cancel()
        pendingRestart = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            context = LAContext()
            generation += 1
            gaveUp = false
        }
    }

    /// Before the field is replaced: an evaluation tied to the old glyph must not go on without it.
    func restartIfRunning() {
        if running { restart() }
    }

    func stop() {
        wanted = false
        context.invalidate()
    }
}

private struct TouchIDGlyph: NSViewRepresentable {
    let touchID: TouchID
    /// .mini in the status line, .small in the ring. LAAuthenticationView's side: mini 16, small 32, regular 64,
    /// large 128 points.
    let size: NSControl.ControlSize

    func makeNSView(context _: Context) -> LAAuthenticationView {
        let view = LAAuthenticationView(context: touchID.context, controlSize: size)
        let generation = touchID.generation
        // The view exists from the next turn of the main queue on; evaluation may start then.
        DispatchQueue.main.async { [touchID] in touchID.glyphAppeared(generation) }
        return view
    }

    func updateNSView(_: LAAuthenticationView, context _: Context) {}
}

/// The password field, in the theme's style: "pill", "underline", "box", "terminal", "minimal", or "ring".
/// Native on purpose: no plugin sees keystrokes.
struct AuthPanel: View {
    let auth: Theme.Auth
    let style: LockyStyle
    let touchID: TouchID?
    @Bindable var model: AuthModel
    let unlock: () -> Void
    let failed: () -> Void
    var onSize: (CGSize) -> Void = { _ in }
    /// false in the theme editor's preview: the field shows, but never takes the keyboard.
    var interactive = true
    /// Previews without Touch ID on a Mac that has it: the glyph shows as a picture, where the lock shows the live one.
    var touchIDPicture = false
    /// The lock offers ⌃⌥⌘Q (settings.json's emergency_exit): VoiceOver hears it when the lock names it.
    var exit = false

    private var password: String {
        get { model.password }
        nonmutating set { model.password = newValue }
    }
    private var user: Auth.User { model.user }
    /// A check runs, or the wait after wrong passwords: the field and the arrow are disabled.
    private var busy: Bool { model.checking || model.waitLeft > 0 }
    /// What the field says in place of its placeholder, while there is something to say.
    private var note: String? { Self.note(waitLeft: model.waitLeft, wrongShown: model.wrongShown) }
    /// The theme's placeholder. The minimal and terminal styles have none unless the theme gives one.
    private var placeholderText: String {
        auth.placeholder ?? (auth.style == "minimal" || auth.style == "terminal" ? "" : "Enter Password")
    }
    private var touchIDOffered: Bool { touchID != nil || touchIDPicture }
    /// Touch ID listens, so its glyph shows.
    private var listening: Bool { touchIDPicture || touchID?.gaveUp == false }
    private var statusText: String? {
        Self.statusText(touchIDOffered: touchIDOffered, listening: listening, placeholder: placeholderText, hint: auth.hint)
    }
    /// Caps Lock is on while the field takes typing. The theme editor's preview never shows it.
    private var capsLockShown: Bool { model.capsLock && interactive }
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The "ring" style's lit arc: where it starts (0 to 1), its role color, and a counter that restarts its fade.
    @State private var arc: (start: Double, color: String, key: Int) = (0, "accent", 0)

    private var s: CGFloat { style.scale }
    private var width: CGFloat { auth.width * s }

    /// The field's note, in place of its placeholder: the wait after wrong passwords, then "Wrong Password" until the
    /// next key. Plain English on purpose: Duration.formatted rounds to the nearest minute and follows the system's
    /// language.
    static func note(waitLeft: Int, wrongShown: Bool) -> String? {
        if waitLeft > 59 {
            let minutes = Int((Double(waitLeft) / 60).rounded(.up))
            return minutes == 1 ? "Try again in 1 minute" : "Try again in \(minutes) minutes"
        }
        if waitLeft > 0 { return waitLeft == 1 ? "Try again in 1 second" : "Try again in \(waitLeft) seconds" }
        return wrongShown ? "Wrong Password" : nil
    }

    /// The way out as VoiceOver says it, with the keys' names in place of their symbols.
    static let wayOut = "Press Control-Option-Command-Q to switch to the macOS lock screen"

    /// What VoiceOver says after a wrong password: the wait too, once there is one, since the field then refuses keys,
    /// and the way out when this wrong password makes the lock name it.
    static func announcement(waitLeft: Int, wayOut: Bool = false) -> String {
        let text = note(waitLeft: waitLeft, wrongShown: false).map { "Wrong Password. \($0)" } ?? "Wrong Password"
        return wayOut ? "\(text). \(Self.wayOut)" : text
    }

    /// The line under the field says how to unlock, unless the field's placeholder says it already. nil: no text
    /// (the glyph alone still shows while Touch ID listens).
    static func statusText(touchIDOffered: Bool, listening: Bool, placeholder: String, hint: Bool) -> String? {
        guard hint else { return nil }
        if touchIDOffered { return listening ? "Touch ID or Enter Password" : "Enter Password" }
        return placeholder.isEmpty ? "Enter Password" : nil
    }

    var body: some View {
        if auth.style == "ring" { ring } else { stack }
    }

    /// i3lock's ring: the password field is the ring. Each key lights an arc at a random place; backspace
    /// lights one in the warning color; checking turns the ring accent, and a wrong password turns it danger.
    private var ring: some View {
        let diameter = width
        let line = auth.ringWidth.map { $0 * s } ?? max(6, diameter * 0.03)
        let base = model.checking ? style.color("accent") : model.wrongShown ? style.color("danger") : style.color("border")
        return ZStack {
            if let fill = auth.ringFill {
                Circle().fill(style.color(fill)).padding(line / 2)
            }
            Circle().stroke(base, lineWidth: line)
            Circle()
                .trim(from: 0, to: 0.14)
                .stroke(style.color(arc.color), style: StrokeStyle(lineWidth: line, lineCap: .butt))
                .rotationEffect(.degrees(arc.start * 360 - 90))
                .shadow(color: auth.ringGlow ? style.color(arc.color) : .clear, radius: auth.ringGlow ? line : 0)
                .opacity(arc.key == 0 ? 0 : 1)
                .id(arc.key)
                // A key lights its arc at once; the arc before it fades out.
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
            secureField(slot: "")
                .frame(width: 1, height: 1)
                .opacity(0.011)
            // Fixed in place while Touch ID listens, whatever the note says: a glyph taken out during an evaluation
            // makes macOS show its own prompt. It stands for the status line here, and LAAuthenticationView has no
            // label of its own.
            if listening {
                glyph(.small)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Touch ID or Enter Password")
                    .offset(y: diameter * 0.34)
            }
            // The ring has no edge to hold it, and themes put a clock in its middle: ⇪ sits on the Touch ID glyph's line,
            // beside the glyph, which stays where it is.
            if capsLockShown {
                capsLockSign(on: auth.ringFill, size: 16)
                    .offset(x: listening ? 16 + 14 * s : 0, y: diameter * 0.34)
            }
            if let note {
                // VoiceOver reads it on the field.
                Text(note)
                    .font(font(12, "medium"))
                    .foregroundStyle(model.waitLeft > 0 ? style.quiet(on: auth.ringFill) : style.color("danger"))
                    .legibilityHalo(style)
                    .offset(y: diameter * 0.24)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.25), value: arc.key)
        .onChange(of: password.count) { old, new in
            guard new != old else { return }
            arc = (Double.random(in: 0..<1), new > old ? "accent" : "warning", arc.key + 1)
            let key = arc.key
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                if arc.key == key { arc.key = 0 }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            if interactive { focused = true }
        }
        .onChange(of: model.focusRequest) { focused = true }
        // A field made during a check or the wait after wrong passwords was disabled when it asked for focus.
        .onChange(of: model.checking || model.waitLeft > 0) { _, busy in if !busy, interactive { focused = true } }
    }

    /// ⇪ in the field's quiet color, as the macOS login window shows Caps Lock. Over the field's own space, so it never
    /// moves the field; it comes and goes with the key, at once.
    private func capsLockSign(on surface: String?, size: CGFloat = 13) -> some View {
        Image(systemName: "capslock.fill")
            .font(.system(size: size * auth.size / 14 * s, weight: .medium))
            .foregroundStyle(style.quiet(on: surface))
            .legibilityHalo(style)
            .accessibilityLabel("Caps Lock is on")
    }

    /// The Touch ID glyph at its natural side, made again for each new context. Gone once Touch ID gave up.
    @ViewBuilder private func glyph(_ size: NSControl.ControlSize) -> some View {
        let side: CGFloat = size == .mini ? 16 : 32
        if let touchID {
            if !touchID.gaveUp {
                TouchIDGlyph(touchID: touchID, size: size).id(touchID.generation).frame(width: side, height: side)
            }
        } else if touchIDPicture {
            Image(systemName: "touchid").resizable().scaledToFit().symbolRenderingMode(.multicolor).frame(width: side, height: side)
        }
    }

    /// Avatar, name, field, and the status line, in one column: nothing beside the field, so its center is the stack's.
    private var stack: some View {
        VStack(alignment: auth.hintAlign == "leading" ? .leading : .center, spacing: 12 * s) {
            if auth.avatar, auth.style != "terminal", auth.style != "minimal", let picture = user.picture { avatar(picture) }
            if auth.name && !user.name.isEmpty && auth.style != "terminal" && auth.style != "minimal" {
                Text(user.name).font(font(15, "semibold")).foregroundStyle(style.color("fg")).lineLimit(1).legibilityHalo(style)
            }
            // Only the shake animates: the note and the arrow change with it at once.
            field.animation(reduceMotion ? nil : .linear(duration: 0.45)) { content in
                content.modifier(Shake(phase: CGFloat(model.wrong), amplitude: 10 * s))
            }
            if touchIDOffered || statusText != nil { statusLine }
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .milliseconds(250))  // the window is key by then
            if interactive { focused = true }
        }
        .onChange(of: model.focusRequest) { focused = true }
        // A field made during a check or the wait after wrong passwords was disabled when it asked for focus.
        .onChange(of: model.checking || model.waitLeft > 0) { _, busy in if !busy, interactive { focused = true } }
    }

    /// The live Touch ID glyph and how to unlock, under the field. As tall as the glyph while Touch ID is offered, so
    /// nothing moves when it gives up.
    private var statusLine: some View {
        HStack(spacing: 6 * s) {
            if listening { glyph(.mini) }
            if let statusText {
                Text(statusText).font(font(12, "medium")).foregroundStyle(style.quiet(on: nil)).legibilityHalo(style)
            }
        }
        .frame(minHeight: touchIDOffered ? 16 : nil)
        // One element that reads the line (LAAuthenticationView has no label of its own), or "Touch ID" for the glyph
        // alone.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusText ?? "Touch ID")
        .accessibilityHidden(statusText == nil && !listening)
    }

    /// Sizes are given for a 14-point field and scale with auth.font.size.
    private func font(_ size: CGFloat, _ weight: String, mono: Bool = false) -> Font {
        let size = size * auth.size / 14
        if (mono || auth.style == "terminal"), auth.font.family == nil {
            return Font.system(size: size * s, weight: StyleWeights.weight(auth.font.weight ?? weight), design: .monospaced)
        }
        return style.font(size: size, weight: auth.font.weight ?? weight, design: auth.font.design, family: auth.font.family, mono: false, italic: false)
    }

    /// The palette role (or color) the field's text sits on; nil where it sits on the screen.
    private var fieldSurface: String? {
        switch auth.style {
        case "underline", "terminal", "minimal": nil
        case "ring": auth.ringFill
        default: "surface"
        }
    }

    private var glowColor: Color { auth.glow == nil ? .clear : style.color(auth.style == "terminal" ? "accent" : "fg") }

    /// The underline's or the box's line: danger after a wrong password, else the focus color while the field is
    /// focused. The editor's preview never takes focus, and draws the focus color as the lock does.
    private var lineColor: Color {
        if model.wrongShown { return style.color("danger") }
        return style.color(interactive ? (focused ? auth.focus : "border") : auth.focus)
    }

    private func avatar(_ picture: NSImage) -> some View {
        Image(nsImage: picture).resizable().scaledToFill()
            .frame(width: 64 * s, height: 64 * s)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 10 * s, y: 4 * s)
    }

    /// The native secure field, with Locky's own placeholder, `slot`: SwiftUI draws a field's prompt in the system's
    /// gray, which disappears on light themes. Locky draws it in the palette's muted color instead.
    private func secureField(slot: String, alignment: Alignment = .leading) -> some View {
        ZStack(alignment: alignment) {
            if password.isEmpty, !slot.isEmpty {
                // The theme's glow from the letters alone, then the halo around both.
                Text(slot).font(font(14, "regular")).foregroundStyle(style.quiet(on: fieldSurface))
                    .shadow(color: glowColor, radius: auth.glow ?? 0)
                    .legibilityHalo(style)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            SecureField("", text: $model.password)
                .textFieldStyle(.plain)
                .font(font(14, "regular"))
                .foregroundStyle(style.color("fg"))
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .focused($focused)
                .disabled(busy || !interactive)
                .onSubmit(submit)
                .accessibilityLabel("Password")
                // The drawn note is hidden: VoiceOver hears the wait, or "Wrong Password", on the field.
                .accessibilityHint(note ?? "")
                .shadow(color: glowColor, radius: auth.glow ?? 0)
        }
    }

    @ViewBuilder private var field: some View {
        switch auth.style {
        case "underline":
            VStack(spacing: 8 * s) {
                secureField(slot: note ?? placeholderText, alignment: auth.hintAlign == "leading" ? .leading : .center)
                    .overlay(alignment: .trailing) { if capsLockShown { capsLockSign(on: fieldSurface) } }
                Rectangle().fill(lineColor).frame(height: 1.5 * s)
            }
            .frame(width: width)
        case "box":
            HStack(spacing: 6 * s) {
                secureField(slot: note ?? placeholderText)
                if capsLockShown { capsLockSign(on: fieldSurface) }
            }
            .padding(.horizontal, 14 * s)
            .frame(width: width, height: 40 * s)
            .background(style.color("surface"), in: RoundedRectangle(cornerRadius: 10 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10 * s, style: .continuous).strokeBorder(lineColor, lineWidth: 1.5 * s))
        case "terminal":
            HStack(spacing: 0) {
                Text(auth.prompt ?? "\(user.login)@\(user.host) ~ % ").font(font(14, "regular")).foregroundStyle(style.color("accent"))
                    .shadow(color: glowColor, radius: auth.glow ?? 0)
                    .legibilityHalo(style)
                Text("unlock ").font(font(14, "regular")).foregroundStyle(style.color("fg"))
                    .shadow(color: glowColor, radius: auth.glow ?? 0)
                    .legibilityHalo(style)
                secureField(slot: note ?? placeholderText).frame(width: width * 0.6)
                    .overlay(alignment: .trailing) { if capsLockShown { capsLockSign(on: fieldSurface) } }
            }
        case "minimal":
            // The field is there and focused from the start, but only appears once you type or it has a note.
            secureField(slot: note ?? placeholderText, alignment: .center)
                .frame(width: width)
                .opacity(!password.isEmpty || note != nil ? 1 : 0.01)
                // Shows while the field itself does not: the next key types in capitals.
                .overlay(alignment: .trailing) { if capsLockShown { capsLockSign(on: fieldSurface) } }
        default:
            HStack(spacing: 6 * s) {
                secureField(slot: note ?? placeholderText)
                if capsLockShown { capsLockSign(on: fieldSurface) }
                if !password.isEmpty {
                    // A pointer target only: Return stays the keyboard's way.
                    Button(action: submit) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20 * s))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(style.color("fg"))
                    }
                    .buttonStyle(PressDim())
                    .focusable(false)
                    .disabled(busy)
                    .accessibilityLabel("Unlock")
                }
            }
            .padding(.leading, 16 * s)
            .padding(.trailing, (password.isEmpty ? 16 : 8) * s)
            .frame(width: width, height: 36 * s)
            .modifier(GlassCapsule(fill: style.color("surface")))
        }
    }

    private func submit() {
        guard !password.isEmpty, model.beginCheck() else { return }
        Task {
            let ok = await Auth.verify(password)
            password = ""
            model.endCheck()
            if ok {
                model.succeeded()
                unlock()
            } else {
                let named = model.stuck
                model.failed()
                let wayOut = exit && !named && model.stuck
                AccessibilityNotification.Announcement(Self.announcement(waitLeft: model.waitLeft, wayOut: wayOut)).post()
                failed()
                focused = true
            }
        }
    }
}

/// WCAG 2 contrast from the palette's colors, for the field's quiet text: the placeholder and the hint must
/// reach 4.5:1 on what is behind them.
enum Contrast {
    struct RGB: Equatable {
        var r, g, b: Double
    }

    /// `hex`, with its alpha, painted over the opaque `below`.
    static func over(_ hex: String, _ below: RGB) -> RGB? {
        guard let color = NSColor(hex: hex) else { return nil }
        let a = color.alphaComponent
        return RGB(r: color.redComponent * a + below.r * (1 - a), g: color.greenComponent * a + below.g * (1 - a),
                   b: color.blueComponent * a + below.b * (1 - a))
    }

    static func luminance(_ color: RGB) -> Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// The color to draw `text` in over `layers` (painted first to last on black): `text` itself when it reaches
    /// 4.5:1, otherwise the first mix toward `fg` that does, or `fg`'s own color. nil when a color is not "#rrggbb[aa]".
    static func readable(_ text: String, fg: String, on layers: [String]) -> String? {
        var backdrop = RGB(r: 0, g: 0, b: 0)
        for layer in layers {
            guard let next = over(layer, backdrop) else { return nil }
            backdrop = next
        }
        guard let start = over(text, backdrop), let end = over(fg, backdrop) else { return nil }
        if ratio(start, backdrop) >= 4.5 { return text }
        for step in 1...20 {
            let t = Double(step) / 20
            let mix = RGB(r: start.r + (end.r - start.r) * t, g: start.g + (end.g - start.g) * t, b: start.b + (end.b - start.b) * t)
            if ratio(mix, backdrop) >= 4.5 || step == 20 {
                return String(format: "#%02x%02x%02x", Int((mix.r * 255).rounded()), Int((mix.g * 255).rounded()), Int((mix.b * 255).rounded()))
            }
        }
        return nil
    }
}

extension LockyStyle {
    /// The palette's muted color, lifted toward fg where it would not reach 4.5:1 on `surface` (a palette role or a
    /// color) over the screen's bg, or on bg alone when nil: the field's placeholder, the status line, the glance
    /// hint, and the message. The backdrop it must read on has 12% of fg over it, a margin: the pill's glass renders
    /// lighter than the palette's surface, and the halo leaves part of the scene at its edge. Lifted to 4.5:1 on the
    /// palette alone, Tokyo Night's placeholder read 3.7:1 on its glass.
    func quiet(on surface: String?) -> Color {
        guard let muted = palette["muted"], let fg = palette["fg"], let bg = palette["bg"] else { return color("muted") }
        var layers = [bg]
        if let surface, let hex = palette[surface] ?? (surface.hasPrefix("#") ? surface : nil) { layers.append(hex) }
        if let margin = NSColor(hex: fg) {
            layers.append(String(format: "#%02x%02x%02x1f", Int((margin.redComponent * 255).rounded()),
                                 Int((margin.greenComponent * 255).rounded()), Int((margin.blueComponent * 255).rounded())))
        }
        return Contrast.readable(muted, fg: fg, on: layers).flatMap { Color(hex: $0) } ?? color("muted")
    }
}

/// "Press any key to unlock", where the password field of a theme that shows it on activity will appear.
struct GlanceHint: View {
    let auth: Theme.Auth
    let style: LockyStyle

    var body: some View {
        Text("Press any key to unlock")
            .font(style.font(size: 13 * auth.size / 14, weight: auth.font.weight ?? "medium", design: auth.font.design,
                             family: auth.font.family, mono: false, italic: false))
            .foregroundStyle(style.quiet(on: nil))
            .legibilityHalo(style)
    }
}

/// The theme's bg close around the lock screen's text, so it reads on any scene without sampling it: each letter sits
/// on the bg that `Contrast.readable` measured its color against, from one end of the widest line to the other. Where
/// the scene matches its palette it does not show, Matrix's rain and Notebook's lines included. It takes the place of
/// an area scrim, which dimmed those scenes around the field, showed as a dark oval on others, and left the ends of a
/// long line on the scene (Snowfall's ⌃⌥⌘Q line read 3.6:1 there).
struct LegibilityHalo: ViewModifier {
    let style: LockyStyle

    func body(content: Content) -> some View {
        let color = style.palette["bg"].flatMap { NSColor(hex: $0)?.withAlphaComponent(1) }.map { Color(nsColor: $0) } ?? .black
        let s = style.scale
        // Two tight passes outline the letters, the third fills their insides, the last feathers the edge.
        content
            .shadow(color: color, radius: s)
            .shadow(color: color, radius: s)
            .shadow(color: color, radius: 2 * s)
            .shadow(color: color.opacity(0.6), radius: 5 * s)
    }
}

extension View {
    /// The palette's bg close around this text: see LegibilityHalo.
    func legibilityHalo(_ style: LockyStyle) -> some View { modifier(LegibilityHalo(style: style)) }
}

enum StyleWeights {
    static func weight(_ name: String) -> Font.Weight { LockyStyle.weights[name] ?? .regular }
}

/// The pill's glass. The regular variant: the pill holds text (HIG Materials).
private struct GlassCapsule: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(fill), in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

/// The unlock arrow: dimmed while the pointer is down, at once, as AppKit highlights a press, and while it is disabled.
private struct PressDim: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed || !isEnabled ? 0.55 : 1)
    }
}

/// The macOS login window's head-shake for a wrong password: three swings that die down while `phase` moves to the
/// next whole number.
struct Shake: GeometryEffect {
    var phase: CGFloat
    var amplitude: CGFloat
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let f = phase - phase.rounded(.down)
        return ProjectionTransform(CGAffineTransform(translationX: amplitude * sin(f * 6 * .pi) * (1 - f), y: 0))
    }
}
