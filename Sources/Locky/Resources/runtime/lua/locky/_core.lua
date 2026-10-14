-- Locky's core. The host runs it once per Lua state, before any other code, with two arguments:
-- its native functions, and a function that says whether the current call has run out of time.
-- It builds the `locky` global and returns the entry points the host calls.
local native, budget_exceeded = ...

local type, pairs, ipairs, select, tostring, rawget, error = type, pairs, ipairs, select, tostring, rawget, error
local raw_pcall, raw_xpcall = pcall, xpcall
local raw_create, raw_resume = coroutine.create, coroutine.resume
local raw_getinfo = debug.getinfo
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

-------------------------------------------------------------------------------
-- Trust. Third-party plugins (folders in the pack folder) run programs and change files only when the user
-- allows it. Every Lua frame on the stack counts, and so does the code that resumed the running coroutine; code
-- loaded from a string counts as a plugin's. Locky's Lua makes no proper tail calls (see lparser.c), so a caller
-- never leaves the stack early. Defense in depth, not a sandbox: see docs/plugins.md.
-------------------------------------------------------------------------------

local sub, lower = string.sub, string.lower
local raw_running = coroutine.running
-- Plugin folder name (lowercase) → { system = true, files = true }: what locky.pack.add and settings.json allow.
local grants = {}
local capabilities = { system = { "run programs", "Run programs" }, files = { "change files", "Change files" } }
-- Each frame source → the plugin folder it is in, "" for code loaded from a string, or false for trusted code.
local plugin_of = {}
-- Each coroutine → the plugins that were on the stack when it was last resumed.
local resumed_by = raw_setmetatable({}, { __mode = "k" })

local function plugin_from(source)
  local name = plugin_of[source]
  if name == nil then
    if sub(source, 1, 1) == "@" then
      name = native.plugin_of(sub(source, 2)) or false
    else
      name = ""
    end
    plugin_of[source] = name
  end
  return name
end

-- The plugins with code on the stack, from `level` up, as a set of folder names.
local function plugins_on_stack(level)
  local found = {}
  for name in pairs(resumed_by[raw_running()] or {}) do
    found[name] = true
  end
  while true do
    local info = raw_getinfo(level + 1, "S")
    if not info then
      return found
    end
    if info.what ~= "C" then
      local name = plugin_from(info.source)
      if name then
        found[name] = true
      end
    end
    level = level + 1
  end
end

local core_source = raw_getinfo(1, "S").source

-- Whether the function `level` frames up was called under `name` by a Lua function outside the core. Anything else
-- is trusted code making the call for whoever handed it the function or the data, with no plugin frame left on the
-- stack: a metamethod, a for iterator, a C function such as pairs or pcall, the core, the host (a callback, or the
-- <close> variable of a closed coroutine), or code calling what a plugin put in place of a function it knows, such as
-- ipairs or locky.tbl.islist.
local function called_directly(level, name)
  local how, info = raw_getinfo(level + 1, "n"), raw_getinfo(level + 2, "S")
  return info ~= nil and info.what ~= "C" and info.source ~= core_source and how.namewhat ~= "metamethod"
    and how.name == name
end

-- Raises an error for the code `level` frames up unless every plugin on the stack may use `capability` and the
-- function the check guards was called directly.
local function require_grant(capability, what, level)
  local words = capabilities[capability]
  for name in pairs(plugins_on_stack(2)) do
    if name == "" then
      error(("%s: code loaded from a string may not %s"):format(what, words[1]), level + 1)
    end
    local granted = grants[lower(name)]
    if not (granted and granted[capability]) then
      error(("%s: plugin %q may not %s. To allow it, turn on %s for it in Settings › Plugins, or add allow = { %q } to its locky.pack.add entry in init.lua")
        :format(what, name, words[1], words[2], capability), level + 1)
    end
  end
  if not called_directly(level, what:match("[^.]+$")) then
    error(("%s: call it by its name from your own code, not through pcall, a callback, a metamethod, or another name")
      :format(what), level + 1)
  end
end

