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
        func pack(src: String? = nil, version: String? = nil, dir: String? = nil, fromSettings: Bool = true) -> Inspection.PackInfo {
            Inspection.PackInfo(name: "x", src: src, version: version, dir: dir.map { URL(fileURLWithPath: $0) }, fromSettings: fromSettings,
                                alsoInConfig: false, folder: URL(fileURLWithPath: "/tmp/x"), installed: true)
        }
        #expect(PluginsPage.source(pack(src: "https://github.com/someone/locky-stars")) == "someone/locky-stars")
        #expect(PluginsPage.source(pack(src: "https://github.com/someone/locky-stars.git", version: "v1.2.0")) == "someone/locky-stars · v1.2.0")
        #expect(PluginsPage.source(pack(src: "https://github.com/someone/locky-git-extra", fromSettings: false)) == "someone/locky-git-extra · init.lua")
        #expect(PluginsPage.source(pack(src: "git@gitlab.com:someone/x.git")) == "git@gitlab.com:someone/x.git")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(PluginsPage.source(pack(dir: home + "/code/my-plugin")) == "~/code/my-plugin")
    }

    /// Every card shows the sizes in one order: the Lock Screen ones, then the desktop ones.
    @Test func sizesShowInOneOrder() {
        #expect(FamilyPicker.sorted(["small", "inline", "circular", "large"]) == ["circular", "inline", "small", "large"])
        #expect(FamilyPicker.order == ["circular", "rectangular", "inline", "small", "medium", "large"])
    }
}
