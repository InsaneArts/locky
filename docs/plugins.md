# Writing Locky plugins

Locky's plugins are Lua, and the system copies Neovim's: an `init.lua`, a runtime path, `require()`,
`plugin/` scripts that run at startup, `setup(opts)`, packages from git with a lockfile, and health checks.
Locky embeds Lua 5.5.

## Where things live

| Path | What |
|---|---|
| `~/.config/locky/init.lua` | Your config. Runs first, each time the screen locks. |
| `~/.config/locky/lua/` | Your modules, for `require()`. |
| `~/.config/locky/plugin/` | Your scripts that run at startup, such as widget definitions. |
| `~/.config/locky/themes/` | Your themes, one `<name>.lua` each. |
| `~/.config/locky/shaders/` | Your background shaders. |
| `~/.config/locky/locky-pack-lock.json` | The commit of every package. Keep it in your dotfiles. |
| `~/.local/share/locky/pack/<name>/` | Packages installed by `locky pack sync`. |
| `~/Library/Logs/Locky/locky.log` | What plugins print, and every error. |

`$XDG_CONFIG_HOME` and `$XDG_DATA_HOME` move the first and the last two, as in Neovim.

## The runtime path

Locky looks for `lua/`, `plugin/`, `themes/`, `shaders/`, and `assets/` in these folders, first match wins:

1. `~/.config/locky`
2. each package from `locky.pack.add`, in the order you add them
3. Locky's built-in runtime (core modules and widgets)
4. Locky's built-in theme packages

So a file of yours shadows a built-in one with the same path. `require("a.b")` loads `lua/a/b.lua` or
`lua/a/b/init.lua`.

## Startup

Each time the screen locks, Locky starts a fresh Lua state and:

1. runs `init.lua`, then makes `locky.config` read-only: plugins, themes, and widgets read options but never change them
2. runs every `plugin/*.lua` in the runtime path, in path order, then by file name
3. loads the theme (`locky.config.theme`, or the one picked in the menu)
4. creates the theme's widgets, calls each one's `init`, and draws them
5. fires the `lock` event

When the screen unlocks, Locky fires `unlock`, stops every timer and process, and closes the state. Nothing
survives between locks; keep anything you need in a file.

## A widget

```lua
-- ~/.config/locky/plugin/uptime.lua
local ui = locky.ui

locky.widget.define("uptime", {
  description = "How long the Mac has been on",
  card = true,                         -- sit on the theme's card unless the theme says otherwise
  opts = { label = "Up" },             -- defaults; the theme's and the user's options merge in
  choices = { label = { "Up", "On" } }, -- optional: the values an option takes, for the window's editor
  init = function(self)
    self:every(60, function(self)      -- runs now, then every minute; stops when the lock opens
      self:set({ seconds = locky.sys.uptime() })
    end)
  end,
  render = function(self)              -- returns a view; called again after every self:set
    local s = self.state.seconds
    if not s then return nil end
    return ui.vstack {
      align = "leading", spacing = 2,
      ui.text(self.opts.label, { size = 12, color = "muted", case = "upper", tracking = 1 }),
      ui.text(("%dd %dh"):format(s // 86400, s % 86400 // 3600), { size = 22, weight = "semibold", mono = true }),
    }
  end,
})
```

Then place it in a theme, or add it to the current one from `init.lua`:

```lua
locky.theme.extend("default", function(theme)
  table.insert(theme.widgets, { "uptime", anchor = "bottom-left", offset = { 32, -32 } })
end)
```

`render` must be quick and must not wait for anything: fetch data in `init` with timers and
`self:system`, keep it in `self.state`, and only draw it in `render`. See [views.md](views.md) for every
view and property, and [api.md](api.md) for `locky.*`.

## The rules that keep the lock screen safe

- **Time budgets.** Every call into Lua has one: 100 ms for `render`, timers, events, and process
  callbacks; 500 ms for `init`; 2 s for `init.lua`; 1 s for each `plugin/` script. Locky stops code that
  runs longer, even inside `pcall` or a coroutine. A budget counts the time the code runs, so a Mac busy
  with other work does not stop a widget; time spent waiting (a slow file read) counts once a call has
  held the Lua queue for ten times its budget plus a second.
- **Failing widgets stop.** A widget that fails three times in a row, or runs past its budget once, is
  stopped with all its timers and processes. The others keep going. A call that a long C function (a big
  `table.move`, a slow pattern) carried past its budget counts as a failure too.
- **The password field never waits for Lua.** It appears with the shield, in the last theme's style, and
  takes the new theme's style when Lua is ready, unless typing has begun.
