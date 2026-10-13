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

The menu bar icon has Lock Now, the theme picker, Preview Theme, and Settings…, which opens Locky's window at
its Settings page.

## Themes

![The built-in themes](docs/gallery.png)

Twenty-eight themes ship with Locky. Each is a package in `Sources/Locky/Resources/packages/<id>/` (Aurora, the
default, lives in the core runtime) with its own widgets, shaders, and a README with its options. The last eight
are live wallpapers, after the most popular scenes on Wallpaper Engine's Steam Workshop, drawn entirely in Metal.

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
| Tokyo Night | `tokyonight` | The hyprlock look: hours over minutes in two colors, status in the corners. |
| Gruvbox | `gruvbox` | A conky sidebar of system stats beside a big clock, in Gruvbox colors. |
| Observatory | `observatory` | Stars and the Milky Way over a dome; tonight's moon and the sun's path. |
| Mission | `mission` | Flight control: mission elapsed time, clocks, telemetry, and progress rings. |
| Pocket | `pocket` | A handheld LCD game: a pixel clock, hearts, a score, and the Game of Life. |
| Bauhaus | `bauhaus` | A 1923 poster in primary shapes; a notch in the red circle sweeps the seconds. |
| Memento | `memento` | Day 286 of 365: a dot for every day of the year, and a stoic quote. |
| Rainy | `rainy` | Rain sliding down a window over city lights; the time in words. |
| Matrix | `matrix` | Digital rain, a glowing clock, and "Wake up, Neo…" typed in the corner. |
| Notebook | `notebook` | A ruled notebook page: your todo.txt by hand, a sticky note, a coffee ring. |
| Event Horizon | `eventhorizon` | A black hole's turning accretion disk, its light bent around the shadow. |
| Galaxy Sea | `galaxysea` | The Milky Way mirrored in a calm sea, a small boat on the horizon, meteors. |
| Liquid | `liquid` | Color folding into color like silk; a big clock and a row of glass widgets. |
| Neon City | `neoncity` | A rainy city at 2 AM: towers drifting past, neon signs, a neon clock. |
| Sakura | `sakura` | A cherry branch under the moon, falling petals, the month's old Japanese name. |
| Deep Blue | `deepblue` | Underwater light rays and plankton, and a humpback gliding past. |
| Lookout | `lookout` | Firewatch-style ridges and a fire lookout, lit by the real time of day. |
| Snowfall | `snowfall` | Snow falling on a pine forest at night, a cabin with warm windows. |

Pick one in the menu's Theme submenu, or in `init.lua` with `locky.setup({ theme = "station" })`.
`Scripts/snapshot.sh <id> out.png [1728x1117]` renders any theme to a PNG.

## The window

Settings… (⌘,) in the menu opens Locky's window: a live dashboard, a theme editor (drag widgets on the live
preview, with a grid to snap to; change a widget's options, the background, and where the password field sits),
every widget drawn live with Install Widgets…, plugins (install, update, remove), the config with Open in your
editor, and settings such as the Lock Now shortcut, auto-lock, Open at Login, a lock screen message, privacy mode,
a theme schedule, the battery saver, and a photo after wrong passwords. It saves to
`~/.config/locky/settings.json`, which wins over init.lua key by key: see [settings.md](docs/settings.md).

## Configure

`~/.config/locky/init.lua` (the window's Lua Config page creates it with examples):

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
locky pack check                  which plugins have updates; installs none
locky login [on|off]              open Locky at login, or not
locky preview --theme NAME        the lock screen in a window
locky window [SECTION]            the Locky window, at a page
```

## Docs

- [plugins.md](docs/plugins.md): the plugin system, widgets, packages, health, and the safety rules
- [views.md](docs/views.md): every view and property widgets can draw
- [widgets.md](docs/widgets.md): the core widgets and their options
- [themes.md](docs/themes.md): themes, backgrounds, and shaders
- [api.md](docs/api.md): the `locky` API
- [settings.md](docs/settings.md): settings.json, which the window writes, and how it layers over init.lua

## Layout

```
Sources/CLua/                 Lua 5.5.1 (unmodified) and locky_bridge.c: time budgets, memory limit, safe calls
Sources/Locky/Lua/            the runtime: LuaVM, LuaRuntime, the runtime path, system information
Sources/Locky/Views/          views, themes, backgrounds, widget hosts, the password field
Sources/Locky/Window/         the Locky window: dashboard, theme editor, plugins, config, settings
Sources/Locky/Settings/       settings.json, its store, and the theme schedule
Sources/Locky/System/         the shortcut, auto-lock, login item, power, camera, and editors
Sources/Locky/Resources/
  runtime/                    lua/locky (core, ui), plugin/ (core widgets), themes/, shaders/, types/
  packages/                   the built-in theme packages, one folder each
Scripts/                      packaging, snapshot.sh (a theme to PNG), window-shot.sh (a window page to PNG),
                              thumbnails.sh (the theme thumbnails), make_icon.swift (the app icon)
Tests/LockyTests/             the test suite
```
