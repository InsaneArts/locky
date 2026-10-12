---@meta locky
-- Type stubs for lua-language-server: completion and type checks for Locky's API.
-- Point workspace.library at this folder; see docs/plugins.md. This file is never run.
error("Cannot require a meta file")

---@alias locky.Color string A palette role ("fg", "muted", "accent", ...), a color name, or "#rrggbb[aa]".
---@alias locky.Paint locky.Color|{ [integer]: locky.Color, angle: number? } A color, or a gradient.
---@alias locky.Anchor "top"|"top-left"|"top-right"|"left"|"center"|"right"|"bottom"|"bottom-left"|"bottom-right"
---@alias locky.Event "lock"|"unlock"|"auth_failed"|"auth_shown"|"auth_hidden"
---@alias locky.Timer integer
---@alias locky.Process integer

---@class locky.View: table A view built with locky.ui.

---@class locky.ViewProps
---@field size number? Font size, or a dot's diameter, a ring's diameter, a progress bar's height.
---@field weight ("ultralight"|"thin"|"light"|"regular"|"medium"|"semibold"|"bold"|"heavy"|"black")?
---@field design ("default"|"rounded"|"serif"|"monospaced")?
---@field font string? A font family, such as "Futura".
---@field mono boolean? Digits of one width.
---@field tracking number? Letter spacing.
---@field italic boolean?
---@field skew number? Degrees of slant, for faces without an italic.
---@field case ("upper"|"lower")?
---@field lines integer? Most lines to show.
---@field text_align ("leading"|"center"|"trailing")?
---@field line_spacing number?
---@field numeric boolean? Digits roll when the text changes.
---@field color locky.Paint?
---@field opacity number?
---@field spacing number?
---@field align string? "leading", "center", "trailing", "top", "bottom", "top-leading", ...
---@field columns integer? A grid's cells per row.
---@field padding number|number[]? One number, { vertical, horizontal }, or { top, leading, bottom, trailing }.
---@field width number?
---@field height number?
---@field max_width number?
---@field fill (boolean|"width"|"height")?
---@field offset number[]? { x, y }
---@field rotation number? Degrees, clockwise.
---@field scale number?
---@field background (locky.Paint|"glass")?
---@field radius number?
---@field border locky.Paint?
---@field border_width number?
---@field shadow number?
---@field shadow_color locky.Color?
---@field glow (boolean|number)?
---@field blur number?
---@field stroke locky.Paint?
---@field stroke_width number?
---@field min number?
---@field max number?
---@field slots integer?
---@field style string? A chart's "line", "area", or "bar".
---@field fit ("fill"|"fit")?
---@field tint boolean?
---@field mode ("hierarchical"|"palette"|"multicolor")?
---@field colors locky.Color[]?
---@field animate ("smooth"|"spring"|"linear")?
---@field id string?
---@field points number[][]? A polygon's corners: { {x, y}, ... } as fractions of its frame.

---@class locky.ui
locky_ui = {}
---@param t (locky.View|locky.View[]|false|nil|locky.ViewProps)[]|locky.ViewProps
---@return locky.View
function locky_ui.vstack(t) end
---@param t (locky.View|locky.View[]|false|nil|locky.ViewProps)[]|locky.ViewProps
---@return locky.View
function locky_ui.hstack(t) end
---@param t (locky.View|locky.View[]|false|nil|locky.ViewProps)[]|locky.ViewProps
---@return locky.View
function locky_ui.zstack(t) end
---@param t (locky.View|locky.View[]|false|nil|locky.ViewProps)[]|locky.ViewProps
---@return locky.View
function locky_ui.grid(t) end
---@param value string|number
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.text(value, props) end
---Live time or date text: "time", "date", or a template such as "HH", "mm", "EEEE d MMMM".
---@param format string
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.time(format, props) end
---@param name string An SF Symbol name.
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.symbol(name, props) end
---@param path string Absolute, "~/...", or relative to the calling plugin's package.
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.image(path, props) end
---@param value number 0 to 1
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.progress(value, props) end
---@param value number 0 to 1
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.ring(value, props) end
---@param values number[]
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.chart(values, props) end
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.rect(props) end
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.circle(props) end
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.capsule(props) end
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.line(props) end
---@param props locky.ViewProps|{ points: number[][] }?
---@return locky.View
function locky_ui.polygon(props) end
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.dot(props) end
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.spacer(props) end
---@param props locky.ViewProps?
---@return locky.View
function locky_ui.divider(props) end
---@generic T
---@param list T[]
---@param fn fun(item: T, index: integer): locky.View?
---@return locky.View[]
function locky_ui.each(list, fn) end
---@param value any
---@return boolean
function locky_ui.is_view(value) end

