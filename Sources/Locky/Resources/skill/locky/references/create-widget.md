# Create a widget

A widget is a Lua file in your config folder. This guide makes one that shows the days left in the year, checks
it, draws it, and puts it on the lock screen. To have a coding agent do this for you, see [agents.md](agents.md).

The steps use the command line in Locky.app:

```sh
alias locky=/Applications/Locky.app/Contents/MacOS/Locky
```

## 1. Write the file

Make `~/.config/locky/plugin/yearleft.lua`. Locky runs every file in `plugin/` when the screen locks.

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

`init` gets the data and keeps it in `self.state`. `self:every(3600, ...)` runs now and then every hour.
`render` draws what is in `self.state` and returns a view. Keep `render` fast: it has 100 ms.

## 2. Check it

```sh
locky check --widget yearleft
```

`--widget` puts your widget alone in a theme and runs it. The widget's line must say `ok`, and the last line must
say `No problems.`. An error names the file and the line.

## 3. Look at it

```sh
locky render --theme default --widget yearleft --out /tmp/yearleft.png
open /tmp/yearleft.png
```

`render` draws the lock screen to a PNG, with your widget alone in the middle of the theme. Change the file, then
check and render again until the widget looks right. Without `--widget`, `render` draws the whole theme.

## 4. Put it on the lock screen

Open Themes, choose Customize… on a theme, and click Add Widget… (+) in the toolbar. Your widget is in the
gallery with the others. Add it, then drag it to its place.

To add it from `init.lua` instead:

```lua
locky.theme.extend("default", function(theme)
  table.insert(theme.widgets, { "yearleft", anchor = "bottom-right", offset = { -40, -40 } })
end)
```

## Next

- [views.md](views.md): every view and property `render` can use.
- [api.md](api.md): `locky.*`, such as timers, programs, files, and system values.
- [plugins.md](plugins.md): the rules that keep the lock screen safe, and how to share widgets as a plugin.
