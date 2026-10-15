# The locky API

Everything plugins and `init.lua` use is in the global `locky`. Lua 5.5's standard library is there too,
minus what [plugins.md](plugins.md#the-rules-that-keep-the-lock-screen-safe) lists.

## Config

| | |
|---|---|
| `locky.setup(opts)` | Merges `opts` into `locky.config`: `theme`, `background`, `palette`, `widgets`, `hour24` (`true` or `false` forces a 24- or 12-hour clock in every theme), and `privacy` (`true`: `locky.sys.user()` and `locky.sys.hostname()` return generic names, `locky.herdr` gives each agent its kind as the title and no workspace, and the password field shows no name or picture; widgets that show other personal data should check `locky.config.privacy`), and `message` (a line under the password field, such as "If found, call ..."; it stays visible while a theme hides the field). A value of the wrong type is an error. settings.json, which the Themes and Settings windows write, applies before init.lua and again after the plugin scripts, so it wins. |
| `locky.config` | The current settings. Read-only once `init.lua` has run: a plugin script, theme, or widget that writes it (or calls `locky.setup`) gets an error. |
| `locky.version` | Locky's version. |

## Widgets

| | |
|---|---|
| `locky.widget.define(name, spec)` | Defines a widget. `spec`: `render(self)` (required), `init(self)`, `opts`, `size = { w, h }`, `card`, `description`, and `choices` (the values an option takes, such as `{ style = { "list", "dots" } }`: Customize offers them in a menu). Names may contain letters, digits, `_`, `-`, and `.`; a package prefixes its own, such as `"synthwave.sun"`. |
| `locky.widget.get(name)`, `locky.widget.list()` | A definition; all names. |

Inside `init` and `render`, `self` is the widget instance:

| | |
|---|---|
| `self.opts` | Options: the definition's defaults, then the theme's, then the user's: `locky.setup({ widgets = … })`, then settings.json's. |
| `self.state` | A table for your data. |
| `self.theme` | The theme: `palette`, `font`, `name`, … |
| `self:set(patch)` | Merges `patch` into `self.state` and draws the widget again. |
| `self:refresh()` | Draws the widget again. |
| `self:every(seconds, fn, opts)` | Calls `fn(self)` now and every `seconds` (0.05 or more). `opts.now = false` skips the first call; `opts.align = true` keeps calls on wall-clock multiples, such as the start of each minute for 60, and calls once more right after the Mac or its display wakes. Timers pause while the display sleeps. Returns a timer. |
| `self:after(seconds, fn)` | Calls `fn(self)` once. Returns a timer. |
| `self:system(cmd, opts, on_exit)` | `locky.system` owned by the widget; `on_exit(self, result)`. |
| `self:on(event, fn)` | `locky.on` owned by the widget; `fn(self, data)`. |
| `self:log(...)` | Logs with the widget's name. |

Everything a widget starts stops when the screen unlocks or the widget fails.

## Timers, events, processes

| | |
|---|---|
| `locky.defer(fn, seconds)` | Calls `fn` once, after `seconds` (default 0: after the current call). Returns a timer. |
| `locky.schedule(fn)` | `locky.defer(fn, 0)`. |
| `locky.cancel(timer)` | Stops a timer. |
| `locky.now()` | Seconds since 1970 with fractions, for motion finer than `os.time`'s whole seconds. |
| `locky.on(event, fn)` | `"lock"` (the screen locked), `"unlock"` (about to close), `"auth_failed"` (a wrong password), `"auth_shown"` and `"auth_hidden"` (the password field appeared or went away, in themes with `auth.reveal = "activity"`). No event carries any part of a password. |
| `locky.system(cmd, opts, on_exit)` | Runs a program without a shell and without waiting, like `vim.system`. `cmd` is a list: `{ "pmset", "-g", "batt" }`. `opts`: `cwd`, `env` (table), `stdin` (string), `timeout` (seconds, default 10). `on_exit(result)`: `code`, `signal`, `stdout`, `stderr`, `timed_out`. A missing program gives code 127. Homebrew's folders are on `PATH`. Returns a process. An installed plugin needs the `"system"` grant ([plugins.md](plugins.md#what-a-plugin-may-do)). |
| `locky.kill(process)` | Stops a process. |

## System

| | Returns |
|---|---|
| `locky.sys.battery()` | `present`, `percent`, `charging`, `plugged`, `state` (`"charging"`, `"charged"`, `"plugged"`, `"discharging"`), `remaining` and `until_full` (minutes, when known). |
| `locky.sys.cpu()` | `usage` (percent of all cores since the previous call), `cores`. |
| `locky.sys.memory()` | `total`, `used` (bytes, like Activity Monitor's Memory Used), `percent`. |
| `locky.sys.uptime()` | Seconds since the Mac started, sleep included. |
| `locky.sys.hostname()` | `name` (the computer's name), `host` (its local host name). |
| `locky.sys.user()` | `name` (short), `full_name`. |
| `locky.sys.os()` | `name`, `version`, `codename`, `build`. |
| `locky.sys.machine()` | `model`, `chip`, `cores`, `memory`. |
| `locky.sys.keyboard()` | The selected keyboard layout: `id`, `name`, `language`. |
| `locky.sys.displays()` | How many displays are connected. |
| `locky.sys.screen()` | The main display: `width`, `height` (points), `scale` (what Locky multiplies theme sizes by), and `layout_width`, `layout_height`: the size in theme units, so a widget can span or measure the screen. |
| `locky.sys.wallpaper()` | The main display's desktop picture as an image file path, or nil. For a dynamic wallpaper this is its thumbnail. |
| `locky.sys.wallpaper_colors()` | Its dominant colors, most common first, as `"#rrggbb"` (up to 5; empty without a wallpaper). A theme can build its palette from them, like Material You. |
| `locky.date.format(template, time, zone)` | A date: `"time"` (24- or 12-hour as `locky.config.hour24` forces, when set), `"date"`, a pattern used as it is (`"EEEE d MMMM"`, `"HH:mm"`), or `"skeleton:EEEEdMMMM"` (ordered the user's way). Names come in the user's language. `time` defaults to now; `zone` (such as `"Asia/Tokyo"`) shows it in another time zone, and the pattern `"ZZZZZ"` gives that zone's offset (`+09:00`). |
| `locky.date.locale()` | `identifier`, `language`, `hour24` (`locky.config.hour24` when set), `first_weekday` (1 is Sunday), `temperature` (`"C"` or `"F"`, from System Settings › General › Language & Region), `weekdays`, `weekdays_short`, `weekdays_abbreviated`, `months`, `months_short`. |
| `locky.location()` | Where the Mac is: `lat`, `lon`, `name`, or nil. This is Location Services' last fix if you allowed it in Customize, else the city of the Mac's time zone. It never asks for a permission. In privacy mode, `name` is nil; a widget must not show `lat` and `lon`. |

## Files and data

| | |
|---|---|
| `locky.fs.read(path)` | The file as a string, or `nil, error`. Up to 16 MB. |
| `locky.fs.exists(path)`, `locky.fs.is_dir(path)`, `locky.fs.list(dir)` | |
| `locky.fs.home`, `locky.fs.expand(path)`, `locky.fs.join(...)` | |
| `locky.fs.package_dir()` | The folder of the package that holds the calling file. |
| `locky.json.encode(value)`, `locky.json.decode(text)` | JSON. Keys come out sorted; JSON null becomes nil. |

## Tables and strings

After Neovim's `vim.tbl_*`: `locky.tbl.deep_extend(behavior, ...)` (`"force"`, `"keep"`, or `"error"`; maps
merge, lists are replaced), `extend`, `deepcopy`, `islist`, `isempty`, `keys`, `values`, `map`, `filter`,
`contains`, `count`, `get(t, ...)`. `locky.str.split(s, sep, { trimempty = true })`, `trim`, `startswith`,
`endswith`. `locky.inspect(value)`. `locky.validate(name, value, type_or_types_or_fn, optional)`.

## herdr

`require("locky.herdr")` reads coding agents from [herdr](https://herdr.dev), for widgets that show them:

```lua
local herdr = require("locky.herdr")
init = function(self)
  herdr.watch(self, function(self, data) self:set({ herdr = data }) end)  -- now, then at each change
end
```

Locky keeps one connection to herdr's socket while a lock or a preview shows a widget that watches. herdr tells
Locky when an agent changes, so the widget gets new data at once, and no program runs on a timer. If herdr is not
running, Locky tries again after 0.5, 1, 2, and then every 3 seconds. The old form `herdr.watch(self, seconds, fn)`
still works; the seconds have no effect.

`data` is `false` when herdr is not running, otherwise `{ agents, counts, need, fetched }`:

- `agents`: sorted blocked, done, working, idle, and in each status the oldest change first. Each agent is
  `{ id, status, kind, title, workspace, since }`. `id` is herdr's terminal id, which stays when the pane moves.
  `since` is how many seconds the agent had its status at `fetched`. It is `nil` when the status began before Locky
  connected.
- `counts`: the number of agents in each status (`blocked`, `done`, `working`, `idle`, `unknown`).
- `need`: blocked + done.
- `fetched`: when herdr gave the data, in seconds since 1970.

A plugin you install needs the "Run programs" grant to read the agents
([plugins.md](plugins.md#what-a-plugin-may-do)); without it, `data` is `false`. Your config folder and Locky's own
widgets need no grant.

In privacy mode, `title` is the agent's kind (such as `"Claude"`) and `workspace` is `""`. The kind is the name of
the program, not of your work, so it shows.

`herdr.elapsed(data, agent)` is the seconds the agent has had its status now, or `nil`. `herdr.duration(seconds)`
writes it short, as the agents widget does: `"now"`, `"12m"`, `"3h"`, `"2d"`. `herdr.colors` and `herdr.words`
map each status to a palette role and a label. `herdr.parse(json)` parses `herdr api snapshot` output yourself.

## Weather

`require("locky.weather")` gets the weather from [Open-Meteo](https://open-meteo.com), as the weather widget does:

```lua
local weather = require("locky.weather")
init = function(self)
  weather.watch(self, self.opts, function(self, data) self:set({ data = data }) end)
end
```

`opts`: `location`, `place_name`, `units`, and `every`, as [widgets.md](widgets.md#sky) says. `data` is `false`
while there is no weather, otherwise `{ place, temp, feels, high, low, unit, condition, code, symbol, night,
humidity, wind, wind_unit, wind_dir, uv, sunrise, sunset, moon_phase, moon_illumination, days, hours, fetched }`.
`code` is the WMO weather code; `weather.condition(code, night)` gives its words and SF Symbol. Weather data by
Open-Meteo.com, under CC BY 4.0.

## Logging and health

`print(...)` and `locky.log.debug/info/warn/error(...)` write to `~/Library/Logs/Locky/locky.log`;
`locky.notify(message, level)` too. `locky.health.start/ok/info/warn/error` report from a plugin's
`lua/<name>/health.lua` (see [plugins.md](plugins.md#health)).

## Themes and packages

`locky.theme.extend(name, table_or_function)`, `locky.theme.derive(base, { name, edits })` (the file Duplicate
Theme and Export Theme write; see [themes.md](themes.md#make-and-share-themes-in-the-window)), `locky.theme.list()`,
`locky.theme.current`.
`locky.pack.add(specs)`. See [themes.md](themes.md) and [plugins.md](plugins.md#a-package).