local function resume(co, ...)
  resumed_by[co] = plugins_on_stack(2)
  return rethrow_timeout(raw_resume(co, ...))
end
coroutine.resume = resume

coroutine.wrap = function(f)
  local co = raw_create(f)
  return function(...)
    local results = pack(resume(co, ...))
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
  -- "@" names a file: a string chunk must not pass for one, or for trusted code.
  if type(chunkname) == "string" and sub(chunkname, 1, 1) == "@" then
    chunkname = "=" .. sub(chunkname, 2)
  end
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
-- new files open. Writing, removing, and renaming files needs the "files" grant.
do
  local raw_open, raw_lines, raw_input, raw_output = io.open, io.lines, io.input, io.output
  local raw_remove, raw_rename, raw_tmpname = os.remove, os.rename, os.tmpname
  local find = string.find
  local function check(path)
    if type(path) == "string" and native.fs_kind(path) == "other" then
      error(path .. ": only regular files can be opened", 3)
    end
  end
  io.open = function(path, mode, ...)
    if type(mode) == "string" and find(mode, "[wa+]") then
      require_grant("files", "io.open", 2)
    end
    check(path)
    return raw_open(path, mode, ...)
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
    if type(file) == "string" then
      require_grant("files", "io.output", 2)
    end
    check(file)
    return raw_output(file)
  end
  os.remove = function(...)
    require_grant("files", "os.remove", 2)
    return raw_remove(...)
  end
  os.rename = function(...)
    require_grant("files", "os.rename", 2)
    return raw_rename(...)
  end
  os.tmpname = function()
    require_grant("files", "os.tmpname", 2)
    return raw_tmpname()
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
  local info = raw_getinfo(level + 1, "Sl")
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

-- The type of each setting. Lua and the host both read privacy and hour24 only as true or false, so another
-- value would hide names in widgets but not in the password field, or fail the host's whole config.
local setting_types = {
  theme = "string", hour24 = "boolean", privacy = "boolean", message = "string",
  background = "table", palette = "table", widgets = "table",
}

-- Once init.lua has run, the settings belong to the core: locky.config gives read-only views of them, so a plugin,
-- theme, or widget reads options but cannot change what the user set (privacy above all).
local frozen
local read_only = "locky.config is read-only once init.lua has run: set options in init.lua"
local raw_next, raw_rawset = next, rawset
local targets = raw_setmetatable({}, { __mode = "k" })  -- each view → the table it shows
local views = raw_setmetatable({}, { __mode = "k" })    -- each table → its view

local view_mt
local function view(t)
  if type(t) ~= "table" then
    return t
  end
  if not views[t] then
    local v = raw_setmetatable({}, view_mt)
    targets[v], views[t] = t, v
  end
  return views[t]
end
view_mt = {
  __index = function(v, key)
    return view(targets[v][key])
  end,
  __newindex = function()
    error(read_only, 2)
  end,
  __len = function(v)
    return #targets[v]
  end,
  __pairs = function(v)
    return function(_, key)
      local k, value = raw_next(targets[v], key)
      return k, view(value)
    end, v, nil
  end,
  __metatable = false,
}

function next(t, key)
  if targets[t] then
    local k, value = raw_next(targets[t], key)
    return k, view(value)
  end
  return raw_next(t, key)
end

function rawset(t, key, value)
  if targets[t] or (t == locky and key == "config") then
    error(read_only, 2)
  end
  return raw_rawset(t, key, value)
end

-- A copy of a table and the tables in it, read raw and without metatables.
local function raw_copy(t, seen)
  if type(t) ~= "table" then
    return t
  end
  seen = seen or {}
  if not seen[t] then
    local copy = {}
    seen[t] = copy
    for k, v in raw_next, t do
      copy[raw_copy(k, seen)] = raw_copy(v, seen)
    end
  end
  return seen[t]
end

-- The settings themselves, for the core: locky.config while init.lua runs, the frozen table after.
local function current_config()
  return frozen or rawget(locky, "config")
end

