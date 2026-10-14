# settings.json

Locky's windows save every change to `~/.config/locky/settings.json` at once. Open at login is not in the file:
macOS keeps it as a login item. init.lua stays yours: the windows never change it, and Settings › Lua Config creates
it only when it is missing.

Locky applies the layers in this order, and a later layer wins key by key:

1. Locky's defaults.
2. `init.lua` and the `plugin/` scripts (`locky.setup`, `locky.theme.extend`, `locky.pack.add`).
3. `settings.json`.

A key that settings.json leaves out keeps init.lua's value. Choosing init.lua's own value in a window removes
the key, so init.lua's value applies again. Hide personal information is the one exception: turning it on always
writes `"privacy": true`, so an init.lua that stops with an error can never turn it off. Packages are the
exception to the order: settings.json's `packs` load before init.lua runs, so init.lua can `require` them. The
other values apply before init.lua runs as well, so the code init.lua runs sees them (with `privacy` on, a module
that reads your name as it loads gets the generic one), and again after the plugin scripts, so they win.

The file is plain JSON with sorted keys, so you can edit it by hand and keep it in your dotfiles; Locky picks up
an edit at once. A symlinked settings.json keeps its link when Locky saves it. Locky writes the file with mode
0600, and a config folder it creates with mode 0700, so only you can read them. If the file has an error, Locky
says so in its windows and in `locky check`, and does not overwrite it.

## Keys

