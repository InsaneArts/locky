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
| `text` | none: it draws at its own size |
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
| `weather` | The weather from [Open-Meteo](https://open-meteo.com), which needs no key; kept for 30 minutes. | `style`: `line`, `hero`, `detail`, `forecast` (three days); `location`; `units`: `automatic`, `celsius`, `fahrenheit`; `place` |
| `sun` | Today's path of the sun, where it is now, and sunrise and sunset (from Open-Meteo). | `width`, `location` |
| `moon` | Tonight's phase, how much is lit, and the days to the full moon. No network. | `style`: `full`, `symbol`, `row`; `size` |

The weather and sun widgets share one request, cached in `~/Library/Caches/Locky`. Hide personal information
(`privacy`) leaves out the place's name.

`location` is one of these:

- `"lat,lon"`, such as `"41.7151,44.8271"`. Customize › Location writes this, with the place's name in `place_name`.
- A place's name, such as `"Tbilisi"` or `"Paris, Texas"`. Locky finds it once with Open-Meteo's geocoding and keeps
  the result.
- `""` (the default) or `"current"`: where the Mac is. If you allow Location Services, this is the Mac's own
  location. If not, it is the city of the Mac's time zone.

In Customize, Location has a search field that suggests cities and regions as you type, and Current Location first.
macOS asks for Location Services only when you pick Current Location, never during a lock. If you said no, the row
under Location opens System Settings › Privacy & Security › Location Services.

`units` `automatic` follows System Settings › General › Language & Region › Temperature. Fahrenheit also shows
wind in mph; Celsius, in km/h. The notebook theme's weather takes `location` and `units` too.

Weather data by [Open-Meteo.com](https://open-meteo.com), under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

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
| `text` | Your own words, in the theme's font and text color. | `text`; `size`: `small`, `medium`, `large`, `huge` (or points); `weight`; `alignment`: `leading`, `center`, `trailing`; `color` |
| `agents` | Coding agents from [herdr](https://herdr.dev): who needs you, who is working. | `style`: `list`, `summary`, `dots`, `board`; `rows` |
| `git` | Your repositories: branch, uncommitted changes, commits to push or pull, the last commit. | `repos = { "~/code/app" }` (shows nothing without it) |
| `quote` | A short quote that changes every half hour. | `source`: `builtin`, `fortune`; `quotes` (your own list of `{ text, author }`); `every` |
| `life` | Conway's Game of Life, evolving quietly. | `columns`, `rows`, `every`, `cell` |

Hide personal information (`privacy = true`) keeps names out: the user's and the Mac's, the place, the network
address, git's repositories, branches, and commit messages (the git widget shows only its counts), and herdr's
titles and workspaces.