function locky.setup(opts)
  if frozen then
    error(read_only, 2)
  end
  validate("opts", opts, "table")
  for key, kind in pairs(setting_types) do
    validate("opts." .. key, opts[key], kind, true)
  end
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
  local source = raw_getinfo((level or 1) + 1, "S").source
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
    if locky.config.privacy == true then
      return { name = "Mac", host = "mac" }
    end
    return native.sys_hostname()
  end,
  user = function()
    if locky.config.privacy == true then
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
  format = function(template, time, zone)
    validate("template", template, "string")
    validate("time", time, "number", true)
    validate("zone", zone, "string", true)
    if template == "time" and type(locky.config.hour24) == "boolean" then
      template = locky.config.hour24 and "HH:mm" or "h:mm"
    end
    return native.date_format(template, time or os.time(), zone)
  end,
  --- The user's language, weekdays, months, first weekday, and hour24 (locky.config.hour24 when it is set).
  locale = function()
    local locale = native.locale()
    if type(locky.config.hour24) == "boolean" then
      locale.hour24 = locky.config.hour24
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
  require_grant("system", "locky.system", 3)
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

-- Apple's widget families, with their sizes in points: circular, rectangular, and inline as on the Lock Screen,
-- small, medium, and large as on the desktop. Inline fits its one line of text.
local families = {
  inline = false, circular = { 76, 76 }, rectangular = { 172, 76 },
  small = { 170, 170 }, medium = { 364, 170 }, large = { 364, 382 },
}
local family_names = "inline, circular, rectangular, small, medium, large"
local function is_family(v)
  return families[v] ~= nil, "expected a family: " .. family_names
end

--- Defines a widget. spec:
---   render(self)  required: returns a view built with locky.ui, or nil to show nothing
---   init(self)    optional: runs when the lock screen opens; start timers and processes here
---   opts          optional: default options; a theme's and the user's options merge into them
---   size          optional: { width, height } in points; without it the widget fits its content
---   card          optional: true to sit on the theme's card unless the theme says otherwise
---   families      optional: the families it draws, such as { "circular", "small" }; render reads self.family
---   choices       optional: the values an option takes, for Customize, such as
---                 { style = { "list", "dots" } }
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
  validate("spec.families", spec.families, function(v)
    if type(v) ~= "table" or not tbl.islist(v) then
      return false, "expected a list of families: " .. family_names
    end
    for _, family in ipairs(v) do
      if families[family] == nil then
        return false, ("unknown family %q: expected one of %s"):format(tostring(family), family_names)
      end
    end
    return true
  end, true)
  validate("spec.choices", spec.choices, function(v)
    local expected = "expected lists of strings by option, such as { style = { \"list\", \"dots\" } }"
    if type(v) ~= "table" then
      return false, expected
    end
    for key, list in pairs(v) do
      if type(key) ~= "string" or not tbl.islist(list) or #list == 0 then
        return false, expected
      end
      for _, item in ipairs(list) do
        if type(item) ~= "string" then
          return false, expected
        end
      end
    end
    return true
  end, true)
  local definition = tbl.extend("force", spec)
  definition.name = name
  definition.source = caller(2)
  local info = raw_getinfo(2, "S")
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

