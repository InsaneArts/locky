-- Locky's core. The host runs it once per Lua state, before any other code, with two arguments:
-- its native functions, and a function that says whether the current call has run out of time.
-- It builds the `locky` global and returns the entry points the host calls.
local native, budget_exceeded = ...

local type, pairs, ipairs, select, tostring, rawget, error = type, pairs, ipairs, select, tostring, rawget, error
local raw_pcall, raw_xpcall = pcall, xpcall
local raw_create, raw_resume = coroutine.create, coroutine.resume
local raw_load, raw_loadfile, raw_setmetatable = load, loadfile, setmetatable
local pack, unpack, concat, insert, sort = table.pack, table.unpack, table.concat, table.insert, table.sort

-------------------------------------------------------------------------------
-- Guards. A call that ran out of time must end: pcall, xpcall, and coroutines would otherwise catch the
-- timeout and keep going. Source only, never bytecode. No finalizers: they run outside any time budget.
-------------------------------------------------------------------------------

-- A call that ran out of time or memory must end. budget_exceeded() says why (or false); the error is
-- raised again whatever the caught error became, since an xpcall handler may have turned it into nil.
local function rethrow_timeout(ok, ...)
  if not ok then
    local why = budget_exceeded()
    if why then
      error(why, 0)
    end
  end
  return ok, ...
end

function pcall(f, ...)
  return rethrow_timeout(raw_pcall(f, ...))
end

-- The handler runs inside the hook that raised the error, where the hook is off: after a timeout it must
-- not run at all, or a slow handler would run unbounded.
function xpcall(f, handler, ...)
  return rethrow_timeout(raw_xpcall(f, function(e)
    if budget_exceeded() then
      return e
    end
    return handler(e)
  end, ...))
end

coroutine.resume = function(co, ...)
  return rethrow_timeout(raw_resume(co, ...))
end

coroutine.wrap = function(f)
  local co = raw_create(f)
  return function(...)
    local results = pack(coroutine.resume(co, ...))
    if not results[1] then
      coroutine.close(co)  -- runs its <close> variables, as Lua's own wrap does
      error(results[2], 0)
    end
    return unpack(results, 2, results.n)
  end
end

-- load runs a reader function inside the parser's own protected call, which turns any error, a timeout
-- included, into nil and a message.
local function rethrow_load(chunk, ...)
  if chunk == nil then
    local why = budget_exceeded()
    if why then
      error(why, 0)
    end
  end
  return chunk, ...
end

-- Source only, never bytecode. The environment argument is passed on only when given, so chunks keep
-- their globals.
function load(chunk, chunkname, _, ...)
  return rethrow_load(raw_load(chunk, chunkname, "t", ...))
end

function loadfile(path, _, ...)
  return raw_loadfile(path, "t", ...)
end

function dofile(path)
  local chunk = assert(loadfile(path))
  return chunk()
end

-- Opening a named pipe or a device blocks inside C, where no time budget reaches: only regular files and
-- new files open.
do
  local raw_open, raw_lines, raw_input, raw_output = io.open, io.lines, io.input, io.output
  local function check(path)
    if type(path) == "string" and native.fs_kind(path) == "other" then
      error(path .. ": only regular files can be opened", 3)
    end
  end
  io.open = function(path, ...)
    check(path)
    return raw_open(path, ...)
  end
  io.lines = function(path, ...)
    check(path)
    return raw_lines(path, ...)
  end
  io.input = function(file)
    check(file)
    return raw_input(file)
  end
  io.output = function(file)
    check(file)
    return raw_output(file)
  end
end

function setmetatable(t, mt)
  if type(mt) == "table" and rawget(mt, "__gc") ~= nil then
    error("Locky does not allow __gc metamethods: they would run outside the time budget", 2)
  end
  return raw_setmetatable(t, mt)
end

-- Where a call came from, as "file:line", for logs and errors.
local function caller(level)
  local info = debug.getinfo(level + 1, "Sl")
  if not info then
    return "?"
  end
  return info.short_src .. ":" .. (info.currentline or 0)
end

function print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring((select(i, ...)))
  end
  native.log("info", concat(parts, "\t"), caller(2))
end

-- require() finds lua/<name>.lua and lua/<name>/init.lua in the runtime path, like Neovim.
insert(package.searchers, function(name)
  local path = native.find_module(name)
  if not path then
    return "\n\tno file lua/" .. name:gsub("%.", "/") .. ".lua in Locky's runtime path"
  end
  local chunk, message = raw_loadfile(path, "t")
  if not chunk then
    error(message, 0)
  end
  return chunk, path
end)

-------------------------------------------------------------------------------
-- The locky global.
-------------------------------------------------------------------------------

locky = {}
locky.version = native.version()