- **Memory.** All plugins share 256 MB.
- **Size of a view.** A widget draws at most 5,000 views, and a text holds at most 10,000 characters: the
  main thread draws them, and the password field shares it. Images are decoded off the main thread as
  thumbnails of at most 4,096 pixels.
- **Odd numbers.** A view or theme value that is not a finite number (Lua's `1/0` or `0/0`) is an error, not
  a crash, and sizes and offsets stay within 100,000 points.
- **No blocking calls.** There is no `os.execute` or `io.popen`: use `locky.system`, which never blocks.
  `io.open` and `io.lines` open only regular files (a named pipe would block). There is no `os.exit`, no C
  modules, no bytecode, no `__gc` finalizers, and `debug` has only `traceback` and `getinfo` (which never
  returns a function: that would hand plugins the raw `pcall`, which can catch a timeout).
- **No keyboard.** Widgets never get keystrokes or clicks. No event carries any part of the password.

## What a plugin may do

A plugin you install (a folder in `~/.local/share/locky/pack`) runs programs and changes files only if you
allow it. Without the grant, `locky.system` fails, and so do `io.open` in a write, append, or update mode,
`io.output` with a file name, `os.remove`, `os.rename`, and `os.tmpname`. The error names the plugin and says
how to allow it. Allow it on the Plugins page ("Run programs", "Change files"), or in `init.lua`:

```lua
locky.pack.add({ { src = "someone/locky-git", allow = { "system" } } })   -- "system", "files", or both
```

In settings.json the same entry is `{ "src": "someone/locky-git", "allow": ["system"] }`. `locky check` and
`locky health` list what each plugin may do. Your config folder, your local `{ dir = ... }` folders, and Locky's
own code need no grant.

Locky decides by the call stack: if any Lua function on it comes from a plugin without the grant, or from
code loaded from a string (`load`), the call fails. A coroutine counts the code that resumed it. Locky's Lua
makes no proper tail calls, so `return f()` keeps its caller on the stack; deep recursion through tail calls
runs out of stack. Only `init.lua` and your own config may call `locky.pack.add`, so a plugin cannot grant
itself anything.

This is defense in depth, not a sandbox. A plugin still runs as you: it can read your files and show what it
reads on the lock screen. Lua is not built to isolate code, and a determined plugin may find a way around
these checks. Install only plugins you trust.

## A package

A package is a git repository laid out like the config folder:

```
locky-weather/
  plugin/weather.lua        -- defines the widget (runs at startup)
  lua/weather/init.lua      -- the module: setup(opts), helpers
  lua/weather/health.lua    -- optional: return { check = function() ... end }
  themes/stormy.lua         -- optional: themes it ships
  shaders/rain.metal        -- optional: shaders it ships
  assets/                   -- optional: images
  README.md
```

Users add it in `init.lua` and install it with `locky pack sync` (or the Locky window's Plugins page):

```lua
locky.pack.add({
  "someone/locky-weather",                                  -- GitHub shorthand
  { src = "https://git.example.com/x.git", version = "v1.2.0" },  -- a tag, branch, or commit
  { dir = "~/code/my-plugin" },                             -- a local folder, while you write it
})
require("weather").setup({ city = "Tbilisi" })
```

A source is `"user/repo"` (GitHub), or an `https://`, `ssh://`, or `git@` address. Locky refuses `http://`,
`git://`, and `file://`, even through a redirect: anyone on the network could change what they send. For a
folder on your Mac, use `{ dir = ... }`.

`locky pack update` moves every package to the newest commit of its version and rewrites
`locky-pack-lock.json`; `locky pack clean` deletes packages `init.lua` no longer adds.
`locky pack check` fetches and lists the packages `update` would move, and moves none.

Follow Neovim's conventions: `setup(opts)` only merges options (use `locky.tbl.deep_extend`), keep
`plugin/<name>.lua` small, and give every option a default.

## Health

`locky health` runs Locky's own checks, then `check()` from every `lua/<name>/health.lua`:

```lua
-- lua/weather/health.lua
return {
  check = function()
    locky.health.start("weather")
    if locky.fs.exists("/usr/bin/curl") then
      locky.health.ok("curl is installed")
    else
      locky.health.error("curl is missing", "install it with Homebrew")
    end
  end,
}
```

## Tools

- `locky check [--theme NAME]` runs your config, plugins, and a theme without locking, and lists every error.
- `locky preview --theme NAME` opens the lock screen in a window.
- `locky themes` and `locky widgets` list what is installed.
- For completion and type checking in any editor with lua-language-server, point it at Locky's type stubs.
  `~/.config/locky/.luarc.json`:

  ```json
  {
    "runtime.version": "Lua 5.5",
    "workspace.library": ["/Applications/Locky.app/Contents/Resources/runtime/types"],
    "diagnostics.globals": ["locky"]
  }
  ```
