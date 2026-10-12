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
    var password = ""
    /// Bumped to put the keyboard focus back in the field.
    var focusRequest = 0
    /// The lock could not take the keyboard (macOS refused it): the field asks for a click instead of looking
    /// ready for typing, so nobody types the password into the app behind the lock.
    var needsClick = false
    /// Wrong passwords so far, and whether a check (or the wait after the third wrong one) runs. Here and not in
    /// the field, so a rebuilt field (a display added, the power changed) keeps the wait.
    var wrong = 0
    var checking = false
    /// The user the field shows; privacy mode can change it while the field stays.
    var user = Auth.User(name: "", login: "user", host: "mac", picture: nil)
}

/// Touch ID drawn inside Locky's window. LAAuthenticationView takes the place of the system's Touch ID sheet,
/// which could open under the shield, so evaluation starts only once that view exists.
@MainActor @Observable
final class TouchID {
    private(set) var context = LAContext()
    /// Changes with every new context; the glyph view is made again for it.
    private(set) var generation = 0
    private var wanted = false
    private var running = false
    private var readyGeneration = -1
    private var restarts = 0
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
        guard wanted, !running, readyGeneration == generation else { return }
        running = true
        let generation = generation
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "unlock your Mac") { success, error in
            let code = (error as? LAError)?.code
            let description = error?.localizedDescription
            Task { @MainActor [weak self] in self?.finished(success, code, description, generation) }
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
        }
    }

    /// A new context (and glyph), evaluated again if it was wanted: after a display wake or a rebuilt window.
    func restart(after delay: Double = 0) {
        context.invalidate()
        running = false
        Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self else { return }
            context = LAContext()
            generation += 1
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

    func makeNSView(context _: Context) -> LAAuthenticationView {
        let view = LAAuthenticationView(context: touchID.context, controlSize: .regular)
        let generation = touchID.generation
        // The view exists from the next turn of the main queue on; evaluation may start then.
        DispatchQueue.main.async { [touchID] in touchID.glyphAppeared(generation) }
        return view
    }

    func updateNSView(_: LAAuthenticationView, context _: Context) {}
}

