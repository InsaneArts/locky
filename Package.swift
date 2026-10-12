// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Locky",
    platforms: [.macOS(.v15)],
    targets: [
        // Lua 5.5.1, unmodified (see Sources/CLua/LICENSE), plus Locky's C bridge: locky_bridge.c.
        .target(
            name: "CLua",
            path: "Sources/CLua",
            exclude: ["LICENSE"],
            cSettings: [.define("LUA_USE_POSIX")]
        ),
        // Resources are copied into the .app by Scripts/package_app.sh, so the target has no Bundle.module.
        .executableTarget(name: "Locky", dependencies: ["CLua"], path: "Sources/Locky", exclude: ["Resources"]),
        .testTarget(name: "LockyTests", dependencies: ["Locky"], path: "Tests/LockyTests"),
    ]
)
