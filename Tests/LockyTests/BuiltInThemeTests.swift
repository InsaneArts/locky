import Foundation
import Metal
import Testing
@testable import Locky

/// Every theme Locky ships must load cleanly, start every widget, draw it, and compile its shader.
@Suite struct BuiltInThemeTests {
    static let themes: [String] = {
        let sandboxPath = RuntimePath(config: URL(fileURLWithPath: "/nonexistent"), packs: URL(fileURLWithPath: "/nonexistent"),
                                      roots: [RuntimePath.builtInRuntime] + RuntimePath.builtInPackages)
        return sandboxPath.findAll("themes", suffix: ".lua").map(\.name).sorted()
    }()

    @Test func thereAreThemes() {
        #expect(Self.themes.contains("default"))
    }

    @Test(arguments: themes) func themeStartsCleanly(_ name: String) async throws {
        let sandbox = try Sandbox()
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(packages: true), delegate: recorder.delegate)
        let started = await runtime.start(theme: name)
        defer { runtime.stop() }
        #expect(started.theme.id == name)
        #expect(started.problems.isEmpty, "\(started.problems)")
        #expect(!started.instances.contains(nil), "every widget starts")
        let ids = started.instances.compactMap { $0 }
        // Widgets that wait for a program (herdr, for one) may draw nothing yet; none may fail.
        _ = await eventually(timeout: 2) { ids.allSatisfy { recorder.views[$0] != nil } }
        #expect(recorder.failures.isEmpty, "\(recorder.failures.mapValues(\.message))")

        for (layer, transparent) in [(started.theme.background, false), (started.theme.overlay, true)] {
            guard case .shader(let url, _, _, _, _, _, _)? = layer else { continue }
            let device = try #require(MTLCreateSystemDefaultDevice())
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(throws: Never.self) { _ = try ShaderView.compile(source, device: device, transparent: transparent) }
        }
    }
}
