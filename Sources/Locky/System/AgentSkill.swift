import Foundation

/// The Locky skill for coding agents: SKILL.md and the Lua API docs, in Locky.app's Resources/skill/locky. `locky skill
/// install` and Settings › Customization copy it into each agent's skills folder, so an agent can write widgets and themes.
/// Only agents whose folder is there get it: Locky never creates ~/.claude, ~/.codex, or ~/.agents.
struct AgentSkill {
    /// The skill as Locky ships it.
    static var bundled: URL { RuntimePath.resources.appending(path: "skill/locky") }

    enum Agent: String, CaseIterable, Sendable {
        case claude = ".claude", codex = ".codex", agents = ".agents"

        /// As Settings and the command line name it.
        var name: String {
            switch self {
            case .claude: "Claude Code"
            case .codex: "Codex"
            case .agents: "~/.agents"
            }
        }
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Where the skill is, for one agent.
    enum State: Equatable, Sendable {
        case missing
        /// Another version than the one Locky ships.
        case outdated
        case current
    }

    /// The home folder the agents' folders are in: $HOME, as the agents read it; tests pass their own.
    var home = ProcessInfo.processInfo.environment["HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
        ?? FileManager.default.homeDirectoryForCurrentUser
    var source = AgentSkill.bundled

    /// The agents whose folder is in the home folder.
    var agents: [Agent] {
        Agent.allCases.filter { FileManager.default.fileExists(atPath: home.appending(path: $0.rawValue).path) }
    }

    func folder(for agent: Agent) -> URL { home.appending(path: "\(agent.rawValue)/skills/locky") }

    func state(for agent: Agent) -> State {
        let folder = folder(for: agent)
        guard FileManager.default.fileExists(atPath: folder.path) else { return .missing }
        return Self.contents(of: folder) == Self.contents(of: source) ? .current : .outdated
    }

    /// Copies the skill to every agent there is, replacing an older copy, and returns the folders. Each copy goes to a
    /// folder beside its place first and then swaps in, so an agent never reads half a skill.
    @discardableResult
    func install() throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.appending(path: "SKILL.md").path) else {
            throw Failure(errorDescription: "The skill is missing from Locky: \(LuaError.shortenPaths(source.path))")
        }
        let agents = agents
        guard !agents.isEmpty else {
            throw Failure(errorDescription: "No agent folder: Locky installs the skill in ~/.claude, ~/.codex, and ~/.agents.")
        }
        return try agents.map { agent in
            let folder = folder(for: agent)
            let parent = folder.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            let temporary = parent.appending(path: ".locky-\(UUID().uuidString)")
            try fm.copyItem(at: source, to: temporary)
            if fm.fileExists(atPath: folder.path) {
                do {
                    _ = try fm.replaceItemAt(folder, withItemAt: temporary)
                } catch {
                    try? fm.removeItem(at: temporary)
                    throw error
                }
            } else {
                try fm.moveItem(at: temporary, to: folder)
            }
            return folder
        }
    }

    /// Every file under `folder` by relative path, with its bytes.
    private static func contents(of folder: URL) -> [String: Data] {
        let paths = (try? FileManager.default.subpathsOfDirectory(atPath: folder.path)) ?? []
        var files: [String: Data] = [:]
        for path in paths { files[path] = try? Data(contentsOf: folder.appending(path: path)) }
        return files
    }
}
