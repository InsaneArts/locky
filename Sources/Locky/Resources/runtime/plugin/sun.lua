-- sun: the sun's path from sunrise to sunset, where it is now, and the day's length. Sunrise and sunset come
-- from wttr.in, like the weather widget's (one request serves both); without the network it shows nothing.
--   opts.width      the path's width in points (default 240); its height is a third of that
--   opts.location, opts.every   as the weather widget's
--   opts.size, opts.color (the sun, default "warning"), opts.path (the dotted path, default "muted")
local ui = locky.ui
local weather = require("locky.weather")

local function clock(minutes)
  local today = os.date("*t")
  return locky.date.format("time", os.time({ year = today.year, month = today.month, day = today.day, hour = minutes // 60, min = minutes % 60 }))
end

local function span(minutes)
  return ("%dh %02dm"):format(minutes // 60, minutes % 60)
end

locky.widget.define("sun", {
  description = "Sunrise, sunset, and the sun's path today",
  opts = { width = 240, location = "", every = 30, size = 12, color = "warning", path = "muted" },
  init = function(self)
    weather.watch(self, self.opts, function(self, data)
      self:set({ rise = data and data.sunrise, set = data and data.sunset })
    end)
    self:every(60, function(self)
      local t = os.date("*t")
      self:set({ now = t.hour * 60 + t.min })
    end, { align = true })
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.rise or not s.set or not s.now or s.set <= s.rise then
      return nil
    end
    local w = o.width
    local h = w / 3
    local day = s.set - s.rise
    local f = (s.now - s.rise) / day
    local up = f >= 0 and f <= 1
    local function at(x)
      return { -w / 2 + w * x, h / 2 - h * math.sin(math.pi * x) }
    end
    local path = {}
    for i = 0, 24 do
      local p = at(i / 24)
      path[#path + 1] = ui.dot({ size = 3, color = o.path, opacity = 0.6, offset = p })
    end
    local note
    if up then
      note = span(s.set - s.now) .. " of daylight left"
    else
      local to = (s.rise - s.now) % 1440
      note = "Sunrise in " .. span(to)
    end
    return ui.vstack {
      spacing = 8,
      ui.zstack {
        width = w + 16, height = h + 16,
        ui.line({ width = w + 16, stroke_width = 1, color = o.path, opacity = 0.5, offset = { 0, h / 2 } }),
        ui.each(path, function(dot) return dot end),
        up and ui.dot({ size = 14, color = o.color, glow = 8, offset = at(f) }),
      },
      ui.hstack {
        width = w + 16,
        ui.text(clock(s.rise), { size = o.size, mono = true }),
        ui.spacer(),
        ui.text(note, { size = o.size - 1, color = "muted" }),
        ui.spacer(),
        ui.text(clock(s.set), { size = o.size, mono = true }),
      },
    }
  end,
})
