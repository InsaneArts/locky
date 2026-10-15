# settings.json

Locky's windows save every change to `~/.config/locky/settings.json` at once. Open at login is not in the file:
macOS keeps it as a login item. init.lua stays yours: the windows never change it, and Settings › General › Config
folder creates it only when it is missing.

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
| `schedule` | `{ "mode": "time", "day": "glass", "night": "default", "day_starts": "07:00", "night_starts": "19:00" }`, or `{ "mode": "appearance", "light": "glass", "dark": "default" }` | Themes › Schedule (the toolbar's clock, or File › Schedule Themes…) |
| `themes` | `{ "<id>": { "background": {…}, "palette": {…}, "font": {…}, "card": {…}, "widgets": […], "auth": {…} } }`: see below and [themes.md](themes.md#make-and-share-themes-in-the-window) | Themes › Customize… |
| `packs` | Package specs, as `locky.pack.add` takes them: `"user/repo"`, an `https://`, `ssh://`, or `git@` address, or `{ "src": …, "version": …, "name": …, "allow": ["system", "files"] }` (`allow`: what the plugin may do; see [plugins.md](plugins.md#what-a-plugin-may-do)) | Settings › Plugins › Install Plugin… |
| `message` | A line under the password field | Settings › General › Lock Screen |
| `hour24` | `true` or `false`: a 24- or 12-hour clock in every theme | — (the lock screen follows System Settings › General › Date & Time unless this key or init.lua sets it) |
| `privacy` | `true` hides your name and picture, this Mac's name, its location (the clocks' city and the weather's place), network addresses, agent titles and workspaces, and git repositories, branches, and commit messages. Plugin widgets decide for themselves | Settings › General › Lock Screen › Hide personal information |
| `touch_id` | `false` turns Touch ID off (default `true`) | Settings › General › Unlock |
| `emergency_exit` | `false` stops ⌃⌥⌘Q from switching to the macOS lock screen (default `true`) | — (on unless this key is `false`) |
| `lock_key` | `true`: the Touch ID button shows Locky's lock instead of the macOS lock screen (default `false`). Needs Accessibility access; see [security.md](security.md#what-locky-guarantees) | Settings › General › Lock with the Touch ID button |
| `shortcut` | `{ "key": 37, "modifiers": ["control", "option", "command"] }`: a virtual key code (37 is L) and modifiers | Settings › General › Lock Now shortcut |
| `auto_lock` | `{ "idle_minutes": 5, "display_sleep": true, "system_sleep": true, "screen_saver": true }`; a missing key is off. Locky treats `display_sleep` and `screen_saver` as one: when either is `true`, it locks on both. The idle count pauses while a video, a call, or a presentation keeps the display on | Settings › General › Lock Automatically (one switch, "When the screen saver starts or the display turns off", for both keys) |
| `battery_saver` | `true`: nothing moves on battery either. In Low Power Mode or with Reduce Motion on, nothing moves anyway | — |
| `lock_animation` | How a lock comes in and goes out: `"fade"`, `"focus"` (the default), `"iris"`, `"lift"`, `"sweep"`, `"dissolve"`, `"tiles"`, or `"none"`. Fade: the lock fades in and out. Focus: the lock grows sharp from a little larger, and grows as it goes. Iris: it opens from the middle of the screen, and out from the password field. Lift: it comes down from above the screen, and lifts up off it. Sweep: a wide soft edge crosses the screen in the reading direction. Dissolve: it forms out of large soft clouds, and clears outward from the password field. Tiles: hexagons appear from the middle, and go from the password field. `true` from an older Locky is Focus, `false` is none, and a name Locky does not know is Focus. The lock comes in animated after Lock Now and after inactivity. A lock when the display turns off, the screen saver starts, or the Mac sleeps covers the screen at once. The lock goes out animated only after your password or Touch ID. With Reduce Motion on, every style is Fade | Settings › General › Lock Screen › Lock animation |
| `display_off` | Seconds on the lock screen without input before the displays turn off. It acts only during a lock, and also when the system's display sleep is Never or another app keeps the display on | Settings › General › Lock Screen › Turn the display off |
| `intruder_photo` | Take a camera photo at this many wrong passwords in one lock. Locky keeps the newest 20 photos and deletes those older than 30 days | Settings › General › Unlock › Take a photo |
| `update_check` | `false` stops the daily plugin update check, which fetches and compares commits and runs no plugin code (default `true`) | Settings › Plugins › Check for updates daily |
| `editor`, `terminal` | What "Open in" uses: an app's bundle id, a command (`"nvim"`), or `"default"`; a terminal's bundle id | Settings › General › Customization › Config folder › Open in |

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
  theme to use it, or use the arrow keys. With a theme schedule on, the choice replaces the schedule's day or
  night theme, or its light or dark mode theme, whichever applies now. A theme that failed to load on the last
  lock shows at the top (and first in the menu bar icon's menu) until its files or init.lua change or you dismiss
  it; Open goes to the line with the error. When the theme in use does not load, the top says why, with Open at
  the file and line. Schedule (the clock in the toolbar, or File › Schedule Themes…) changes the theme by time of
  day or with Light and Dark mode. New Theme… (+ in the toolbar, File › New Theme…, or ⌘N) makes "Untitled Theme"
  from a blank one and opens Customize on it ([create-theme.md](create-theme.md)). Right-click a theme you made for
  Move to Trash.
- **Customize:** Customize… (or Return, or a theme's right-click menu) opens the editor on that theme's live lock
  screen. Click a widget or the password field to select it, and drag it to move it. A widget lands pinned to
  the corner, edge, or center of the part of the screen it is in, so it keeps its place on other screens; View ›
  Show Grid shows a 30-point grid and snaps what you drag to it. The arrow keys move what is selected a point (a
  grid step with Shift), Delete removes a selected widget, and Escape clears the selection; a second Escape
  returns to the themes. The inspector shows what is selected: where it is pinned (Reset puts it back where the
  theme has it), its size, its card, and its options. With nothing selected, it shows the background, the widget
  list, and the password field, and under the background, the theme's Colors and Font; a theme you made with
  New Theme… also shows its Name there. Add Widget… (+) opens a live gallery of the widgets, in each of their sizes.
  The More menu (and the File menu) has Duplicate Theme…, Export Theme…, Revert to Original, and, for a theme you
  made, Move to Trash (see [themes.md](themes.md#make-and-share-themes-in-the-window)). Edit › Undo (⌘Z) takes
  back each change, and Redo (⇧⌘Z) makes it again. Done returns to the themes. For a theme that does not load,
  Customize shows why, with Open at the file and line.
- **Settings › General:** Open at login, the Lock Now shortcut, Lock with the Touch ID button, Lock Automatically, the lock screen message, Hide
  personal information, Lock animation, Turn the display off, Touch ID, and Take a photo; photos taken after wrong
  passwords show at the top. Under Lock animation, a small preview plays the chosen style on the theme in use, over
  your desktop picture, while the Settings window is in front. With Reduce Motion on, it shows a still picture and
  says that Locky uses Fade. The Lock Automatically footer says that you may unlock twice when
  macOS also asks for your password after the display turns off. The last section, Customization, has:
  - **Config folder:** its path, and Open in your editor for init.lua. The button's menu chooses the editor (and
    the terminal for a terminal editor) and has Show in Finder. Without init.lua, Create init.lua makes one with
    examples.
  - each problem in init.lua and the plugin scripts, with Open at its file and line. A theme that does not load
    says why in the Themes window.
  - **Themes:** New Theme… makes a theme.
  - **Widgets:** New Widget… explains that a coding agent writes widgets, with the agent skill, an example prompt
    to copy, and Widget Guide ([create-widget.md](create-widget.md)).
  - **Agent skill:** the agents that have Locky's skill. Install copies it, Update replaces an older copy, and Show
    in Finder shows the copies. See [agents.md](agents.md).
  - **Log:** Open shows `~/Library/Logs/Locky/locky.log`: what plugins print, and every error.
- **Settings › Plugins:** install from git; Update… on a plugin shows its new commits and diffstat and installs
  exactly those commits; Run programs and Change files allow a plugin added here to do that; Check for updates
  daily checks in the background, and Check Now checks at once. The footer says Up to date only after a check that
  reached the plugins and found each at its newest commit. Each plugin shows the themes and widgets it adds.
- **Welcome:** a window of its own. It opens by itself on the first launch, and from Help › Welcome to Locky
  after that. It has three pages: a live preview and Lock Now; Lock automatically, Open at login, the Lock Now
  shortcut, Lock with the Touch ID button, and Accessibility; and what happens if something goes wrong. Done closes it.