---@class locky.Widget
---@field id integer
---@field name string
---@field opts table Options: the definition's defaults, then the theme's, then the user's.
---@field state table Your data.
---@field theme locky.Theme
local Widget = {}
---Merges `patch` into self.state and draws the widget again.
---@param patch table
function Widget:set(patch) end
function Widget:refresh() end
---Calls fn(self) now and every `seconds` (0.05 or more).
---@param seconds number
---@param fn fun(self: locky.Widget)
---@param opts { now: boolean?, align: boolean? }?
---@return locky.Timer
function Widget:every(seconds, fn, opts) end
---@param seconds number
---@param fn fun(self: locky.Widget)
---@return locky.Timer
function Widget:after(seconds, fn) end
---@param cmd string[]
---@param opts locky.SystemOpts?
---@param on_exit fun(self: locky.Widget, result: locky.SystemResult)?
---@return locky.Process
function Widget:system(cmd, opts, on_exit) end
---@param event locky.Event
---@param fn fun(self: locky.Widget, data: any)
function Widget:on(event, fn) end
function Widget:log(...) end

---@class locky.WidgetSpec
---@field render fun(self: locky.Widget): locky.View?
---@field init fun(self: locky.Widget)?
---@field opts table?
---@field size number[]? { width, height }; without it the widget fits its content.
---@field card boolean? Sit on the theme's card unless the theme says otherwise.
---@field description string?

---@class locky.SystemOpts
---@field cwd string?
---@field env table<string, string>?
---@field stdin string?
---@field timeout number? Seconds, default 10.

---@class locky.SystemResult
---@field code integer
---@field signal integer
---@field stdout string
---@field stderr string
---@field timed_out boolean

---@class locky.Placement
---@field [1] string The widget's name.
---@field widget string?
---@field anchor locky.Anchor?
---@field offset number[]?
---@field size number[]?
---@field align string?
---@field card (boolean|"glass"|"solid"|"outline"|"none")?
---@field display ("main"|"all")?
---@field opts table?

---@class locky.Theme
---@field name string?
---@field description string?
---@field author string?
---@field palette table<string, string>?
---@field font { family: string?, design: string?, weight: string? }?
---@field background table?
---@field overlay table? Drawn above the widgets with transparency; same tables as background.
---@field card { style: string?, radius: number?, fill: locky.Color?, border: locky.Color? }?
---@field auth { style: ("pill"|"underline"|"box"|"terminal"|"minimal")?, anchor: locky.Anchor?, offset: number[]?, width: number?, avatar: boolean?, name: boolean?, hint: boolean?, placeholder: string?, prompt: string?, font: table?, reveal: ("always"|"activity")?, idle: number?, dim: number?, focus: string?, hint_align: ("center"|"leading")?, glow: (number|boolean)?, ring: { width: number?, fill: string?, glow: boolean? }? }?
---@field widgets locky.Placement[]?

---@class locky.PackSpec
---@field src string? A git URL, or "user/repo" for GitHub.
---@field version string? A tag, branch, or commit.
---@field name string?
---@field dir string? A local folder instead of git.

---@class locky
locky = {}
---@type string
locky.version = ""
---@type { theme: string, auto_unlock: number, background: table?, palette: table, widgets: table, hour24: boolean?, privacy: boolean, message: string? }
locky.config = {}
---@param opts { theme: string?, auto_unlock: number?, background: table?, palette: table<string, string>?, widgets: table<string, table>?, hour24: boolean?, privacy: boolean?, message: string? }
function locky.setup(opts) end
locky.ui = locky_ui

locky.widget = {}
---@param name string
---@param spec locky.WidgetSpec
---@return table
function locky.widget.define(name, spec) end
---@param name string
---@return locky.WidgetSpec?
function locky.widget.get(name) end
---@return string[]
function locky.widget.list() end

locky.theme = {}
---@type locky.Theme?
locky.theme.current = nil
---@param name string
---@param patch locky.Theme|fun(theme: locky.Theme): locky.Theme?
function locky.theme.extend(name, patch) end
---@return string[]
function locky.theme.list() end

locky.pack = {}
---@param specs (string|locky.PackSpec)[]|locky.PackSpec
function locky.pack.add(specs) end

