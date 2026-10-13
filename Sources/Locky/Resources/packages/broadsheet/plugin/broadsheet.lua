-- Broadsheet's widgets: the parts of a newspaper's front page.
--   broadsheet.masthead   the paper's name between rules, and the dateline: volume (years since 1970), number
--                         (the day of the year), the date, and the edition. opts.title (default "The Daily Lock"),
--                         opts.width (default 1320)
--   broadsheet.section    a column's head: small capitals over a rule. opts.text, opts.width (default 360)
--   broadsheet.markets    the Mac's numbers as a stock table: CPU, memory, disk, and battery, each with its change
--                         since the last reading. opts.width (default 360), opts.every (seconds, default 30)
--   broadsheet.almanac    one line: sunrise and sunset (from wttr.in), the moon, and the days left in the year
--   broadsheet.rule       a thin vertical rule between columns; give it a size such as { 1, 300 }
local ui = locky.ui
local weather = require("locky.weather")
local sky = require("locky.sky")
local time = require("locky.time")

local roman = { { 1000, "M" }, { 900, "CM" }, { 500, "D" }, { 400, "CD" }, { 100, "C" }, { 90, "XC" }, { 50, "L" },
  { 40, "XL" }, { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }
local function numeral(n)
  local out = {}
  for _, pair in ipairs(roman) do
    while n >= pair[1] do
      out[#out + 1], n = pair[2], n - pair[1]
    end
  end
  return table.concat(out)
end

locky.widget.define("broadsheet.masthead", {
  description = "The paper's name and the dateline",
  opts = { title = "The Daily Lock", width = 1320 },
  init = function(self)
    self:every(3600, function(self) self:set({ now = os.time() }) end)
  end,
  render = function(self)
    local o, now = self.opts, self.state.now
    if not now then return nil end
    local t = os.date("*t", now)
    local small = { size = 12, font = "Copperplate", tracking = 1.5, color = "fg" }
    return ui.vstack {
      spacing = 8, width = o.width,
      ui.rect({ height = 3, fill = "width", color = "fg" }),
      ui.text(o.title, { size = 76, font = "Bodoni 72", weight = "bold", color = "fg", tracking = -1 }),
      ui.rect({ height = 1, fill = "width", color = "fg" }),
      ui.hstack {
        ui.text(("Vol. %s · No. %d"):format(numeral(t.year - 1969), t.yday), small),
        ui.spacer(),
        ui.text(locky.date.format("EEEE, MMMM d, yyyy", now), small),
        ui.spacer(),
        ui.text("Locked Edition · Free", small),
      },
      ui.rect({ height = 3, fill = "width", color = "fg" }),
    }
  end,
})

locky.widget.define("broadsheet.section", {
  description = "A column's head",
  opts = { text = "Weather", width = 360 },
  render = function(self)
    local o = self.opts
    return ui.vstack {
      spacing = 5, width = o.width, align = "leading",
      ui.text(o.text, { size = 14, font = "Copperplate", weight = "bold", tracking = 2, color = "fg" }),
      ui.rect({ height = 1, fill = "width", color = "fg" }),
    }
  end,
})

locky.widget.define("broadsheet.rule", {
  description = "A vertical rule",
  render = function(self)
    return ui.rect({ fill = true, color = "border" })
  end,
})

local function disk(self)
  self:system({ "df", "-k", "/System/Volumes/Data" }, function(self, result)
    local used, free = result.stdout:match("\n%S+%s+%d+%s+(%d+)%s+(%d+)")
    if used then
      local s = self.state
      s.disk = tonumber(used) / (tonumber(used) + tonumber(free)) * 100
      if s.current and not s.current.disk then
        s.current.disk = s.disk
        self:refresh()
      end
    end
  end)
end

locky.widget.define("broadsheet.markets", {
  description = "The Mac's numbers as a stock table",
  opts = { width = 360, every = 30 },
  init = function(self)
    -- CPU use is measured between two readings: take one now, and show the first a moment later.
    locky.sys.cpu()
    local function read(self)
      disk(self)
      local s = self.state
      local battery = locky.sys.battery()
      local now = { cpu = locky.sys.cpu().usage, mem = locky.sys.memory().percent, disk = s.disk, bat = battery.present and battery.percent or nil }
      self:set({ previous = s.current or now, current = now })
    end
    self:after(1.5, read)
    self:every(self.opts.every, read, { now = false })
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.current then return nil end
    local rows = {}
    for _, item in ipairs({ { "cpu", "CPU USAGE" }, { "mem", "MEMORY" }, { "disk", "DISK" }, { "bat", "BATTERY" } }) do
      local value, before = s.current[item[1]], s.previous[item[1]]
      if value then
        local change = before and value - before or 0
        local arrow = change > 0.05 and "▲" or change < -0.05 and "▼" or "■"
        rows[#rows + 1] = ui.hstack {
          width = o.width,
          ui.text(item[2], { size = 15, font = "Baskerville", weight = "semibold" }),
          ui.spacer(),
          ui.text(("%.1f%%"):format(value), { size = 15, font = "Baskerville", mono = true }),
          ui.text(("%s %.1f"):format(arrow, math.abs(change)), {
            size = 13, font = "Baskerville", width = 70, text_align = "trailing",
            color = change > 0.05 and "accent" or change < -0.05 and "success" or "muted",
          }),
        }
        rows[#rows + 1] = ui.rect({ height = 1, fill = "width", color = "border" })
      end
    end
    return ui.vstack { spacing = 7, width = o.width, rows }
  end,
})

locky.widget.define("broadsheet.almanac", {
  description = "Sunrise, sunset, the moon, and the days left in the year",
  opts = { location = "", every = 30 },
  init = function(self)
    weather.watch(self, self.opts, function(self, data)
      self:set({ rise = data and data.sunrise, set = data and data.sunset })
    end)
    self:every(3600, function(self) self:set({ now = os.time() }) end)
  end,
  render = function(self)
    local s = self.state
    if not s.now then return nil end
    local function clock(m)
      local t = os.date("*t")
      return locky.date.format("time", os.time({ year = t.year, month = t.month, day = t.day, hour = m // 60, min = m % 60 }))
    end
    local moon = sky.moon(s.now)
    local p = time.progress(s.now)
    local parts = {}
    if s.rise and s.set then
      parts[#parts + 1] = "Sunrise " .. clock(s.rise)
      parts[#parts + 1] = "Sunset " .. clock(s.set)
    end
    parts[#parts + 1] = moon.name .. ", " .. moon.illumination .. "% lit"
    parts[#parts + 1] = p.days_left_in_year .. " days left in the year"
    return ui.text("ALMANAC  —  " .. table.concat(parts, "  ·  "), { size = 13, font = "Baskerville", italic = true, color = "muted" })
  end,
})