-- The options a placement of widget `name` gets: the widget's defaults, then the theme's, then init.lua's
-- (locky.setup({ widgets = ... })), then settings.json's. `with_settings = false` leaves settings.json's out.
local function widget_opts(name, placement, with_settings)
  local definition = widgets[name] or {}
  return tbl.deep_extend("force", definition.opts or {}, placement.opts or {}, current_config().widgets[name] or {},
    with_settings ~= false and placement.settings_opts or nil)
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
    }, theme.palette or {}, current_config().palette or {}),
    font = theme.font or {},
    background = background_from_settings and theme.background or current_config().background or theme.background or { color = "#000000" },
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
    validate(where .. ".family", entry.family, is_family, true)
    result.widgets[i] = {
      widget = widget,
      anchor = anchor,
      offset = point(where .. ".offset", entry.offset) or { 0, 0 },
      size = point(where .. ".size", entry.size),
      align = entry.align,
      card = entry.card,
      family = entry.family,
      display = entry.display or "main",
      opts = entry.opts or {},
      settings_opts = entry.settings_opts,
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

-- Customize's changes to themes, from settings.json: { [name] = { background = {...}, widgets = {...} } }.
local settings_themes = {}

local function placement_name(placement)
  return type(placement) == "table" and (placement.widget or placement[1]) or nil
end

-- What else a settings.json placement may say: see docs/themes.md.
local alignments = {
  center = true, leading = true, trailing = true, left = true, right = true, top = true, bottom = true,
  ["top-leading"] = true, ["top-trailing"] = true, ["bottom-leading"] = true, ["bottom-trailing"] = true,
  ["top-left"] = true, ["top-right"] = true, ["bottom-left"] = true, ["bottom-right"] = true,
}
local card_styles = { glass = true, solid = true, outline = true, none = true }

-- The fields of a background table (docs/themes.md) and their types; a list holds values of its type.
local background_fields = {
  shader = "string", image = "string", video = "string", color = "string", tint = "string", wallpaper = "boolean",
  blur = "number", dim = "number", speed = "number", resolution = "number", fps = "number", angle = "number",
  noise = "number", tint_amount = "number",
}
local background_lists = { colors = "string", gradient = "string", params = "number" }

-- A settings.json background with the fields Locky knows, each checked. Any other field is left out: it means
-- nothing to this version, and one nested deep enough would stop the theme from reaching the host.
local function settings_background(where, background)
  validate(where, background, "table")
  local result = {}
  for key, kind in pairs(background_fields) do
    validate(where .. "." .. key, background[key], kind, true)
    result[key] = background[key]
  end
  for key, kind in pairs(background_lists) do
    validate(where .. "." .. key, background[key], function(v)
      if tbl.islist(v) then
        for _, item in ipairs(v) do
          if type(item) ~= kind then
            return false, ("expected a list of %ss"):format(kind)
          end
        end
        return true
      end
      return false, ("expected a list of %ss"):format(kind)
    end, true)
    result[key] = background[key] and tbl.deepcopy(background[key])
  end
  return result
end

-- What the window changed in `theme`: its background, its widget list, and where its password field sits. A
-- widget entry with `ref` is the theme's own placement number `ref` (keeping its options) with the entry's
-- fields on top; an entry without `ref` adds a widget. Returns nil for no change; raises on a bad entry, so
-- nothing half-applies.
local function settings_edit(name, theme, edit)
  local where = "settings.json themes." .. name
  validate(where, edit, "table", true)
  if edit == nil or (edit.background == nil and edit.widgets == nil and edit.auth == nil) then
    return nil
  end
  local result = {}
  if edit.background ~= nil then
    result.background = settings_background(where .. ".background", edit.background)
  end
  if edit.auth ~= nil then
    validate(where .. ".auth", edit.auth, "table")
    validate(where .. ".auth.anchor", edit.auth.anchor, function(v)
      return anchors[v] ~= nil, "expected an anchor such as top or bottom-right"
    end, true)
    point(where .. ".auth.offset", edit.auth.offset)
    -- The place only: the rest of the field is the theme's.
    result.auth = { anchor = edit.auth.anchor, offset = edit.auth.offset and { edit.auth.offset[1], edit.auth.offset[2] } }
  end
  if edit.widgets ~= nil then
    validate(where .. ".widgets", edit.widgets, function(v)
      return tbl.islist(v), "expected a list of widget entries"
    end)
    -- Every field is checked before anything applies: one the theme cannot use would fail the whole theme.
    for i, entry in ipairs(edit.widgets) do
      local at = ("%s.widgets[%d]"):format(where, i)
      validate(at, entry, "table")
      validate(at .. ".ref", entry.ref, function(v)
        return type(v) == "number" and v >= 1 and v % 1 == 0, "expected a placement number, such as 2"
      end, true)
      validate(at .. ".widget", entry.widget, "string")
      validate(at .. ".anchor", entry.anchor, function(v)
        return anchors[v] ~= nil, "expected an anchor such as top or bottom-right"
      end, true)
      point(at .. ".offset", entry.offset)
      point(at .. ".size", entry.size)
      validate(at .. ".align", entry.align, function(v)
        return alignments[v] ~= nil, "expected an alignment such as leading, top, or bottom-trailing"
      end, true)
      validate(at .. ".card", entry.card, function(v)
        return type(v) == "boolean" or card_styles[v] ~= nil, "expected true, false, or a card style: glass, solid, outline, none"
      end, true)
      validate(at .. ".family", entry.family, is_family, true)
      validate(at .. ".display", entry.display, function(v)
        return v == "main" or v == "all", "expected \"main\" or \"all\""
      end, true)
      validate(at .. ".opts", entry.opts, "table", true)
    end
    -- An entry with `ref` keeps the theme's placement, if it is still there. After the theme changed, it takes
    -- the first unused placement of the same widget, once every exact ref has taken its own: a stale ref must
    -- not take a placement another entry names. A widget the theme no longer has is dropped.
    local original, used, bases, list = theme.widgets or {}, {}, {}, {}
    for i, entry in ipairs(edit.widgets) do
      if entry.ref ~= nil and placement_name(original[entry.ref]) == entry.widget and not used[entry.ref] then
        bases[i], used[entry.ref] = entry.ref, true
      end
    end
    for i, entry in ipairs(edit.widgets) do
      if entry.ref ~= nil and not bases[i] then
        for j, placement in ipairs(original) do
          if not used[j] and placement_name(placement) == entry.widget then
            bases[i], used[j] = j, true
            break
          end
        end
      end
    end
    for i, entry in ipairs(edit.widgets) do
      local base = bases[i]
      if entry.ref == nil or base then
        local placement = {}
        if base then
          for key, value in pairs(original[base]) do
            placement[key] = value
          end
          placement[1] = nil
        end
        placement.widget = entry.widget
        for _, key in ipairs({ "anchor", "align", "card", "family", "display" }) do
          if entry[key] ~= nil then
            placement[key] = entry[key]
          end
        end
        -- x and y only: whatever else the list holds must not reach the host.
        for _, key in ipairs({ "offset", "size" }) do
          if entry[key] ~= nil then
            placement[key] = { entry[key][1], entry[key][2] }
          end
        end
        -- Kept apart from the theme's options: they merge last, over init.lua's locky.setup({ widgets = ... }).
        placement.settings_opts = entry.opts and tbl.deepcopy(entry.opts)
        list[#list + 1] = placement
      end
    end
    result.widgets = list
  end
  return result
end

-- Themes being derived, so a theme that derives from itself fails instead of looping.
local deriving = {}

--- A theme made in the Themes window (Duplicate Theme, Import Theme): theme `base` with `def.edits` applied in
--- order, each a change as settings.json's themes.<name> holds one, and `def.name` as its name. The changes' widget
--- options become the theme's own, so init.lua's merge over them. See docs/themes.md.
function locky.theme.derive(base, def)
  validate("base", base, "string")
  validate("def", def, "table")
  validate("def.name", def.name, "string", true)
  validate("def.edits", def.edits, "table", true)
  if deriving[base] then
    error(("theme %q derives from itself"):format(base), 2)
  end
  deriving[base] = true
  local ok, theme = pcall(read_theme, base)
  deriving[base] = nil
  if not ok then
    error(theme, 0)
  end
  for _, edit in ipairs(def.edits or {}) do
    local change = settings_edit(base, theme, edit)
    if change then
      theme.background = change.background or theme.background
      if change.widgets then
        for _, placement in ipairs(change.widgets) do
          placement.opts = tbl.deep_extend("force", placement.opts or {}, placement.settings_opts or {})
          placement.settings_opts = nil
        end
        theme.widgets = change.widgets
      end
      if change.auth then
        theme.auth = tbl.deep_extend("force", type(theme.auth) == "table" and theme.auth or {}, change.auth)
      end
    end
  end
  theme.description = ("Made from %s."):format(type(theme.name) == "string" and theme.name or base)
  theme.name = def.name or theme.name
  return theme
end

-- An error without a position inside Locky's core, which says nothing to the user.
local function without_core_position(message)
  return (tostring(message):gsub("^locky/_core%.lua:%d+: ", ""))
end

-- The theme with settings.json's change, unless `with_edit` is false. A change that fails is reported in
-- `problems` and left out, so the theme still loads; `edited` says whether one applied.
local function load_theme(name, with_edit)
  local theme = read_theme(name)
  local problems = {}
  local edit
  if with_edit ~= false then
    local ok, result = pcall(settings_edit, name, theme, settings_themes[name])
    if ok then
      edit = result
    else
      problems[1] = without_core_position(result)
    end
  end
  if edit then
    local background, widgets, auth = theme.background, theme.widgets, theme.auth
    theme.background = edit.background or background
    theme.widgets = edit.widgets or widgets
    if edit.auth then
      theme.auth = tbl.deep_extend("force", type(auth) == "table" and auth or {}, edit.auth)
    end
    local ok, normalized = pcall(normalize_theme, name, theme, edit.background ~= nil)
    if ok then
      normalized.edited = true
      normalized.problems = problems
      return normalized
    end
    -- Checked above, so this should not happen; if it does, the theme still loads.
    problems[#problems + 1] = ("settings.json themes.%s: %s"):format(name, without_core_position(normalized))
    theme.background, theme.widgets, theme.auth = background, widgets, auth
  end
  local normalized = normalize_theme(name, theme, false)
  normalized.edited = false
  normalized.problems = problems
  return normalized
end

-- A copy with only strings, numbers, booleans, and tables: for data the host reads. The host takes string keys
-- and a list without gaps, nothing else, and a table 16 levels down is left out, so a cycle ends. Raw access:
-- a metamethod must not fail the copy.
local function plain(value, depth, seen)
  depth = depth or 0
  local kind = type(value)
  if kind == "string" or kind == "number" or kind == "boolean" then
    return value
  elseif kind ~= "table" or depth >= 16 then
    return nil
  end
  -- Each table is copied once: a table that refers to itself, even many times over, cannot grow the copy.
  seen = seen or {}
  if seen[value] then
    return nil
  end
  seen[value] = true
  local copy = {}
  for key, item in next, value do
    if type(key) == "string" then
      copy[key] = plain(item, depth + 1, seen)
    end
  end
  for i = 1, rawlen(value) do
    copy[i] = plain(rawget(value, i), depth + 1, seen)
    if copy[i] == nil then
      break
    end
  end
  return copy
end

-- A field the host reads as text: a string, or nothing.
local function text(value)
  return type(value) == "string" and value or nil
end

-- An error as text. Only a string or a number: tostring would run an error object's own __tostring, which may fail.
local function error_text(e)
  if type(e) == "string" or type(e) == "number" then
    return tostring(e)
  end
  return ("(error object is a %s value)"):format(type(e))
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
  validate("spec.allow", spec.allow, function(v)
    if not tbl.islist(v) then
      return false, "expected a list, such as { \"system\", \"files\" }"
    end
    for _, capability in ipairs(v) do
      if not capabilities[capability] then
        return false, "expected \"system\" or \"files\", got " .. tostring(capability)
      end
    end
    return true
  end, true)
  -- git would read a leading "-" as an option.
  validate("spec.src", spec.src, function(v)
    return v == nil or v:sub(1, 1) ~= "-", "must not start with '-'"
  end)
  validate("spec.version", spec.version, function(v)
    return v == nil or v:sub(1, 1) ~= "-", "must not start with '-'"
  end)
  -- A NUL byte in git's arguments ends the app: Foundation raises an Objective-C exception for it.
  for _, field in ipairs({ "src", "version", "name", "dir" }) do
    validate("spec." .. field, spec[field], function(v)
      return v == nil or not v:find("%c"), "must not contain control characters"
    end)
  end
  local src = spec.src
  if src and src:match("^[%w_.-]+/[%w_.-]+$") then
    src = "https://github.com/" .. src
  end
  -- Encrypted sources only: anyone on the network can change what http:// and git:// send. A local folder is
  -- { dir = ... }.
  validate("spec.src", src, function(v)
    return v == nil or v:match("^https://") or v:match("^ssh://") or v:match("^git@"),
      "use \"user/repo\" for GitHub, or an https://, ssh://, or git@ address (not http:// or file://; for a local folder, use dir = ...)"
  end)
  -- Copied with the core's own functions: a module init.lua required may have changed locky.tbl.
  local allow = {}
  for i, capability in ipairs(spec.allow or {}) do
    allow[i] = capability
  end
  local name = spec.name or (spec.dir and spec.dir:match("([^/]+)/*$")) or src:match("([^/]+)/*$"):gsub("%.git$", "")
  validate("spec.name", name, function(v)
    return v:match("^[%w_.-]+$") ~= nil and v ~= "." and v ~= "..", "expected letters, digits, '_', '-', and '.'"
  end)
  return { name = name, src = src, version = spec.version, dir = spec.dir and locky.fs.expand(spec.dir), allow = allow }
end

-- `from` is "settings" for Settings › Plugins' packages (settings.json) and "config" for init.lua's.
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
      local granted = {}
      for _, capability in ipairs(normalized.allow) do
        granted[capability] = true
      end
      grants[lower(normalized.name)] = granted
      native.pack_add(normalized.name, normalized.dir)
    end
  end
end

--- Adds plugins: "user/repo", a git URL, or { src = ..., version = "v1.2.0" | branch | commit, name = ... }.
--- { dir = "~/code/my-plugin" } adds a local folder, for writing a plugin.
--- allow = { "system", "files" } lets a plugin run programs and change files.
function locky.pack.add(specs)
  -- A plugin adding packages could grant itself anything.
  if raw_next(plugins_on_stack(1)) ~= nil or not called_directly(1, "add") then
    error("locky.pack.add: only init.lua and your own config may add plugins", 2)
  end
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
    -- As the Lua side reads them: hour24 only as true or false, privacy only when true.
    local hour24 = config.hour24
    if type(hour24) ~= "boolean" then
      hour24 = nil
    end
    return {
      -- Only whether auto_unlock is set: it is gone, and the host says so.
      theme = config.theme, auto_unlock = config.auto_unlock ~= nil, hour24 = hour24, privacy = config.privacy == true,
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

  -- After init.lua: from here on locky.config is read-only.
  freeze_config = function()
    -- A copy: a module init.lua required may hold the table itself, or have given it a metatable.
    frozen = raw_copy(rawget(locky, "config"))
    raw_rawset(locky, "config", nil)
    raw_setmetatable(locky, {
      __index = function(_, key)
        if key == "config" then
          return view(frozen)
        end
      end,
      __newindex = function(t, key, value)
        if key == "config" then
          error(read_only, 2)
        end
        raw_rawset(t, key, value)
      end,
      __metatable = false,
    })
  end,

  -- settings.json's values, after init.lua, so they win. Its theme changes apply as each theme loads.
  -- Returns a message for each value of the wrong type; those are skipped.
  apply_settings = function(settings)
    local failures = {}
    for _, key in ipairs({ "theme", "hour24", "privacy", "message" }) do
      local expected = ({ theme = "string", hour24 = "boolean", privacy = "boolean", message = "string" })[key]
      local value = settings[key]
      if value ~= nil and type(value) ~= expected then
        failures[#failures + 1] = ("%s: expected a %s, got %s"):format(key, expected, type(value))
      elseif value ~= nil then
        current_config()[key] = value
      end
    end
    settings_themes = type(settings.themes) == "table" and settings.themes or {}
    return failures
  end,

  -- `with_edit = false` leaves settings.json's change out: for a change only the host can find bad, such as a
  -- shader that is not there. `edited` in the result says whether a change applied.
  load_theme = function(name, with_edit)
    current_theme = load_theme(name, with_edit)
    locky.theme.current = current_theme
    -- The host gets plain data: options keep their functions here, and the host gets a plain copy of each
    -- placement's options, to tell whether a widget changed when the theme editor's preview loads the theme again.
    local exported = tbl.extend("force", current_theme)
    exported.widgets = {}
    for i, placement in ipairs(current_theme.widgets) do
      exported.widgets[i] = tbl.extend("force", placement)
      local ok, opts = pcall(widget_opts, placement.widget, placement)
      exported.widgets[i].opts = ok and plain(opts) or nil
      exported.widgets[i].settings_opts = nil
      local definition = widgets[placement.widget]
      exported.widgets[i].known = definition ~= nil
      local family = families[placement.family]
      if placement.family and definition and definition.families and not tbl.contains(definition.families, placement.family) then
        current_theme.problems[#current_theme.problems + 1] = ("theme.widgets[%d]: %s has no %s layout; it draws %s"):format(
          i, placement.widget, placement.family, table.concat(definition.families, ", "))
      end
      exported.widgets[i].size = placement.size or (family and { family[1], family[2] }) or (definition and definition.size)
      if placement.card == nil and placement.family then
        -- Desktop families sit on the theme's card; Lock Screen ones on the bare screen, the circle on a disc.
        local system = placement.family == "small" or placement.family == "medium" or placement.family == "large"
        exported.widgets[i].card = system or placement.family == "circular"
      elseif placement.card == nil and definition then
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
      -- The user has the last word, and the window's layer wins, as everywhere.
      opts = widget_opts(definition.name, placement),
      -- Apple's family the placement asks for, or nil: the widget's own size.
      family = placement.family,
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

  -- Each theme's name, description, author, folder, and palette, or the error that stops it from loading. The
  -- window reads the list at once, so a theme that fails it gets an error row of its own.
  theme_infos = function()
    local list = {}
    for _, name in ipairs(locky.theme.list()) do
      local ok, info = pcall(function()
        local theme = read_theme(name)
        return {
          id = name, name = text(theme.name) or name, description = text(theme.description), author = text(theme.author),
          dir = text(theme.dir), palette = plain(theme.palette),
        }
      end)
      list[#list + 1] = ok and info or { id = name, name = name, error = error_text(info) }
    end
    return list
  end,

  -- The theme as init.lua and plugins leave it, before the window's changes: what Reset goes back to. Each
  -- placement's options are the ones it gets before settings.json's.
  theme_layout = function(name)
    local theme = normalize_theme(name, read_theme(name), false)
    local widgets_list = {}
    for i, placement in ipairs(theme.widgets) do
      local ok, opts = pcall(widget_opts, placement.widget, placement, false)
      widgets_list[i] = {
        widget = placement.widget, anchor = placement.anchor, offset = placement.offset, size = placement.size,
        align = placement.align, card = plain(placement.card), family = placement.family, display = placement.display,
        opts = ok and plain(opts) or nil,
      }
    end
    return {
      id = name, name = theme.name, background = plain(theme.background), widgets = widgets_list,
      auth = { anchor = theme.auth.anchor, offset = plain(theme.auth.offset) }, card_style = text(theme.card.style),
    }
  end,

  -- Every widget: name, description, the file that defines it, whether it sits on a card by default, its own
  -- options, the same with init.lua's, and the values its options take. Like theme_infos, one widget that fails
  -- gets an error row.
  widget_catalog = function()
    local list = {}
    for _, name in ipairs(locky.widget.list()) do
      local definition = widgets[name]
      local ok, info = pcall(function()
        -- init.lua's options may not be a table: the row still lists the widget.
        local opts_ok, opts = pcall(widget_opts, name, {}, false)
        return {
          name = name, description = text(definition.description), file = text(definition.file), card = definition.card == true,
          opts = opts_ok and plain(opts) or nil, defaults = plain(definition.opts), choices = plain(definition.choices),
          families = plain(definition.families),
        }
      end)
      list[#list + 1] = ok and info or { name = name, error = error_text(info) }
    end
    return list
  end,
}
