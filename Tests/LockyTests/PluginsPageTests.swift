import AppKit
import Foundation
import Testing
@testable import Locky

/// The Add Widget sheet's cards and the Plugins pane.
@MainActor
@Suite struct PluginsPageTests {
    /// Polls `condition` on the main actor, where the model lives.
    private func wait(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        return condition()
    }

    /// An installed plugin as the config read lists it.
    private func pack(src: String? = nil, version: String? = nil, dir: String? = nil, fromSettings: Bool = true,
                      alsoInConfig: Bool = false) -> Inspection.PackInfo {
        Inspection.PackInfo(name: "x", src: src, version: version, dir: dir.map { URL(fileURLWithPath: $0) }, fromSettings: fromSettings,
                            alsoInConfig: alsoInConfig, folder: URL(fileURLWithPath: "/tmp/x"), installed: true)
    }

    /// A plugin's row says what it adds in the names people read, with "Theme:" and "Widget:" for one, and nothing when
    /// it adds nothing.
    @Test func aPluginSaysWhatItAdds() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/stars.lua", """
            locky.widget.define('stars.count', { render = function() end })
            locky.widget.define('stars.graph', { render = function() end })
            """)
        try sandbox.write("themes/stormy.lua", "return { name = 'Stormy' }")
        _ = NSApplication.shared
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        model.refresh()
        #expect(await wait { model.inspection.loaded })
        #expect(Provides.summary(model: model, folder: sandbox.config) == "Theme: Stormy · Widgets: Stars Count, Stars Graph")
        #expect(Provides.summary(model: model, folder: sandbox.packs) == nil)
    }

    @Test(arguments: [(.sync, "Couldn't install plugins"), (.update, "Couldn't update plugins"), (.clean, "Couldn't remove the plugin"),
                      (.check, "Couldn't check for updates")] as [(PackManager.Action, String)])
    func aFailedRunSaysWhatFailed(_ action: PackManager.Action, _ title: String) {
        #expect(PluginsPage.failure(action) == title)
    }

    /// A row names where a plugin comes from in short: its GitHub path or address, or its folder; then its version, and
    /// init.lua for one init.lua adds.
    @Test func aPluginsSourceIsShort() {
        #expect(PluginsPage.source(pack(src: "https://github.com/someone/locky-stars")) == "someone/locky-stars")
        #expect(PluginsPage.source(pack(src: "https://github.com/someone/locky-stars.git", version: "v1.2.0")) == "someone/locky-stars · v1.2.0")
        #expect(PluginsPage.source(pack(src: "https://github.com/someone/locky-git-extra", fromSettings: false)) == "someone/locky-git-extra · init.lua")
        #expect(PluginsPage.source(pack(src: "git@gitlab.com:someone/x.git")) == "git@gitlab.com:someone/x.git")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(PluginsPage.source(pack(dir: home + "/code/my-plugin")) == "~/code/my-plugin")
    }

    /// Remove deletes only a clone Locky made, and its message says what happens to the folder. A local folder is the
    /// person's own: a clean would delete it if the lockfile still named it from an earlier install.
    @Test func removeDeletesOnlyACloneLockyMade() {
        let clone = pack(src: "https://github.com/someone/locky-stars")
        let local = pack(dir: "/tmp/x")
        let both = pack(src: "https://github.com/someone/locky-stars", alsoInConfig: true)
        #expect(PluginsPage.deletesFolder(clone))
        #expect(!PluginsPage.deletesFolder(local))
        #expect(!PluginsPage.deletesFolder(both))
        #expect(PluginsPage.removal(clone) == "Locky deletes its folder. Its themes and widgets stop showing.")
        #expect(PluginsPage.removal(local) == "Locky keeps its folder. Its themes and widgets stop showing.")
        #expect(PluginsPage.removal(both) == "init.lua also adds it, so it stays installed.")
    }

    /// The update footer says "Up to date" only after a check that reached every plugin and found nothing newer. A
    /// failed check keeps its results until the next check, so a later run that succeeds does not make it up to date.
    @Test func upToDateNeedsACheckThatReachedEveryPlugin() {
        let old = "3f9c2a1b7d4e5f60718293a4b5c6d7e8f9a0b1c2", new = "8b1d0e4a9c7f6e5d4c3b2a1908f7e6d5c4b3a291"
        let current = PackUpdate(name: "locky-stars", current: old, latest: old)
        #expect(PluginsPage.upToDate([current]))
        #expect(!PluginsPage.upToDate([PackUpdate(name: "locky-stars", current: old, latest: new)]))
        #expect(!PluginsPage.upToDate([current, PackUpdate(name: "locky-transit", current: old, error: "fetch failed")]))
        // A check that failed as a whole, such as one that found another run holding the lock, lists no plugin.
        #expect(!PluginsPage.upToDate([]))
        #expect(!PluginsPage.upToDate([PackUpdate(name: "locky-transit")]))
    }

    /// Every card shows the sizes in one order: the Lock Screen ones, then the desktop ones.
    @Test func sizesShowInOneOrder() {
        #expect(FamilyPicker.sorted(["small", "inline", "circular", "large"]) == ["circular", "inline", "small", "large"])
        #expect(FamilyPicker.order == ["circular", "rectangular", "inline", "small", "medium", "large"])
    }
}
