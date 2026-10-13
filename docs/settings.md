# settings.json

The Locky window saves every change to `~/.config/locky/settings.json` at once. init.lua stays yours: the
window only reads it.

Locky applies the layers in this order, and a later layer wins key by key:

1. Locky's defaults.
2. `init.lua` and the `plugin/` scripts (`locky.setup`, `locky.theme.extend`, `locky.pack.add`).
3. `settings.json`.

A key that settings.json leaves out keeps init.lua's value. For the values Lua reads too, the Settings page
shows init.lua's value until you change it there, and then offers a Reset that removes the key. Packages
are the exception to the order: settings.json's `packs` load before init.lua runs, so init.lua can
`require` them. The other values apply before init.lua runs as well, so the code init.lua runs sees them
(with `privacy` on, a module that reads your name as it loads gets the generic one), and again after the
plugin scripts, so they win.

The file is plain JSON with sorted keys, so you can edit it by hand and keep it in your dotfiles; the
window picks up an edit at once. A symlinked settings.json keeps its link when the window saves. If the file
has an error, Locky says so in the window and in `locky check`, and does not overwrite it.

## Keys

| Key | Value | In the window |
|---|---|---|
| `theme` | A theme id, such as `"mocha"` | Themes › Use This Theme, or the menu |
| `schedule` | `{ "mode": "time", "day": "glass", "night": "default", "day_starts": "07:00", "night_starts": "19:00" }`, or `{ "mode": "appearance", "light": "glass", "dark": "default" }` | Settings › Theme Schedule |
| `themes` | `{ "<id>": { "background": {…}, "widgets": […], "auth": {…} } }`: see below | Themes › Background and Widgets |
| `packs` | Package specs, as `locky.pack.add` takes them: `"user/repo"`, an `https://`, `ssh://`, or `git@` address, or `{ "src": …, "version": …, "name": …, "allow": ["system", "files"] }` (`allow`: what the plugin may do; see [plugins.md](plugins.md#what-a-plugin-may-do)) | Plugins › Install |
| `message` | A line under the password field | Settings › Lock Screen |
| `hour24` | `true` or `false`: a 24- or 12-hour clock in every theme | Settings › Lock Screen |
| `privacy` | `true`: no agent titles or workspaces, no name, picture, or computer name | Settings › Lock Screen |
| `auto_unlock` | Seconds until the prototype's lock opens by itself; `0` turns it off | Settings › Unlock |
| `touch_id` | `false` turns Touch ID off (default `true`) | Settings › Unlock |
| `emergency_exit` | `false` stops ⌃⌥⌘Q from quitting (default `true`) | Settings › Unlock |
| `shortcut` | `{ "key": 37, "modifiers": ["control", "option", "command"] }`: a virtual key code (37 is L) and modifiers | Settings › General |
| `auto_lock` | `{ "idle_minutes": 5, "display_sleep": true, "system_sleep": true, "screen_saver": true }`; a missing key is off | Settings › Lock Automatically |
| `battery_saver` | `true`: on battery or in Low Power Mode, nothing moves | Settings › Power |
| `display_off` | Seconds on the lock screen without input before the displays turn off | Settings › Power |
| `intruder_photo` | Take a camera photo at this many wrong passwords in one lock | Settings › Security |
| `update_check` | `false` stops the daily plugin update check, which fetches and compares commits and runs no plugin code (default `true`) | Settings › Plugins |
| `editor`, `terminal` | What "Open in" uses: an app's bundle id, a command (`"nvim"`), or `"default"`; a terminal's bundle id | Config › Open in |

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

## The window

Open it from the menu (Settings… ⌘,), by opening Locky.app again, or with
`Locky window [dashboard|themes|plugins|config|settings]`. While it is open, Locky shows in the Dock.

- **Dashboard:** the theme a lock uses now, live, with Lock Now; the config's problems, plugins and
  updates, auto-lock, unlock, and the lock screen's changes at a glance; and any photos taken after wrong
  passwords.
- **Themes:** every theme, and the selected one in the editor. Its live preview is a canvas: click a widget or
  the password field to select it, and drag it to move it. A widget lands pinned to the corner, edge, or center
  of the part of the screen it is in, so it keeps its place on other screens; the Grid button shows a 30-point
  grid and snaps what you drag to it. The panel beside the canvas shows what is selected: its place, its card,
  and its options (a menu where the widget lists the values an option takes). With nothing selected, it shows
  the background, the widget list, Add Widget, and Reset Layout.
- **Widgets:** every widget, live. Click one to add it to the active theme, or under Add to, to another; the
  Themes page then opens on that theme. Install Plugin… adds more.
- **Plugins:** install from git; Update All… shows each update's commits and diffstat and installs exactly those
  commits; Run programs and Change files allow a plugin added here to do that; More › Remove Unused… lists the
  folders it deletes and asks first. Each plugin shows the themes and widgets it adds.
- **Config:** init.lua and settings.json, read-only, with problems on their lines and Open in your editor.
- **Settings:** everything in the table above.