/// The password field, in the theme's style: "pill", "underline", "box", "terminal", or "minimal".
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

    private var password: String {
        get { model.password }
        nonmutating set { model.password = newValue }
    }
    private var checking: Bool {
        get { model.checking }
        nonmutating set { model.checking = newValue }
    }
    private var wrong: Int {
        get { model.wrong }
        nonmutating set { model.wrong = newValue }
    }
    private var user: Auth.User { model.user }
    @FocusState private var focused: Bool
    /// The "ring" style's lit arc: where it starts (0 to 1), its role color, and a counter that restarts its fade.
    @State private var arc: (start: Double, color: String, key: Int) = (0, "accent", 0)

    private var s: CGFloat { style.scale }
    private var width: CGFloat { auth.width * s }

    var body: some View {
        if auth.style == "ring" { ring } else { stack }
    }

    /// i3lock's ring: the password field is the ring. Each key lights an arc at a random place; backspace
    /// lights one in the warning color; checking turns the ring accent, and a wrong password flashes it.
    private var ring: some View {
        let diameter = width
        let line = auth.ringWidth.map { $0 * s } ?? max(6, diameter * 0.03)
        let base = checking ? style.color("accent") : wrong > 0 && password.isEmpty ? style.color("danger") : style.color("border")
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
                .transition(.opacity)
            secureField(placeholder: "")
                .frame(width: 1, height: 1)
                .opacity(0.011)
            if touchID != nil, !checking, !(wrong > 0 && password.isEmpty), !model.needsClick {
                glyph.offset(y: diameter * 0.34)
            } else if auth.hint || model.needsClick {
                Text(model.needsClick ? "click to unlock" : checking ? "verifying" : wrong > 0 && password.isEmpty ? "wrong" : "")
                    .font(font(12, "medium"))
                    .foregroundStyle(wrong > 0 && password.isEmpty ? style.color("danger") : style.color("muted"))
                    .offset(y: diameter * 0.36)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.25), value: arc.key)
        .animation(.easeOut(duration: 0.2), value: checking)
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
    }

    private var showsGlyph: Bool { touchID != nil }

    /// The Touch ID glyph, made again for each new context.
    @ViewBuilder private var glyph: some View {
        if let touchID {
            TouchIDGlyph(touchID: touchID).id(touchID.generation).frame(width: 34 * s, height: 34 * s)
        }
    }

    private var stack: some View {
        VStack(alignment: auth.hintAlign == "leading" ? .leading : .center, spacing: 12 * s) {
            if auth.avatar && auth.style != "terminal" && auth.style != "minimal" { avatar }
            if auth.name && !user.name.isEmpty && auth.style != "terminal" && auth.style != "minimal" {
                Text(user.name).font(font(15, "semibold")).foregroundStyle(style.color("fg"))
            }
            HStack(spacing: 10 * s) {
                // A gap as wide as the Touch ID glyph keeps the field itself centered.
                if showsGlyph, auth.hintAlign != "leading", auth.style != "terminal" { Color.clear.frame(width: 34 * s, height: 1) }
                field
                if showsGlyph { glyph }
            }
            .modifier(Shake(times: CGFloat(wrong)))
            .animation(.default, value: wrong)
            if auth.hint { hint }
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .milliseconds(250))  // the window is key by then
            if interactive { focused = true }
        }
        .onChange(of: model.focusRequest) { focused = true }
    }

    /// Sizes are given for a 14-point field and scale with auth.font.size.
    private func font(_ size: CGFloat, _ weight: String, mono: Bool = false) -> Font {
        let size = size * auth.size / 14
        if (mono || auth.style == "terminal"), auth.font.family == nil {
            return Font.system(size: size * s, weight: StyleWeights.weight(auth.font.weight ?? weight), design: .monospaced)
        }
        return style.font(size: size, weight: auth.font.weight ?? weight, design: auth.font.design, family: auth.font.family, mono: false, italic: false)
    }

    private var glowColor: Color { auth.glow == nil ? .clear : style.color(auth.style == "terminal" ? "accent" : "fg") }

    private var avatar: some View {
        Group {
            if let picture = user.picture { Image(nsImage: picture).resizable().scaledToFill() }
            else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(style.color("muted")) }
        }
        .frame(width: 64 * s, height: 64 * s)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.3), radius: 10 * s, y: 4 * s)
    }

    /// The native secure field, with Locky's own placeholder: SwiftUI draws a field's prompt in the system's
    /// gray, which disappears on light themes. Locky draws it in the palette's muted color instead.
    private func secureField(placeholder: String? = nil, alignment: Alignment = .leading) -> some View {
        let text = model.needsClick ? "Click to unlock" : placeholder ?? auth.placeholder ?? (auth.style == "minimal" ? "" : "Enter Password")
        return ZStack(alignment: alignment) {
            if password.isEmpty, !text.isEmpty {
                Text(text).font(font(14, "regular")).foregroundStyle(style.color("muted")).allowsHitTesting(false)
            }
            SecureField("", text: $model.password)
                .textFieldStyle(.plain)
                .font(font(14, "regular"))
                .foregroundStyle(style.color("fg"))
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .focused($focused)
                .disabled(checking || !interactive)
                .onSubmit(submit)
        }
        .shadow(color: glowColor, radius: auth.glow ?? 0)
    }

    @ViewBuilder private var field: some View {
        switch auth.style {
        case "underline":
            VStack(spacing: 8 * s) {
                secureField(alignment: auth.hintAlign == "leading" ? .leading : .center)
                Rectangle().fill(wrong > 0 && password.isEmpty ? style.color("danger") : style.color(focused ? auth.focus : "border"))
                    .frame(height: 1.5 * s)
            }
            .frame(width: width)
        case "box":
            secureField()
                .padding(.horizontal, 14 * s)
                .frame(width: width, height: 40 * s)
                .background(style.color("surface"), in: RoundedRectangle(cornerRadius: 10 * s, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10 * s, style: .continuous).strokeBorder(style.color(focused ? auth.focus : "border"), lineWidth: 1.5 * s))
        case "terminal":
            HStack(spacing: 0) {
                Text(auth.prompt ?? "\(user.login)@\(user.host) ~ % ").font(font(14, "regular")).foregroundStyle(style.color("accent"))
                    .shadow(color: glowColor, radius: auth.glow ?? 0)
                Text("unlock ").font(font(14, "regular")).foregroundStyle(style.color("fg"))
                    .shadow(color: glowColor, radius: auth.glow ?? 0)
                secureField(placeholder: auth.placeholder ?? "").frame(width: width * 0.6)
            }
        case "minimal":
            // The field is there and focused from the start, but only appears once you type.
            secureField(alignment: .center)
                .frame(width: width)
                .opacity(password.isEmpty ? 0.01 : 1)
                .animation(.smooth, value: password.isEmpty)
        default:
            secureField()
                .padding(.horizontal, 16 * s)
                .frame(width: width, height: 36 * s)
                .modifier(GlassCapsule(fill: style.color("surface")))
        }
    }

    private var hint: some View {
        let text = auth.style == "minimal" ? "Type your password to unlock"
            : touchID == nil || auth.style == "terminal" ? "Enter your password" : "Touch ID or enter your password"
        return Text(wrong > 0 ? "Wrong password" : text)
            .font(font(12, "medium"))
            .foregroundStyle(wrong > 0 ? style.color("danger") : style.color("muted"))
            .opacity(auth.style == "minimal" && !password.isEmpty ? 0 : 1)
    }

    private func submit() {
        guard !password.isEmpty, !checking else { return }
        checking = true
        Task {
            let ok = await Auth.verify(password)
            checking = false
            if ok {
                unlock()
            } else {
                password = ""
                wrong += 1
                failed()
                // Like the login window: after a few wrong passwords, each next try waits longer (up to 30 s).
                if wrong >= 3 {
                    checking = true
                    try? await Task.sleep(for: .seconds(min(30, pow(2, Double(wrong - 3)))))
                    checking = false
                }
                focused = true
            }
        }
    }
}

enum StyleWeights {
    static func weight(_ name: String) -> Font.Weight { LockyStyle.weights[name] ?? .regular }
}

private struct GlassCapsule: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear.tint(fill), in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

/// The macOS login window's head-shake for a wrong password.
private struct Shake: GeometryEffect {
    var times: CGFloat
    var animatableData: CGFloat {
        get { times }
        set { times = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(times * .pi * 4), y: 0))
    }
}