| Key | Value | In the windows |
|---|---|---|
| `theme` | A theme id, such as `"mocha"` | The Themes window (click a theme), or the menu's Themes… |
| `schedule` | `{ "mode": "time", "day": "glass", "night": "default", "day_starts": "07:00", "night_starts": "19:00" }`, or `{ "mode": "appearance", "light": "glass", "dark": "default" }` | Themes › Schedule (the toolbar's clock) |
| `themes` | `{ "<id>": { "background": {…}, "widgets": […], "auth": {…} } }`: see below | Themes › Customize… |
| `packs` | Package specs, as `locky.pack.add` takes them: `"user/repo"`, an `https://`, `ssh://`, or `git@` address, or `{ "src": …, "version": …, "name": …, "allow": ["system", "files"] }` (`allow`: what the plugin may do; see [plugins.md](plugins.md#what-a-plugin-may-do)) | Settings › Plugins › Install Plugin… |
| `message` | A line under the password field | Settings › General › Lock Screen |
| `hour24` | `true` or `false`: a 24- or 12-hour clock in every theme | — (the lock screen follows System Settings › General › Date & Time unless this key or init.lua sets it) |
| `privacy` | `true` hides your name and picture, this Mac's name, its location (the clocks' city and the weather's place), network addresses, agent titles and workspaces, and git repositories, branches, and commit messages. Plugin widgets decide for themselves | Settings › General › Lock Screen › Hide personal information |
| `touch_id` | `false` turns Touch ID off (default `true`) | Settings › General › Unlock |
| `emergency_exit` | `false` stops ⌃⌥⌘Q from switching to the macOS lock screen (default `true`) | — (on unless this key is `false`) |
| `shortcut` | `{ "key": 37, "modifiers": ["control", "option", "command"] }`: a virtual key code (37 is L) and modifiers | Settings › General › Lock Now shortcut |
| `auto_lock` | `{ "idle_minutes": 5, "display_sleep": true, "system_sleep": true, "screen_saver": true }`; a missing key is off. The idle count pauses while a video, a call, or a presentation keeps the display on | Settings › General › Lock Automatically |
| `battery_saver` | `true`: nothing moves on battery either. In Low Power Mode or with Reduce Motion on, nothing moves anyway | — |
| `display_off` | Seconds on the lock screen without input before the displays turn off. It acts only during a lock, and also when the system's display sleep is Never or another app keeps the display on | Settings › General › Lock Screen › Turn the display off |
| `intruder_photo` | Take a camera photo at this many wrong passwords in one lock. Locky keeps the newest 20 photos and deletes those older than 30 days | Settings › General › Unlock › Take a photo |
| `update_check` | `false` stops the daily plugin update check, which fetches and compares commits and runs no plugin code (default `true`) | Settings › Plugins › Check for updates daily |
| `editor`, `terminal` | What "Open in" uses: an app's bundle id, a command (`"nvim"`), or `"default"`; a terminal's bundle id | Settings › Lua Config › Open in |

## Theme changes

`themes.<id>.background` replaces the theme's background with any background table from
[themes.md](themes.md#backgrounds), such as `{ "wallpaper": true, "blur": 30, "dim": 0.25 }`. It wins over
`locky.setup({ background = … })`.

`themes.<id>.widgets` replaces the theme's widget list. An entry with `ref` is the theme's own placement
number `ref`: it keeps that placement's options, and the entry's `anchor`, `offset`, `card`, `size`, `align`,
`display`, and `opts` go on top (its `opts` over `locky.setup({ widgets = … })` too). An entry without `ref`
adds a widget:

```json
"themes": {
  "default": {
    "widgets": [
      { "ref": 2, "widget": "clock", "anchor": "top", "offset": [0, 140] },
      { "widget": "calendar", "anchor": "top-right", "offset": [-32, 32], "card": true }
    ]
  }
}
```

If the theme changes later (a plugin update moves its widgets), an entry finds its placement by widget name,
and an entry whose widget the theme no longer has goes away. A bad entry is reported, and the theme loads
without the change.

`themes.<id>.auth` moves the password field, such as `{ "anchor": "bottom", "offset": [0, -80] }`. The rest of
the field stays the theme's.

## The windows

Locky has three windows: Themes, Settings, and the Welcome. Open the **Themes** window from the menu bar icon
(Themes…), by opening Locky.app again, or with `Locky window themes`. Open the **Settings** window with Settings…
(⌘,) in the menu bar icon's menu or in the Locky menu, or with `Locky window settings`, `plugins`, or `config`
(`dashboard` and `widgets` still work and open the Themes window). While a window is open, Locky shows in the
Dock, and its menus have Lock Now in the Locky menu.

- **Themes:** the theme a lock uses now, live, with its name; then every theme as a picture, by name. Click a
  theme to use it, or use the arrow keys; with a theme schedule on, the change goes to the theme the schedule
  shows now. A theme that failed to load on the last lock shows at the top (and first in the menu bar icon's
  menu) until its files or init.lua change or you dismiss it; Open goes to the line with the error. Schedule
  (the clock in the toolbar) changes the theme by time of day or with Light and Dark mode. Right-click a theme
  you made for Move to Trash.
- **Customize:** Customize… (or Return, or a theme's right-click menu) opens the editor on that theme's live lock
  screen. Click a widget or the password field to select it, and drag it to move it. A widget lands pinned to
  the corner, edge, or center of the part of the screen it is in, so it keeps its place on other screens; View ›
  Show Grid shows a 30-point grid and snaps what you drag to it. The arrow keys move what is selected a point (a
  grid step with Shift), Delete removes a selected widget, and Escape clears the selection; a second Escape
  returns to the themes. The inspector shows what is selected: where it is pinned (Reset puts it back where the
  theme has it), its size, its card, and its options. With nothing selected, it shows the background, the widget
  list, and the password field. Add Widget… (+) opens a live gallery of the widgets, in each of their sizes.
  The More menu (and the File menu) has Duplicate Theme…, Export Theme…, Revert to Original, and, for a theme you
  made, Move to Trash (see [themes.md](themes.md#make-and-share-themes-in-the-window)). Edit › Undo (⌘Z) takes
  back each change, and Redo (⇧⌘Z) makes it again. Done returns to the themes.
- **Settings › General:** Open at login, the Lock Now shortcut, Lock Automatically, the lock screen message, Hide
  personal information, Turn the display off, Touch ID, and Take a photo; photos taken after wrong passwords show
  at the top. The Lock Automatically footer says that you may unlock twice when macOS also asks for your password
  after the display turns off.
- **Settings › Plugins:** install from git; Update… on a plugin shows its new commits and diffstat and installs
  exactly those commits; Run programs and Change files allow a plugin added here to do that; Check for updates
  daily checks in the background, and Check Now checks at once. Each plugin shows the themes and widgets it adds.
- **Settings › Lua Config:** init.lua with Open in your editor and Show in Finder, the log, and the config's
  problems, each with Open at its line. What the windows change is saved to settings.json, next to init.lua, and
  wins over it.
- **Welcome:** a window of its own. It opens by itself on the first launch, and from Help › Welcome to Locky
  after that: a live preview and Lock Now, then a switch for auto-lock and one for Open at login. Done closes it.
