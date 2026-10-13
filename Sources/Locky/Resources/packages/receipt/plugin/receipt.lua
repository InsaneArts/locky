-- Receipt's widget: the lock screen as a thermal till receipt, every line a reading of the Mac.
--   receipt.slip   the receipt. opts.store (default "LOCKY MART"), opts.width (characters per line, default 36),
--                  opts.size (default 14), opts.location (for the weather line, as the weather widget's)
local ui = locky.ui
local weather = require("locky.weather")
local sky = require("locky.sky")

local function line(left, right, width)
  right = right or ""
  local gap = width - utf8.len(left) - utf8.len(right)
  if gap < 1 then
    left = left:sub(1, math.max(1, #left + gap - 1))
    gap = 1
  end
  return left .. string.rep(" ", gap) .. right
end

local function center(text, width)
  local pad = math.max(0, (width - utf8.len(text)) // 2)
  return string.rep(" ", pad) .. text
end

local function span(seconds)
  local d, h, m = seconds // 86400, seconds % 86400 // 3600, seconds % 3600 // 60
  return d > 0 and ("%dD %dH"):format(d, h) or h > 0 and ("%dH %02dM"):format(h, m) or ("%d MIN"):format(m)
end

locky.widget.define("receipt.slip", {
  description = "The lock screen as a till receipt",
  opts = { store = "LOCKY MART", width = 36, size = 14, location = "", every = 30 },
  init = function(self)
    self.state.since = os.time()
    locky.sys.cpu()
    weather.watch(self, self.opts, function(self, data) self:set({ weather = data }) end)
    self:system({ "df", "-k", "/System/Volumes/Data" }, function(self, result)
      local free = result.stdout:match("\n%S+%s+%d+%s+%d+%s+(%d+)")
      if free then self:set({ free = tonumber(free) * 1024 }) end
    end)
    local function read(self)
      self:set({ now = os.time(), cpu = locky.sys.cpu().usage, memory = locky.sys.memory().percent, battery = locky.sys.battery() })
    end
    self:after(1, read)
    self:every(60, read, { now = false, align = true })
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.now then return nil end
    local w = o.width
    local rule, double = string.rep("-", w), string.rep("=", w)
    local items = {}
    local function item(label, value)
      if value then items[#items + 1] = line(label, value, w) end
    end
    item("UPTIME", span(locky.sys.uptime()))
    item("BATTERY", s.battery.present and (s.battery.percent .. "%" .. (s.battery.charging and " CHG" or "")) or nil)
    item("CPU", ("%.0f%%"):format(s.cpu))
    item("MEMORY", ("%.0f%%"):format(s.memory))
    item("DISK FREE", s.free and ("%.0f GB"):format(s.free / 1e9) or nil)
    if s.weather then
      item("WEATHER", ("%s° %s"):format(s.weather.temp or "?", (s.weather.condition or ""):upper()))
    end
    local moon = sky.moon(s.now)
    item("MOON", ("%s %d%%"):format(moon.name:upper(), moon.illumination))
    local user = locky.sys.user().name:upper()
    local lines = {
      center("* " .. o.store .. " *", w),
      center("LOCK SCREENS & SUNDRIES", w),
      center(("STORE #%03d  REG 01"):format(tonumber(os.date("%j", s.now))), w),
      rule,
      line(os.date("%a %d %b %Y", s.now):upper(), locky.date.format("HH:mm", s.now), w),
      line("CASHIER: " .. user, "TRN " .. (s.since % 10000), w),
      rule,
    }
    for _, entry in ipairs(items) do lines[#lines + 1] = entry end
    lines[#lines + 1] = rule
    lines[#lines + 1] = line("SUBTOTAL", #items .. " ITEMS", w)
    lines[#lines + 1] = line("AWAY", span(s.now - s.since), w)
    lines[#lines + 1] = double
    lines[#lines + 1] = line("TOTAL DUE", "ONE PASSWORD", w)
    lines[#lines + 1] = double
    local text = {}
    for i, entry in ipairs(lines) do
      text[i] = ui.text(entry, { size = o.size, font = "Menlo", color = "ink", lines = 1, weight = (i == 1 or entry:match("^TOTAL")) and "bold" or nil })
    end
    -- A barcode from the lock's time: bar widths from its digits.
    local bars = {}
    local digits = tostring(s.since) .. tostring(s.since * 7)
    for i = 1, #digits do
      local d = tonumber(digits:sub(i, i))
      bars[#bars + 1] = ui.rect({ width = 1 + d % 3, height = 46, color = "ink" })
      bars[#bars + 1] = ui.rect({ width = 1 + (d * 7) % 3, height = 46, color = "paper" })
    end
    local char = o.size * 0.602
    local paper_width = w * char + 48
    local teeth = {}
    local n = 24
    for i = 0, n do
      teeth[#teeth + 1] = { i / n, (i % 2 == 0) and 1 or 0 }
    end
    local function edge(flip)
      local points = { { 0, flip and 0 or 1 } }
      for _, pt in ipairs(teeth) do points[#points + 1] = { pt[1], flip and 1 - pt[2] or pt[2] } end
      points[#points + 1] = { 1, flip and 0 or 1 }
      return ui.polygon({ points = points, width = paper_width, height = 8, color = "paper" })
    end
    return ui.vstack {
      spacing = 0, rotation = -1.2,
      edge(false),
      ui.vstack {
        spacing = 3, padding = { 22, 24, 26, 24 }, background = "paper", width = paper_width, align = "leading",
        text,
        ui.hstack { spacing = 0, padding = { 12, 0, 6, 0 }, width = w * char, ui.spacer(), ui.hstack { spacing = 0, bars }, ui.spacer() },
        ui.text(center("THANK YOU  ·  COME AGAIN", w), { size = o.size, font = "Menlo", color = "ink" }),
      },
      edge(true),
    }
  end,
})
