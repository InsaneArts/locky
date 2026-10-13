// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Locky",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Locky", targets: ["Locky"]),
        // Named apart from Locky, so `killall Locky` does not end it too.
        .executable(name: "locky-guard", targets: ["LockyGuard"]),
    ],
    targets: [
        // Lua 5.5.1, unmodified (see Sources/CLua/LICENSE), plus Locky's C bridge: locky_bridge.c.
        .target(
            name: "CLua",
            path: "Sources/CLua",
            exclude: ["LICENSE"],
            cSettings: [.define("LUA_USE_POSIX")]
        ),
        // Resources are copied into the .app by Scripts/package_app.sh, so the target has no Bundle.module.
        // The guard, which locks the Mac with the macOS lock screen if Locky dies or hangs during a lock, and what
        // Locky shares with it. Foundation and Darwin only.
        .target(name: "GuardCore", path: "Sources/GuardCore"),
        .executableTarget(name: "LockyGuard", dependencies: ["GuardCore"], path: "Sources/LockyGuard"),
        .executableTarget(name: "Locky", dependencies: ["CLua", "GuardCore"], path: "Sources/Locky", exclude: ["Resources"]),
        .testTarget(name: "LockyTests", dependencies: ["Locky", "GuardCore"], path: "Tests/LockyTests"),
    ]
)
