---
name: locky
description: Makes and changes Locky lock screen widgets and themes, the Lua files in ~/.config/locky. Use when the user asks for a Locky widget, a Locky theme, a change to either, or help with an error in init.lua or a Locky plugin.
---

# Locky widgets and themes

Locky is a macOS lock screen app. Its widgets and themes are Lua files that you write; Locky draws them. You
check your work with Locky's command line: `check` runs the files and lists errors, and `render` draws the lock
screen to a PNG that you look at.

## Find Locky

The command line is the app's own binary:

```sh
LOCKY=/Applications/Locky.app/Contents/MacOS/Locky
# Not there? Find the app: mdfind 'kMDItemCFBundleIdentifier == "com.tornikegomareli.Locky"'
"$LOCKY" help
```

## The config folder

`$LOCKY_CONFIG_DIR` when set, else `$XDG_CONFIG_HOME/locky`, else `~/.config/locky`:

| Path | What |
|---|---|
| `init.lua` | The user's config. Runs first, each time the screen locks. |
| `plugin/<name>.lua` | Scripts that run at startup: put widget definitions here, one file per widget. |
| `themes/<id>.lua` | Themes, one file each. The file name is the theme's id. |
| `shaders/<name>.metal` | Background shaders. |
| `settings.json` | Written by Locky's windows. Read it; leave changes to the windows. |

## Write

- **A widget** is `locky.widget.define(name, spec)` in `plugin/<name>.lua`. `render` returns a view built with
  `locky.ui`; `init` fetches data with timers and keeps it in `self.state`. Read
  [references/plugins.md](references/plugins.md) (A widget, and the safety rules),
  [references/views.md](references/views.md) (every view and property), and [references/api.md](references/api.md)
  (`locky.*`) before you write one.
- **A theme** is `themes/<id>.lua` returning a table: palette, font, background, card, password field, and
  widget placements. Read [references/themes.md](references/themes.md) before you write one, and
  [references/widgets.md](references/widgets.md) for the widgets every theme can place.

A minimal widget, `plugin/yearleft.lua`:

```lua
local ui = locky.ui

locky.widget.define("yearleft", {
  description = "Days left in the year",
  card = true,
  init = function(self)
    self:every(3600, function(self)
      local now = os.date("*t")
      local last = os.time({ year = now.year, month = 12, day = 31, hour = 23 })
      self:set({ days = (last - os.time()) // 86400 })
    end)
  end,
  render = function(self)
    if not self.state.days then return nil end
    return ui.vstack {
      spacing = 2,
      ui.text(self.state.days, { size = 34, weight = "semibold", mono = true }),
      ui.text("days left this year", { size = 12, color = "muted" }),
    }
  end,
})
```

A minimal theme, `themes/dusk.lua`, that places it:

```lua
return {
  name = "Dusk",
  description = "A violet evening, a large clock, and the days left in the year.",
  palette = { bg = "#1b1530", fg = "#f4ecff", muted = "#f4ecff99", accent = "#ff8a5c" },
  font = { design = "rounded" },
  background = { gradient = { "#1b1530", "#4a2a5e" }, angle = 180, noise = 0.04 },
  card = { style = "glass", radius = 18 },
  auth = { style = "pill", anchor = "bottom", offset = { 0, -80 } },
  widgets = {
    { "clock", anchor = "center", offset = { 0, -60 }, opts = { size = 140, weight = "light" } },
    { "date", anchor = "center", offset = { 0, 40 }, opts = { color = "muted" } },
    { "yearleft", anchor = "bottom-right", offset = { -40, -40 } },
  },
}
```

Rules that keep the lock screen safe, from [references/plugins.md](references/plugins.md):

- `render` takes at most 100 ms and never waits: fetch data in `init` with `self:every`, `self:after`, or
  `self:system`, keep it in `self.state`, and draw it in `render`.
- Run programs with `locky.system` or `self:system`, which never block. `os.execute`, `io.popen`, and `os.exit`
  are not there.
- A widget that fails three times in a row, or runs past its budget once, stops.
- Names, places, and other personal data hide when `locky.config.privacy` is true.

## Check

Repeat this loop until both checks pass:

1. Run the files: `"$LOCKY" check --theme <id>`. For a widget, also `"$LOCKY" check --widget <name>`: `check` runs
   only the widgets a theme places, and `--widget` puts yours alone in the theme (default unless `--theme` names
   one). Every widget must say `ok` and the last line must say `No problems.`. Fix each error it lists.
2. Draw the lock screen: `"$LOCKY" render --theme <id> --out /tmp/locky-<id>.png`. For a widget alone, in the
   middle of a theme: `"$LOCKY" render --theme <id> --widget <name> --out /tmp/locky-<name>.png`.
3. Open the PNG and look at it. A widget that fails shows its error in red in its place. Fix what you see:
   text that is cut off, overlaps, low contrast, a widget in the wrong place, an empty space where data should be.

`render` turns privacy mode on, needs no permission, and opens no window. `--size 1728x1117` tries another
screen; `--appearance light` or `dark` tries the other system appearance. Themes lay out for 1440×900.

`Locky lock` locks the user's Mac and `Locky preview` opens a window: use `render` instead of both.

## Hand over

Tell the user the files you wrote. The lock screen picks them up at the next lock. A new widget shows in
Locky's Customize › Add Widget…, where the user places it in any theme. To show it in their current theme without
Customize, add it from `init.lua` when the user asks:

```lua
locky.theme.extend("default", function(theme)
  table.insert(theme.widgets, { "yearleft", anchor = "bottom-right", offset = { -40, -40 } })
end)
```

`"$LOCKY" check` with no `--theme` names the current theme on its first line.
