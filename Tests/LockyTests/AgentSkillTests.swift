import Foundation
import Testing
@testable import Locky

/// `locky skill install` and Settings' Install: copies into a home folder of the test's own, never the real one.
@Suite struct AgentSkillTests {
    let sandbox: Sandbox
    var home: URL { sandbox.root.appending(path: "home") }
    var source: URL { sandbox.root.appending(path: "skill/locky") }

    init() throws {
        sandbox = try Sandbox()
        try FileManager.default.createDirectory(at: source.appending(path: "references"), withIntermediateDirectories: true)
        try "v1".write(to: source.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "api".write(to: source.appending(path: "references/api.md"), atomically: true, encoding: .utf8)
    }

    private func makeHome(_ folders: String...) throws {
        for folder in folders { try FileManager.default.createDirectory(at: home.appending(path: folder), withIntermediateDirectories: true) }
    }

    /// Only the agents whose folder is there get the skill; Locky makes no agent folder.
    @Test func installsForTheAgentsThereAre() throws {
        try makeHome(".claude", ".agents")
        let skill = AgentSkill(home: home, source: source)
        #expect(skill.agents == [.claude, .agents])
        #expect(skill.state(for: .claude) == .missing)
        let folders = try skill.install()
        #expect(folders.map(\.path) == [home.appending(path: ".claude/skills/locky").path, home.appending(path: ".agents/skills/locky").path])
        #expect(try String(contentsOf: home.appending(path: ".claude/skills/locky/references/api.md"), encoding: .utf8) == "api")
        #expect(!FileManager.default.fileExists(atPath: home.appending(path: ".codex").path))
        #expect(skill.state(for: .claude) == .current && skill.state(for: .agents) == .current)
    }

    /// A newer skill makes the copy outdated; installing again replaces it whole, and leaves nothing beside it.
    @Test func replacesAnOlderCopy() throws {
        try makeHome(".codex")
        let skill = AgentSkill(home: home, source: source)
        try skill.install()
        let installed = skill.folder(for: .codex)
        try "old".write(to: installed.appending(path: "stale.md"), atomically: true, encoding: .utf8)
        try "v2".write(to: source.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        #expect(skill.state(for: .codex) == .outdated)
        try skill.install()
        #expect(skill.state(for: .codex) == .current)
        #expect(!FileManager.default.fileExists(atPath: installed.appending(path: "stale.md").path))
        let skills = try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path)
        #expect(skills == ["locky"])
    }

    @Test func failsWithoutAnAgent() throws {
        try makeHome()
        #expect(throws: AgentSkill.Failure.self) { try AgentSkill(home: home, source: source).install() }
    }

    /// Customization's Agent skill row names the agents that have the skill, and what it needs while none could.
    @Test func theRowSaysWhereTheSkillIs() {
        #expect(AgentSkillRow.subtitle(agents: [], installed: []) == "Needs Claude Code, Codex, or a ~/.agents folder.")
        #expect(AgentSkillRow.subtitle(agents: [.claude], installed: []) == "Lets coding agents make widgets and themes.")
        #expect(AgentSkillRow.subtitle(agents: [.claude, .codex], installed: [.claude, .codex]) == "Installed in Claude Code and Codex.")
        #expect(AgentSkillRow.subtitle(agents: Array(AgentSkill.Agent.allCases), installed: Array(AgentSkill.Agent.allCases))
            == "Installed in Claude Code, Codex, and ~/.agents.")
    }

    /// The bundled skill's references are docs/ itself: docs/ is the one source, and this test keeps the copies equal.
    @Test func referencesMatchTheDocs() throws {
        let docs = RuntimePath.resources.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "docs")
        let references = AgentSkill.bundled.appending(path: "references")
        let names = try FileManager.default.contentsOfDirectory(atPath: references.path).sorted()
        #expect(names == ["agents.md", "api.md", "create-widget.md", "plugins.md", "themes.md", "views.md", "widgets.md"])
        for name in names {
            let copy = try Data(contentsOf: references.appending(path: name)), original = try Data(contentsOf: docs.appending(path: name))
            #expect(copy == original, "\(name) differs from docs/\(name): run Scripts/sync-skill.sh")
        }
    }
}