--- Checks an argument and raises a clear error for the caller of the caller.
--- `expected` is a type name, a list of type names, or a function returning true or false, message.
function locky.validate(name, value, expected, optional)
  if value == nil and optional then
    return
  end
  local ok, message
  if type(expected) == "function" then
    ok, message = expected(value)
    message = message or "is not valid"
  else
    local names = type(expected) == "table" and expected or { expected }
    for _, t in ipairs(names) do
      if type(value) == t or (t == "callable" and type(value) == "function") then
        ok = true
      end
    end
    message = ("expected %s, got %s"):format(concat(names, " or "), type(value))
  end
  if not ok then
    error(("%s: %s"):format(name, message), 3)
  end
end
local validate = locky.validate

-------------------------------------------------------------------------------
-- Tables and strings, after vim.tbl_* and vim.split.
-------------------------------------------------------------------------------

local tbl = {}
locky.tbl = tbl

--- True for a table with keys 1..n and nothing else. An empty table counts as a list.
function tbl.islist(t)
  if type(t) ~= "table" then
    return false
  end
  local count = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
      return false
    end
    count = count + 1
  end
  return count == #t
end

function tbl.isempty(t)
  return next(t) == nil
end

local function mergeable(v)
  return type(v) == "table" and (next(v) == nil or not tbl.islist(v))
end

local function deep_extend(behavior, deep, ...)
  local result = {}
  for i = 1, select("#", ...) do
    local t = select(i, ...)
    if t ~= nil then
      validate("argument " .. i, t, "table")
      for k, v in pairs(t) do
        if deep and mergeable(v) and mergeable(result[k]) then
          result[k] = deep_extend(behavior, true, result[k], v)
        elseif result[k] == nil or behavior == "force" then
          result[k] = deep and mergeable(v) and deep_extend(behavior, true, v) or v
        elseif behavior == "error" then
          error("key found in more than one table: " .. tostring(k), 2)
        end
      end
    end
  end
  return result
end

--- Merges tables into a new one. behavior: "force" (later tables win), "keep" (earlier win), or "error".
--- Maps merge recursively; lists are replaced whole.
function tbl.deep_extend(behavior, ...)
  validate("behavior", behavior, function(v)
    return v == "force" or v == "keep" or v == "error", "expected \"force\", \"keep\", or \"error\""
  end)
  return deep_extend(behavior, true, ...)
end

function tbl.extend(behavior, ...)
  return deep_extend(behavior, false, ...)
end

function tbl.deepcopy(v, seen)
  if type(v) ~= "table" then
    return v
  end
  seen = seen or {}
  if seen[v] then
    return seen[v]
  end
  local copy = {}
  seen[v] = copy
  for k, value in pairs(v) do
    copy[tbl.deepcopy(k, seen)] = tbl.deepcopy(value, seen)
  end
  return copy
end

function tbl.keys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  return keys
end

