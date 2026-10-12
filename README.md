# Locky

A lock screen for macOS that you build like a Neovim config: themes and widgets are Lua plugins, drawn
natively with SwiftUI and Metal.

> Prototype. While the screen is locked, the system lock is off; Locky unlocks with Touch ID or your login
> password. For now the lock opens by itself after 60 seconds (`auto_unlock`), and ⌃⌥⌘Q quits it.

## Build

```sh
Scripts/package_app.sh            # builds Locky.app and installs it in /Applications
open Locky.app                    # the lock icon appears in the menu bar
swift test                        # the test suite
```

The menu bar icon has Lock Now, Preview, the theme picker, plugin commands, and Check Config.

## Themes

![The ten built-in themes](docs/gallery.png)

Ten themes ship with Locky. Each is a package in `Sources/Locky/Resources/packages/<id>/` (Aurora, the
default, lives in the core runtime) with its own widgets, shaders, and a README with its options.

| Theme | id | Look |
|---|---|---|
| Aurora | `default` | Northern lights over mountains and a still lake; a thin clock. |
| Glass | `glass` | Your wallpaper, a huge clock, and glass gauges; the password field appears when you type. |
| Station | `station` | A Swiss railway clock on warm gray, with a platform sign and your next "departure". |
| Poster | `poster` | International Typographic Style: giant cropped hours, red minutes overprinting them. |
| Departures | `departures` | A flip clock and a split-flap board of your herdr agents. |
| Word Clock | `wordclock` | An 11×10 letter grid that spells the time (English). |
| Phosphor | `phosphor` | An amber CRT terminal: shell session, block clock, system info, scanlines. |
| Mocha | `mocha` | Catppuccin Mocha with an i3lock-style ring around the clock. |
| Dot Matrix | `dotmatrix` | A 5×7 dot-matrix clock on a ghost grid, with one red accent. |
| Synthwave | `synthwave` | A neon sunset over a perspective grid, with a chrome clock. |

Pick one in the menu's Theme submenu, or in `init.lua` with `locky.setup({ theme = "station" })`.
`Scripts/snapshot.sh <id> out.png [1728x1117]` renders any theme to a PNG.

## Configure

`~/.config/locky/init.lua` (the menu's Open Config Folder creates it with examples):

```lua
locky.setup({ theme = "default", palette = { accent = "#ff79c6" } })
locky.pack.add({ "someone/locky-weather" })
```

The same binary is a command line (`Locky.app/Contents/MacOS/Locky`):

```
locky check [--theme NAME]        run your config, plugins, and a theme; list every error
locky health                      like :checkhealth
locky themes | widgets            what is installed
locky pack list|sync|update|clean plugins from git, pinned by locky-pack-lock.json
locky preview --theme NAME        the lock screen in a window
```

## Docs

- [plugins.md](docs/plugins.md): the plugin system, widgets, packages, health, and the safety rules
- [views.md](docs/views.md): every view and property widgets can draw
- [themes.md](docs/themes.md): themes, backgrounds, and shaders
- [api.md](docs/api.md): the `locky` API

## Layout

```
Sources/CLua/                 Lua 5.5.1 (unmodified) and locky_bridge.c: time budgets, memory limit, safe calls
Sources/Locky/Lua/            the runtime: LuaVM, LuaRuntime, the runtime path, system information
Sources/Locky/Views/          views, themes, backgrounds, widget hosts, the password field
Sources/Locky/Resources/
  runtime/                    lua/locky (core, ui), plugin/ (core widgets), themes/, shaders/, types/
  packages/                   the built-in theme packages, one folder each
Scripts/                      packaging, snapshot.sh (render a theme to PNG)
Tests/LockyTests/             the test suite
```