---@param fn function
---@param seconds number?
---@return locky.Timer
function locky.defer(fn, seconds) end
---@param fn function
---@return locky.Timer
function locky.schedule(fn) end
---@param timer locky.Timer
function locky.cancel(timer) end
---Seconds since 1970 with fractions.
---@return number
function locky.now() end
---@param event locky.Event
---@param fn fun(data: any)
function locky.on(event, fn) end
---@param cmd string[]
---@param opts locky.SystemOpts|fun(result: locky.SystemResult)?
---@param on_exit fun(result: locky.SystemResult)?
---@return locky.Process
function locky.system(cmd, opts, on_exit) end
---@param process locky.Process
function locky.kill(process) end

locky.sys = {}
---@return { present: boolean, percent: integer?, charging: boolean?, plugged: boolean?, state: string?, remaining: integer?, until_full: integer? }
function locky.sys.battery() end
---@return { usage: number, cores: integer }
function locky.sys.cpu() end
---@return { total: integer, used: integer, percent: number }
function locky.sys.memory() end
---@return integer
function locky.sys.uptime() end
---@return { name: string, host: string }
function locky.sys.hostname() end
---@return { name: string, full_name: string }
function locky.sys.user() end
---@return { name: string, version: string, codename: string, build: string }
function locky.sys.os() end
---@return { model: string, chip: string, cores: integer, memory: integer }
function locky.sys.machine() end
---@return { id: string, name: string, language: string }
function locky.sys.keyboard() end
---@return integer
function locky.sys.displays() end
---@return string?
function locky.sys.wallpaper() end
---@return string[]
function locky.sys.wallpaper_colors() end
---@return { width: number, height: number, scale: number, layout_width: number, layout_height: number }
function locky.sys.screen() end

locky.date = {}
---@param template string
---@param time number?
---@return string
function locky.date.format(template, time) end
---@return { identifier: string, language: string, hour24: boolean, first_weekday: integer, weekdays: string[], weekdays_short: string[], weekdays_abbreviated: string[], months: string[], months_short: string[] }
function locky.date.locale() end

locky.fs = {}
---@type string
locky.fs.home = ""
---@param path string
---@return string?, string?
function locky.fs.read(path) end
---@param path string
---@return boolean
function locky.fs.exists(path) end
---@param path string
---@return boolean
function locky.fs.is_dir(path) end
---@param dir string
---@return string[]?, string?
function locky.fs.list(dir) end
---@param path string
---@return string
function locky.fs.expand(path) end
---@return string
function locky.fs.join(...) end
---@return string?
function locky.fs.package_dir() end

locky.json = {}
---@param value any
---@return string
function locky.json.encode(value) end
---@param text string
---@return any
function locky.json.decode(text) end

locky.tbl = {}
---@param behavior "force"|"keep"|"error"
---@return table
function locky.tbl.deep_extend(behavior, ...) end
---@param behavior "force"|"keep"|"error"
---@return table
function locky.tbl.extend(behavior, ...) end
---@generic T
---@param t T
---@return T
function locky.tbl.deepcopy(t) end
---@return boolean
function locky.tbl.islist(t) end
---@return boolean
function locky.tbl.isempty(t) end
---@return any[]
function locky.tbl.keys(t) end
---@return any[]
function locky.tbl.values(t) end
---@return table
function locky.tbl.map(fn, t) end
---@return any[]
function locky.tbl.filter(fn, t) end
---@return boolean
function locky.tbl.contains(t, value) end
---@return integer
function locky.tbl.count(t) end
---@return any
function locky.tbl.get(t, ...) end

locky.str = {}
---@param s string
---@param separator string
---@param opts { trimempty: boolean? }?
---@return string[]
function locky.str.split(s, separator, opts) end
---@return string
function locky.str.trim(s) end
---@return boolean
function locky.str.startswith(s, prefix) end
---@return boolean
function locky.str.endswith(s, suffix) end

---@return string
function locky.inspect(value) end
---@param name string
---@param value any
---@param expected string|string[]|fun(value: any): boolean, string?
---@param optional boolean?
function locky.validate(name, value, expected, optional) end
---@param message any
---@param level ("debug"|"info"|"warn"|"error")?
function locky.notify(message, level) end
locky.log = {}
function locky.log.debug(...) end
function locky.log.info(...) end
function locky.log.warn(...) end
function locky.log.error(...) end

locky.health = {}
---@param name string
function locky.health.start(name) end
---@param message string
function locky.health.ok(message) end
---@param message string
function locky.health.info(message) end
---@param message string
---@param advice string?
function locky.health.warn(message, advice) end
---@param message string
---@param advice string?
function locky.health.error(message, advice) end