function tbl.values(t)
  local values = {}
  for _, v in pairs(t) do
    values[#values + 1] = v
  end
  return values
end

function tbl.map(f, t)
  local result = {}
  for k, v in pairs(t) do
    result[k] = f(v)
  end
  return result
end

function tbl.filter(f, t)
  local result = {}
  for _, v in ipairs(t) do
    if f(v) then
      result[#result + 1] = v
    end
  end
  return result
end

function tbl.contains(t, value)
  for _, v in pairs(t) do
    if v == value then
      return true
    end
  end
  return false
end

function tbl.count(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

--- t[k1][k2]..., or nil when a step is missing.
function tbl.get(t, ...)
  for i = 1, select("#", ...) do
    if type(t) ~= "table" then
      return nil
    end
    t = t[select(i, ...)]
  end
  return t
end

local str = {}
locky.str = str

--- Splits at each plain-text separator. With opts.trimempty, leading and trailing empty parts are dropped.
function str.split(s, separator, opts)
  local parts, start = {}, 1
  if separator == "" then
    for i = 1, #s do
      parts[i] = s:sub(i, i)
    end
    return parts
  end
  while true do
    local first, last = s:find(separator, start, true)
    if not first then
      parts[#parts + 1] = s:sub(start)
      break
    end
    parts[#parts + 1] = s:sub(start, first - 1)
    start = last + 1
  end
  if opts and opts.trimempty then
    while parts[1] == "" do
      table.remove(parts, 1)
    end
    while parts[#parts] == "" do
      parts[#parts] = nil
    end
  end
  return parts
end

-- Linear: the obvious gsub("%s+$", "") is quadratic on long runs of spaces.
function str.trim(s)
  local first = s:find("%S")
  return first and s:match(".*%S", first) or ""
end

function str.startswith(s, prefix)
  return s:sub(1, #prefix) == prefix
end

function str.endswith(s, suffix)
  return suffix == "" or s:sub(-#suffix) == suffix
end

-------------------------------------------------------------------------------
-- inspect, after vim.inspect: a readable, sorted, cycle-safe rendering of any value.
-------------------------------------------------------------------------------

local function inspect(v, indent, seen)
  if type(v) == "string" then
    return ("%q"):format(v)
  elseif type(v) ~= "table" then
    return tostring(v)
  elseif seen[v] then
    return "<cycle>"
  end
  seen[v] = true
  local keys = tbl.keys(v)
  sort(keys, function(a, b)
    if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then
      return a < b
    end
    return type(a) < type(b)
  end)
  if #keys == 0 then
    seen[v] = nil
    return "{}"
  end
  local inner = indent .. "  "
  local parts = {}
  local list = tbl.islist(v)
  for _, k in ipairs(keys) do
    local key = ""
    if not list then
      key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k .. " = " or "[" .. inspect(k, inner, seen) .. "] = "
    end
    parts[#parts + 1] = inner .. key .. inspect(v[k], inner, seen)
  end
  seen[v] = nil
  return "{\n" .. concat(parts, ",\n") .. "\n" .. indent .. "}"
end

function locky.inspect(v)
  return inspect(v, "", {})
end

-------------------------------------------------------------------------------
-- Logging, after vim.notify. Messages go to ~/Library/Logs/Locky/locky.log and to `locky health`.
-------------------------------------------------------------------------------

locky.log = {}
for _, level in ipairs({ "debug", "info", "warn", "error" }) do
  locky.log[level] = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      local part = select(i, ...)
      parts[i] = type(part) == "table" and locky.inspect(part) or tostring(part)
    end
    native.log(level, concat(parts, " "), caller(2))
  end
end

function locky.notify(message, level)
  native.log(level or "info", tostring(message), caller(2))
end

-------------------------------------------------------------------------------
-- Settings. init.lua calls locky.setup({...}); later calls merge into earlier ones.
-------------------------------------------------------------------------------

locky.config = {
  theme = "default",
  -- Prototype safety: the lock opens by itself after this many seconds. 0 turns it off.
  auto_unlock = 60,
  -- Replaces the theme's background, such as { wallpaper = true, blur = 30 } or { image = "~/x.jpg" }.
  background = nil,
  -- Merged into the theme's palette, such as { accent = "#ff79c6" }.
  palette = {},
  -- Options for every instance of a widget, such as { clock = { format = "HH:mm" } }.
  widgets = {},
  -- true or false forces a 24- or 12-hour clock in every theme; nil follows the system.
  hour24 = nil,
  -- Hides agent titles and workspaces, your name, and the computer's name from widgets.
  privacy = false,
  -- A line under the password field, such as "If found, call ...".
  message = nil,
}

function locky.setup(opts)
  validate("opts", opts, "table")
  locky.config = tbl.deep_extend("force", locky.config, opts)
end

-------------------------------------------------------------------------------
-- Files, JSON, the system, dates.
-------------------------------------------------------------------------------

locky.fs = {
  home = native.home(),
  read = native.fs_read,
  exists = native.fs_exists,
  is_dir = native.fs_is_dir,
  list = native.fs_list,
}

function locky.fs.expand(path)
  validate("path", path, "string")
  if path == "~" or str.startswith(path, "~/") then
    return locky.fs.home .. path:sub(2)
  end
  return path
end

function locky.fs.join(...)
  local parts = { ... }
  return (concat(parts, "/"):gsub("/+", "/"))
end

--- The folder of the package that holds the calling file: where its assets/ and shaders/ live.
function locky.fs.package_dir(level)
  local source = debug.getinfo((level or 1) + 1, "S").source
  if source:sub(1, 1) ~= "@" then
    return nil
  end
  local path = locky.fs.expand(source:sub(2))
  return path:match("^(.*)/lua/[^/]+.*$") or path:match("^(.*)/plugin/[^/]+$") or path:match("^(.*)/themes/[^/]+$")
end

locky.json = {
  encode = native.json_encode,
  decode = native.json_decode,
}

locky.sys = {
  battery = native.sys_battery,
  cpu = native.sys_cpu,
  memory = native.sys_memory,
  uptime = native.sys_uptime,
  -- In privacy mode (locky.config.privacy), generic names instead of the computer's and the user's.
  hostname = function()
    if locky.config.privacy then
      return { name = "Mac", host = "mac" }
    end
    return native.sys_hostname()
  end,
  user = function()
    if locky.config.privacy then
      return { name = "user", full_name = "" }
    end
    return native.sys_user()
  end,
  os = native.sys_os,
  machine = native.sys_machine,
  keyboard = native.sys_keyboard,
  displays = native.sys_displays,
  wallpaper = native.sys_wallpaper,
  wallpaper_colors = native.sys_wallpaper_colors,
  screen = native.sys_screen,
}

--- Seconds since 1970 with fractions, for motion finer than os.time's whole seconds.
locky.now = native.now

locky.date = {
  --- Formats a time (seconds since 1970, default now): "time" and "date" give the system's own short time
  --- and long date; a pattern such as "EEEE d MMMM" or "HH:mm" is used as it is (names in the user's
  --- language); "skeleton:EEEEdMMMM" orders and punctuates those fields the user's way.
  format = function(template, time)
    validate("template", template, "string")
    validate("time", time, "number", true)
    if template == "time" and locky.config.hour24 ~= nil then
      template = locky.config.hour24 and "HH:mm" or "h:mm"
    end
    return native.date_format(template, time or os.time())
  end,
  --- The user's language, weekdays, months, first weekday, and hour24 (locky.config.hour24 when it is set).
  locale = function()
    local locale = native.locale()
    if locky.config.hour24 ~= nil then
      locale.hour24 = locky.config.hour24 == true
    end
    return locale
  end,
}

-------------------------------------------------------------------------------
-- Timers, events, and processes. Each belongs to an owner: a widget instance, or 0 for global code.
-- The host stops an owner's timers and processes when the lock screen closes or the widget fails.
-------------------------------------------------------------------------------

--- Runs fn once after `seconds` (default 0: as soon as the current call returns).
function locky.defer(fn, seconds)
  validate("fn", fn, "callable")
  validate("seconds", seconds, "number", true)
  return native.timer(0, seconds or 0, false, fn, false)
end

function locky.schedule(fn)
  return locky.defer(fn, 0)
end

function locky.cancel(timer)
  native.timer_stop(timer)
end

local events = { lock = true, unlock = true, auth_failed = true, auth_shown = true, auth_hidden = true }
local event_names = "\"lock\", \"unlock\", \"auth_failed\", \"auth_shown\", or \"auth_hidden\""

--- Calls fn(data) on each event: "lock" (the screen locked), "unlock" (about to close),
--- "auth_failed" (a wrong password), "auth_shown" and "auth_hidden" (the password field appeared or went
--- away, in themes that hide it until you type). No event carries any part of a password.
function locky.on(event, fn)
  validate("event", event, function(v)
    return events[v] ~= nil, "expected " .. event_names
  end)
  validate("fn", fn, "callable")
  native.on(event, fn, 0)
end

local function system(owner, cmd, opts, on_exit)
  validate("cmd", cmd, function(v)
    if type(v) ~= "table" or #v == 0 then
      return false, "expected a list of strings, such as { \"pmset\", \"-g\", \"batt\" }"
    end
    for _, part in ipairs(v) do
      if type(part) ~= "string" then
        return false, "every part must be a string"
      end
    end
    return true
  end)
  validate("opts", opts, "table", true)
  validate("on_exit", on_exit, "callable", true)
  return native.system(owner, cmd, opts or {}, on_exit)
end

--- Runs a program without waiting, after vim.system. on_exit receives
--- { code, signal, stdout, stderr, timed_out }. opts: cwd, env (table), stdin (string), timeout (seconds, default 10).
function locky.system(cmd, opts, on_exit)
  if type(opts) == "function" then
    opts, on_exit = nil, opts
  end
  return system(0, cmd, opts, on_exit)
end

function locky.kill(process)
  native.system_kill(process)
end

-------------------------------------------------------------------------------
-- Widgets.
-------------------------------------------------------------------------------

local widgets = {}
locky.widget = {}

--- Defines a widget. spec:
---   render(self)  required: returns a view built with locky.ui, or nil to show nothing
---   init(self)    optional: runs when the lock screen opens; start timers and processes here
---   opts          optional: default options; a theme's and the user's options merge into them
---   size          optional: { width, height } in points; without it the widget fits its content
---   card          optional: true to sit on the theme's card unless the theme says otherwise
---   description   optional
function locky.widget.define(name, spec)
  validate("name", name, function(v)
    return type(v) == "string" and v:match("^[%w_][%w_.-]*$") ~= nil, "expected a name of letters, digits, '_', '-', and '.'"
  end)
  validate("spec", spec, "table")
  validate("spec.render", spec.render, "callable")
  validate("spec.init", spec.init, "callable", true)
  validate("spec.opts", spec.opts, "table", true)
  validate("spec.size", spec.size, "table", true)
  local definition = tbl.extend("force", spec)
  definition.name = name
  definition.source = caller(2)
  local info = debug.getinfo(2, "S")
  definition.file = info and info.source:match("^@(.*)")
  widgets[name] = definition
  return definition
end

function locky.widget.get(name)
  return widgets[name]
end

function locky.widget.list()
  local names = tbl.keys(widgets)
  sort(names)
  return names
end

local Instance = {}
Instance.__index = Instance
Instance.__metatable = false  -- so no finalizer can be added to it

--- Merges `patch` into self.state and draws the widget again.
function Instance:set(patch)
  validate("patch", patch, "table")
  for k, v in pairs(patch) do
    self.state[k] = v
  end
  native.invalidate(self.id)
end

--- Draws the widget again.
function Instance:refresh()
  native.invalidate(self.id)
end

--- Calls fn(self) now and every `seconds`. opts.now = false skips the first call. opts.align = true starts
--- each call on a multiple of `seconds` on the wall clock, such as each new minute for 60.
function Instance:every(seconds, fn, opts)
  validate("seconds", seconds, "number")
  validate("fn", fn, "callable")
  validate("opts", opts, "table", true)
  opts = opts or {}
  local timer = native.timer(self.id, seconds, true, function()
    fn(self)
  end, opts.align == true)
  if opts.now ~= false then
    fn(self)
  end
  return timer
end

--- Calls fn(self) once after `seconds`.
function Instance:after(seconds, fn)
  validate("seconds", seconds, "number")
  validate("fn", fn, "callable")
  return native.timer(self.id, seconds, false, function()
    fn(self)
  end, false)
end

--- locky.system, owned by this widget: it stops when the widget does.
function Instance:system(cmd, opts, on_exit)
  if type(opts) == "function" then
    opts, on_exit = nil, opts
  end
  return system(self.id, cmd, opts, on_exit and function(result)
    on_exit(self, result)
  end)
end

--- locky.on, owned by this widget: fn(self, data).
function Instance:on(event, fn)
  validate("event", event, function(v)
    return events[v] ~= nil, "expected " .. event_names
  end)
  validate("fn", fn, "callable")
  native.on(event, function(data)
    fn(self, data)
  end, self.id)
end

function Instance:log(...)
  locky.log.info("[" .. self.name .. "]", ...)
end

-------------------------------------------------------------------------------
-- Themes. A theme is themes/<name>.lua in the runtime path, returning a table; see docs/themes.md.
-------------------------------------------------------------------------------

local theme_patches = {}
locky.theme = {}

--- Changes a theme before it is used. `patch` is a table merged into the theme (lists are replaced whole),
--- or a function(theme) that changes the theme in place or returns a new one.
function locky.theme.extend(name, patch)
  validate("name", name, "string")
  validate("patch", patch, { "table", "function" })
  theme_patches[name] = theme_patches[name] or {}
  insert(theme_patches[name], patch)
end

function locky.theme.list()
  local names = {}
  for _, entry in ipairs(native.find_all("themes", ".lua")) do
    names[#names + 1] = entry.name
  end
  sort(names)
  return names
end

local anchors = {
  top = true, ["top-left"] = true, ["top-right"] = true, center = true,
  bottom = true, ["bottom-left"] = true, ["bottom-right"] = true,
  left = true, right = true,
}

local function point(name, value)
  validate(name, value, function(v)
    return type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number", "expected { x, y }"
  end, true)
  return value
end

-- Checks a theme and fills in defaults. Errors name the field.
local function normalize_theme(name, theme, background_from_settings)
  validate("theme " .. name, theme, "table")
  validate("theme.palette", theme.palette, "table", true)
  validate("theme.widgets", theme.widgets, "table", true)
  local result = {
    id = name,
    dir = theme.dir,
    name = theme.name or name,
    description = theme.description,
    author = theme.author,
    palette = tbl.deep_extend("force", {
      bg = "#000000", fg = "#ffffff", muted = "#ffffff99", accent = "#0a84ff", surface = "#ffffff1a",
      border = "#ffffff26", success = "#30d158", warning = "#ff9f0a", danger = "#ff453a",
    }, theme.palette or {}, locky.config.palette or {}),
    font = theme.font or {},
    background = background_from_settings and theme.background or locky.config.background or theme.background or { color = "#000000" },
    overlay = theme.overlay,
    card = tbl.deep_extend("force", { style = "glass", radius = 22 }, theme.card or {}),
    auth = tbl.deep_extend("force", { style = "pill", anchor = "bottom", offset = { 0, -60 }, avatar = true, name = true, hint = true }, theme.auth or {}),
    widgets = {},
  }
  point("theme.auth.offset", result.auth.offset)
  for i, entry in ipairs(theme.widgets or {}) do
    local where = ("theme.widgets[%d]"):format(i)
    validate(where, entry, "table")
    local widget = entry.widget or entry[1]
    validate(where .. " widget name", widget, "string")
    local anchor = entry.anchor or "center"
    validate(where .. ".anchor", anchor, function(v)
      return anchors[v] ~= nil, "expected one of top, top-left, top-right, left, center, right, bottom, bottom-left, bottom-right"
    end)
    validate(where .. ".opts", entry.opts, "table", true)
    result.widgets[i] = {
      widget = widget,
      anchor = anchor,
      offset = point(where .. ".offset", entry.offset) or { 0, 0 },
      size = point(where .. ".size", entry.size),
      align = entry.align,
      card = entry.card,
      display = entry.display or "main",
      opts = entry.opts or {},
    }
  end
  return result
end

local current_theme

-- A theme file with the changes init.lua and plugins made with locky.theme.extend.
local function read_theme(name)
  local path = native.find_runtime("themes/" .. name .. ".lua")
  if not path then
    error(("no theme named %q (looked for themes/%s.lua in the runtime path)"):format(name, name), 0)
  end
  local chunk, message = raw_loadfile(path, "t")
  if not chunk then
    error(message, 0)
  end
  local theme = chunk()
  validate("themes/" .. name .. ".lua", theme, "table")
  theme.dir = theme.dir or path:match("^(.*)/themes/[^/]+$")
  for _, patch in ipairs(theme_patches[name] or {}) do
    if type(patch) == "function" then
      theme = patch(theme) or theme
    else
      theme = tbl.deep_extend("force", theme, patch)
    end
  end
  return theme
end

-- The Locky window's changes to themes, from settings.json: { [name] = { background = {...}, widgets = {...} } }.
local settings_themes = {}

local function placement_name(placement)
  return type(placement) == "table" and (placement.widget or placement[1]) or nil
end

-- What the window changed in `theme`: its background, and its widget list. A widget entry with `ref` is the
-- theme's own placement number `ref` (keeping its options) with the entry's fields on top; an entry without
-- `ref` adds a widget. Returns nil for no change; raises on a bad entry, so nothing half-applies.
local function settings_edit(name, theme, edit)
  if type(edit) ~= "table" then
    return nil
  end
  local where = "settings.json themes." .. name
  validate(where .. ".background", edit.background, "table", true)
  validate(where .. ".widgets", edit.widgets, "table", true)
  local result = { background = edit.background and tbl.deepcopy(edit.background) }
  if edit.widgets then
    local original, used, list = theme.widgets or {}, {}, {}
    for i, entry in ipairs(edit.widgets) do
      local at = ("%s.widgets[%d]"):format(where, i)
      validate(at, entry, "table")
      validate(at .. ".widget", entry.widget, "string")
      validate(at .. ".anchor", entry.anchor, function(v)
        return v == nil or anchors[v] ~= nil, "expected an anchor such as top or bottom-right"
      end)
      validate(at .. ".opts", entry.opts, "table", true)
      local base
      if entry.ref ~= nil then
        -- The theme's placement, if it is still there; after the theme changed, its first unused placement of
        -- the same widget. A widget the theme no longer has is dropped.
        if placement_name(original[entry.ref]) == entry.widget and not used[entry.ref] then
          base = entry.ref
        else
          for j, placement in ipairs(original) do
            if not used[j] and placement_name(placement) == entry.widget then
              base = j
              break
            end
          end
        end
      end
      if entry.ref == nil or base then
        local placement = {}
        if base then
          used[base] = true
          for key, value in pairs(original[base]) do
            placement[key] = value
          end
          placement[1] = nil
        end
        placement.widget = entry.widget
        for _, key in ipairs({ "anchor", "offset", "size", "align", "card", "display" }) do
          if entry[key] ~= nil then
            placement[key] = entry[key]
          end
        end
        if entry.opts then
          placement.opts = tbl.deep_extend("force", placement.opts or {}, entry.opts)
        end
        list[#list + 1] = placement
      end
    end
    result.widgets = list
  end
  return result
end

local function load_theme(name)
  local theme = read_theme(name)
  local problems = {}
  local ok, edit = pcall(settings_edit, name, theme, settings_themes[name])
  if not ok then
    problems[1] = tostring(edit)
    edit = nil
  end
  if edit then
    theme.background = edit.background or theme.background
    theme.widgets = edit.widgets or theme.widgets
  end
  local normalized = normalize_theme(name, theme, edit ~= nil and edit.background ~= nil)
  normalized.problems = problems
  return normalized
end

-- A copy with only strings, numbers, booleans, and tables: for data the host reads.
local function plain(value)
  local kind = type(value)
  if kind == "string" or kind == "number" or kind == "boolean" then
    return value
  elseif kind ~= "table" then
    return nil
  end
  local copy = {}
  for key, item in pairs(value) do
    copy[key] = plain(item)
  end
  return copy
end

-------------------------------------------------------------------------------
-- Packages, after vim.pack. locky.pack.add puts plugins on the runtime path; `locky pack sync`
-- (or the menu) clones the missing ones with git, pinned by ~/.config/locky/locky-pack-lock.json.
-------------------------------------------------------------------------------

local pack_specs = {}
locky.pack = {}

local function pack_spec(spec)
  if type(spec) == "string" then
    spec = { src = spec }
  end
  validate("spec", spec, "table")
  validate("spec.src", spec.src, "string", spec.dir ~= nil)
  validate("spec.dir", spec.dir, "string", true)
  validate("spec.version", spec.version, "string", true)
  validate("spec.name", spec.name, "string", true)
  -- git would read a leading "-" as an option.
  validate("spec.src", spec.src, function(v)
    return v == nil or v:sub(1, 1) ~= "-", "must not start with '-'"
  end)
  validate("spec.version", spec.version, function(v)
    return v == nil or v:sub(1, 1) ~= "-", "must not start with '-'"
  end)
  local src = spec.src
  if src and src:match("^[%w_.-]+/[%w_.-]+$") then
    src = "https://github.com/" .. src
  end
  local name = spec.name or (spec.dir and spec.dir:match("([^/]+)/*$")) or src:match("([^/]+)/*$"):gsub("%.git$", "")
  validate("spec.name", name, function(v)
    return v:match("^[%w_.-]+$") ~= nil and v ~= "." and v ~= "..", "expected letters, digits, '_', '-', and '.'"
  end)
  return { name = name, src = src, version = spec.version, dir = spec.dir and locky.fs.expand(spec.dir) }
end

-- `from` is "settings" for the Locky window's packages (settings.json) and "config" for init.lua's.
local function add_packs(specs, from, level)
  for _, spec in ipairs(specs) do
    local normalized = pack_spec(spec)
    normalized.from = from
    local duplicate
    for _, existing in ipairs(pack_specs) do
      -- The Mac's file system ignores case, so "One" and "one" would share a folder.
      if existing.name:lower() == normalized.name:lower() then
        duplicate = existing
        break
      end
    end
    if duplicate and duplicate.from == "settings" and from ~= "settings" then
      -- The window added it before init.lua ran; settings.json wins, as it does everywhere.
      duplicate.in_config = true
    elseif duplicate then
      error(("two packages are named %q; give one a name = ..."):format(normalized.name), level)
    else
      insert(pack_specs, normalized)
      native.pack_add(normalized.name, normalized.dir)
    end
  end
end

--- Adds plugins: "user/repo", a git URL, or { src = ..., version = "v1.2.0" | branch | commit, name = ... }.
--- { dir = "~/code/my-plugin" } adds a local folder, for writing a plugin.
function locky.pack.add(specs)
  validate("specs", specs, "table")
  if type(specs[1]) ~= "string" and type(specs[1]) ~= "table" and (specs.src or specs.dir) then
    specs = { specs }
  end
  add_packs(specs, "config", 3)
end

-------------------------------------------------------------------------------
-- Health, after vim.health. A plugin may ship lua/<name>/health.lua returning { check = function() ... }.
-------------------------------------------------------------------------------

local report
locky.health = {}

function locky.health.start(name)
  report.sections[#report.sections + 1] = { name = tostring(name), items = {} }
end

local function health_item(kind)
  return function(message, advice)
    if #report.sections == 0 then
      locky.health.start("?")
    end
    insert(report.sections[#report.sections].items, { kind = kind, message = tostring(message), advice = advice and tostring(advice) })
  end
end
locky.health.ok = health_item("ok")
locky.health.info = health_item("info")
locky.health.warn = health_item("warn")
locky.health.error = health_item("error")

-------------------------------------------------------------------------------
-- The view builders.
-------------------------------------------------------------------------------

locky.ui = require("locky.ui")

-------------------------------------------------------------------------------
-- Entry points for the host.
-------------------------------------------------------------------------------

local instances, last_instance = {}, 0

return {
  config = function()
    local config = locky.config
    return {
      theme = config.theme, auto_unlock = config.auto_unlock, hour24 = config.hour24, privacy = config.privacy == true,
      message = type(config.message) == "string" and config.message or nil,
    }
  end,

  -- settings.json's packages, before init.lua runs. Returns a message for each one that failed.
  settings_packs = function(specs)
    local failures = {}
    for i, spec in ipairs(specs) do
      local ok, message = pcall(add_packs, { spec }, "settings", 0)
      if not ok then
        -- A position inside Locky's core says nothing to the user.
        failures[#failures + 1] = ("[%d] %s"):format(i, (tostring(message):gsub("^locky/_core%.lua:%d+: ", "")))
      end
    end
    return failures
  end,

  -- settings.json's values, after init.lua, so they win. Its theme changes apply as each theme loads.
  -- Returns a message for each value of the wrong type; those are skipped.
  apply_settings = function(settings)
    local failures = {}
    for _, key in ipairs({ "theme", "auto_unlock", "hour24", "privacy", "message" }) do
      local expected = ({ theme = "string", auto_unlock = "number", hour24 = "boolean", privacy = "boolean", message = "string" })[key]
      local value = settings[key]
      if value ~= nil and type(value) ~= expected then
        failures[#failures + 1] = ("%s: expected a %s, got %s"):format(key, expected, type(value))
      elseif value ~= nil then
        locky.config[key] = value
      end
    end
    settings_themes = type(settings.themes) == "table" and settings.themes or {}
    return failures
  end,

  load_theme = function(name)
    current_theme = load_theme(name)
    locky.theme.current = current_theme
    -- The host gets plain data; options stay here, so they may hold functions.
    local exported = tbl.extend("force", current_theme)
    exported.widgets = {}
    for i, placement in ipairs(current_theme.widgets) do
      exported.widgets[i] = tbl.extend("force", placement)
      exported.widgets[i].opts = nil
      local definition = widgets[placement.widget]
      exported.widgets[i].known = definition ~= nil
      exported.widgets[i].size = placement.size or (definition and definition.size)
      if placement.card == nil and definition then
        exported.widgets[i].card = definition.card
      end
    end
    return exported
  end,

  -- Makes the instance for current_theme.widgets[index]. Runs no plugin code.
  create = function(index)
    local placement = current_theme.widgets[index]
    local definition = widgets[placement.widget]
    if not definition then
      error(("no widget named %q"):format(placement.widget), 0)
    end
    last_instance = last_instance + 1
    local instance = raw_setmetatable({
      id = last_instance,
      name = definition.name,
      -- The widget's defaults, then the theme's options, then the user's: the user has the last word.
      opts = tbl.deep_extend("force", definition.opts or {}, placement.opts, locky.config.widgets[definition.name] or {}),
      state = {},
      theme = current_theme,
    }, Instance)
    instances[instance.id] = instance
    return instance.id
  end,

  init = function(id)
    local instance = instances[id]
    local definition = widgets[instance.name]
    if definition.init then
      definition.init(instance)
    end
  end,

  render = function(id)
    local instance = instances[id]
    if not instance then
      return nil
    end
    return widgets[instance.name].render(instance)
  end,

  dispose = function(id)
    instances[id] = nil
  end,

  pack_specs = function()
    return pack_specs
  end,

  -- Runs every lua/*/health.lua in the runtime path. Returns { sections = { { name, items } } }.
  health = function()
    report = { sections = {} }
    for _, entry in ipairs(native.find_all("lua", "/health.lua")) do
      local ok, module = pcall(require, entry.name .. ".health")
      locky.health.start(entry.name)
      if not ok then
        locky.health.error("health.lua failed: " .. tostring(module))
      elseif type(module) ~= "table" or type(module.check) ~= "function" then
        locky.health.error("health.lua must return { check = function() ... end }")
      else
        local checked, message = pcall(module.check)
        if not checked then
          locky.health.error("check() failed: " .. tostring(message))
        end
      end
    end
    local result = report
    report = nil
    return result
  end,

  theme_names = locky.theme.list,
  widget_names = locky.widget.list,

  -- Each theme's name, description, author, and folder, or the error that stops it from loading.
  theme_infos = function()
    local list = {}
    for _, name in ipairs(locky.theme.list()) do
      local ok, theme = pcall(read_theme, name)
      if ok then
        list[#list + 1] = { id = name, name = plain(theme.name) or name, description = plain(theme.description), author = plain(theme.author), dir = theme.dir }
      else
        list[#list + 1] = { id = name, name = name, error = tostring(theme) }
      end
    end
    return list
  end,

  -- The theme as init.lua and plugins leave it, before the window's changes: what Reset goes back to.
  theme_layout = function(name)
    local theme = normalize_theme(name, read_theme(name), false)
    local widgets_list = {}
    for i, placement in ipairs(theme.widgets) do
      widgets_list[i] = {
        widget = placement.widget, anchor = placement.anchor, offset = placement.offset, size = placement.size,
        align = placement.align, card = plain(placement.card), display = placement.display,
      }
    end
    return { id = name, name = theme.name, background = plain(theme.background), widgets = widgets_list }
  end,

  -- Every widget: name, description, and the file that defines it.
  widget_catalog = function()
    local list = {}
    for _, name in ipairs(locky.widget.list()) do
      local definition = widgets[name]
      list[#list + 1] = { name = name, description = plain(definition.description), file = definition.file }
    end
    return list
  end,
}
