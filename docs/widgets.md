# Core widgets

Every theme can use these. Place one in a theme or from `init.lua`:

```lua
locky.theme.extend("default", function(theme)
  table.insert(theme.widgets, { "weather", anchor = "top-right", offset = { -40, 40 }, opts = { style = "hero" } })
end)
```

Every core widget also draws Apple's widget families: give a placement `family = "small"` (or `circular`,
`rectangular`, `inline`, `medium`, `large`) and it lays itself out like Apple's own widget of that size, on the
theme's card ([themes.md](themes.md) lists the sizes). Customize › Add Widget… shows each family live, in the
theme you edit.

| Widget | Families |
|---|---|
| `agents` | inline, circular, rectangular, small, medium, large |
| `analog` | circular, small |
| `away` | inline, circular, rectangular, small |
| `battery` | inline, circular, rectangular, small, medium |
| `calendar` | circular, rectangular, small, medium, large |
| `clock` | inline, circular, rectangular, small, medium |
| `countdown` | inline, circular, rectangular, small |
| `date` | inline, small |
| `disk` | inline, circular, rectangular, small, medium |
| `fetch` | inline, rectangular, small, medium, large |
| `fuzzy` | inline, rectangular, small, medium |
| `git` | inline, rectangular, small, medium, large |
| `greeting` | inline, rectangular |
| `keyboard` | inline, circular |
| `life` | small, medium, large |
| `moon` | inline, circular, rectangular, small, medium |
| `nerdclock` | circular, rectangular, small, medium |
| `network` | inline, circular, rectangular, small, medium |
| `progress` | inline, circular, rectangular, small, medium |
| `quote` | medium, large |
| `sun` | inline, circular, rectangular, small, medium |
| `system` | inline, circular, rectangular, small, medium |
| `top` | inline, rectangular, small, medium, large |
| `uptime` | inline, circular |
| `weather` | inline, circular, rectangular, small, medium, large |
| `worldclock` | inline, circular, rectangular, small, medium |

Options go in `opts`; `locky.setup({ widgets = { weather = { units = "metric" } } })` sets them for every theme.
Most widgets also take `size` (the text size) and `color` (a palette role or a color). The comment at the top of
each file in `Sources/Locky/Resources/runtime/plugin/` lists every option.

## Time

| Widget | Shows | Options |
|---|---|---|
| `clock` | The time, large. | `format` (`"time"` or a pattern such as `"HH:mm"`), `size`, `weight`, `font`, `stacked` (hours above minutes) |
| `date` | Today's date. | `format` (`"date"` or a pattern such as `"EEEE d MMMM"`), `case` |
| `analog` | An analog clock. | `style`: `minimal`, `railway`, `braun`; `seconds`; colors `face`, `hands`, `ticks`, `second` |
| `fuzzy` | The time in words: "it's ten past four". English. | `case`: `lower`, `upper`, `title`; `prefix` |
| `worldclock` | The time in other cities, with the difference from here. | `zones = { { "Tokyo", "Asia/Tokyo" }, ... }`; `style`: `rows`, `columns` |
| `nerdclock` | A binary clock, the time as a hex color, Unix time, or Swatch .beat. | `style`: `binary`, `hex`, `unix`, `beat`; `seconds` |
| `calendar` | This month, today marked. | `title`, `today_color` |
| `progress` | How much of the day, week, month, and year has gone. | `style`: `bars`, `rings`, `dots` (a dot per day of the year), `text`; `show` |
| `countdown` | Days until a date, or since one. | `to = "2026-12-25"` (default: New Year), `since`, `label`; `style`: `big`, `line` |
| `away` | When the screen locked, how long ago, and wrong passwords since. | `style`: `line`, `stack` |

## Sky

| Widget | Shows | Options |
|---|---|---|
| `weather` | The weather from [wttr.in](https://wttr.in), which needs no key; kept for 30 minutes. | `style`: `line`, `hero`, `detail`, `forecast` (three days); `location` (default: wttr.in's guess from your address); `units`: `metric`, `imperial` (default: your region's); `place` |
| `sun` | Today's path of the sun, where it is now, and sunrise and sunset (from wttr.in). | `width`, `location` |
| `moon` | Tonight's phase, how much is lit, and the days to the full moon. No network. | `style`: `full`, `symbol`, `row`; `size` |

The weather and sun widgets share one request, cached in `~/Library/Caches/Locky`. Hide personal information
(`privacy`) leaves out the place's name.

## System

| Widget | Shows | Options |
|---|---|---|
| `battery` | Charge, and time left or charging. | `style`: `row`, `compact`, `ring`; `low` |
| `system` | CPU and memory. | `style`: `rings`, `bars`, `chart`, `text` |
| `disk` | How full the disk is. | `style`: `ring`, `bar`, `text`; `path`; `warn` |
| `network` | The connection, its address, and its speed down and up. | `style`: `line`, `chart`; `every` |
| `top` | The programs using the most CPU or memory. | `rows`, `sort`: `cpu`, `memory` |
| `fetch` | neofetch: user@host, macOS, the model, uptime, chip, memory, and the palette's colors. | `logo` (false hides the padlock), `colors`, `fields` |
| `uptime` | How long the Mac has been on. | `label` |
| `keyboard` | The keyboard layout. | `style`: `name`, `code` |

## You and your work

| Widget | Shows | Options |
|---|---|---|
| `greeting` | "Good evening, Alex." | `name` |
| `agents` | Coding agents from [herdr](https://herdr.dev): who needs you, who is working. | `style`: `list`, `summary`, `dots`, `board`; `rows` |
| `git` | Your repositories: branch, uncommitted changes, commits to push or pull, the last commit. | `repos = { "~/code/app" }` (shows nothing without it) |
| `quote` | A short quote that changes every half hour. | `source`: `builtin`, `fortune`; `quotes` (your own list of `{ text, author }`); `every` |
| `life` | Conway's Game of Life, evolving quietly. | `columns`, `rows`, `every`, `cell` |

Hide personal information (`privacy = true`) keeps names out: the user's and the Mac's, the place, the network
address, git's repositories, branches, and commit messages (the git widget shows only its counts), and herdr's
titles and workspaces.
