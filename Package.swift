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
    dependencies: [
        // The permission flow (System Settings deep links, the floating drag panel, and status reads that never prompt).
        // Pinned to a version whose source was read; MIT, see docs/security.md.
        .package(url: "https://github.com/jaywcjlove/PermissionFlow.git", exact: "2.11.3"),
        // Updates: Sparkle checks the release feed and installs a new Locky only if its EdDSA signature matches the key
        // in the app. Pinned exactly; it ships as Sparkle's own signed binary framework. MIT, see docs/security.md.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0"),
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
        .executableTarget(name: "Locky", dependencies: [
            "CLua", "GuardCore",
            .product(name: "PermissionFlow", package: "PermissionFlow"),
            .product(name: "PermissionFlowCameraStatus", package: "PermissionFlow"),
            .product(name: "SystemSettingsKit", package: "PermissionFlow"),
            .product(name: "Sparkle", package: "Sparkle"),
        ], path: "Sources/Locky", exclude: ["Resources"]),
        // Fixtures: replies saved from the services widgets call, read by path.
        .testTarget(name: "LockyTests", dependencies: ["Locky", "GuardCore"], path: "Tests/LockyTests", exclude: ["Fixtures"]),
    ]
)
