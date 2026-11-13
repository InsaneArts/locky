# Locky for coding agents

Locky locks the Mac, so a broken change can lock someone out or leave their Mac open. Verify a change before you call
it done. README.md has the build commands and the folder layout. docs/ is the public Lua API: third-party plugins,
themes, and packs depend on it, and on the formats of settings.json and the theme files.

## Verify

- `swift test`: the whole suite, about 30 seconds. `TransitionRenderTests.framesShowTheDesktopThenTheScene` fails now
  and then with no change (the first frame of a way out); run it again before you suspect your change.
- A theme or a widget: `locky check --theme ID`, then `locky render --theme ID --out x.png`, and look at the picture.
  From the source tree: `LOCKY_RESOURCES=$PWD/Sources/Locky/Resources .build/debug/Locky check --theme ID`.
- A window: `INSTALL=0 Scripts/package_app.sh`, then `Scripts/window-shot.sh themes out.png`, and look at the picture.
  Only the packaged app has the Liquid Glass look (package_app.sh names the SDK in the binary); `swift build` and the
  tests draw windows as macOS 15 does. The Themes window follows Scene's look (~/Development/Scene): Design.swift has
  the shared pieces.
- Work on your own config folder: `LOCKY_CONFIG_DIR=$(mktemp -d)`. ~/.config/locky is the owner's.
- The lock itself (the keyboard, Touch ID, the hand-over to the macOS lock screen) has tests for its parts only:
  ask the owner to lock and unlock on a real Mac.

## Invariants

- A lock never waits for Lua. The shield and the password field show at once, and widgets fill in when Lua answers.
  Lua runs on its own queue (LuaRuntime), with time budgets and a memory limit; a file whose open would block (a pipe,
  a device) is refused.
- A lock holds the keyboard, or hands over to the macOS lock screen (LockSession.checkKeyboard). During a hand-over
  nothing takes the keyboard; after one that fails, the lock asks for it again. It hands over too when another app's
  window shows above it (watchWindowsAbove): macOS draws its accessory prompt above every app.
- locky-guard locks the Mac with the macOS lock screen if Locky dies or hangs during a lock.
- Locky updates itself with Sparkle (System/Updater.swift). No check starts during a lock, and a tool run starts no
  updater. Scripts/release.sh makes a release, and docs/release.md has the steps: ask the owner before you publish one.
- settings.json is written atomically, and only when it reads without an error. A broken file stays as it is, and
  Locky goes on with the last good settings (~/Library/Application Support/Locky/settings-last-good.json).
- Tool runs (`LOCKY_RESOURCES` set, or `--behind`) have no location, and render, thumbnails, and screenshots use
  privacy mode: no picture shows a name or where the Mac is.

## Where things live

In Sources/Locky:

- LockSession.swift: a lock's or a preview's whole life, on the main actor. LockScreenView draws one display.
- Lua/LuaRuntime.swift: the Lua state, its natives, timers, and processes. Resources/runtime/lua/locky/_core.lua is the
  Lua side of the same API, and its checks (grants, files, time) are part of the security model.
- Views/ draws the lock. Window/ is the Themes, Settings, and Welcome windows, with AppModel as their state.
- Settings/ reads and writes settings.json. System/ is the macOS side: the shortcut, auto-lock, power, permissions.
