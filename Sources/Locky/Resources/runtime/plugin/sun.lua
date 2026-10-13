-- sun: the sun's path from sunrise to sunset, where it is now, and the day's length. Sunrise and sunset come
-- from wttr.in, like the weather widget's (one request serves both); without the network it shows nothing.
--   Families: inline and circular (the next sunrise or sunset), rectangular, small, and medium (with the sun's
--   path over the whole day, after Apple Weather's sunrise and sunset).
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

-- The sun's path over the whole day, `w` by `h` points, as Apple Weather draws it: a curve that crosses the
-- horizon at sunrise and sunset, bright by day and dim by night, with the sun on it now.
local function path(s, w, h)
  local noon = (s.rise + s.set) / 2
  local pad = 6
  local function at(m)
    local e = math.cos(2 * math.pi * (m - noon) / 1440)
    return { m / 1440 * w, pad + (1 - e) / 2 * (h - 2 * pad) }
  end
  -- A curve from minute a to b as a ribbon `t` points thick, its points as fractions of the frame.
  local function ribbon(a, b, t)
    local top, bottom = {}, {}
    local steps = math.max(math.ceil((b - a) / 20), 2)
    for i = 0, steps do
      local m = a + (b - a) * i / steps
      local p, q = at(m - 1), at(m + 1)
      local dx, dy = q[1] - p[1], q[2] - p[2]
      local len = math.sqrt(dx * dx + dy * dy)
      local nx, ny = -dy / len * t / 2, dx / len * t / 2
      local c = at(m)
      top[#top + 1] = { (c[1] + nx) / w, (c[2] + ny) / h }
      bottom[#bottom + 1] = { (c[1] - nx) / w, (c[2] - ny) / h }
    end
    for i = #bottom, 1, -1 do
      top[#top + 1] = bottom[i]
    end
    return top
  end
  local horizon = at(s.rise)[2]
  local glow = {}
  for i = 0, 24 do
    local p = at(s.rise + (s.set - s.rise) * i / 24)
    glow[#glow + 1] = { p[1] / w, p[2] / h }
  end
  local sun = at(s.now)
  local up = s.now >= s.rise and s.now <= s.set
  return ui.zstack {
    width = w, height = h,
    ui.polygon({ points = glow, color = { "#ffffff40", "#ffffff00", angle = 180 }, width = w, height = h }),
    ui.line({ width = w, stroke_width = 1, color = "fg", opacity = 0.3, offset = { 0, horizon - h / 2 } }),
    ui.polygon({ points = ribbon(0, 1440, 2), color = "fg", opacity = 0.3, width = w, height = h }),
    ui.polygon({ points = ribbon(s.rise, s.set, 2.5), color = "fg", width = w, height = h }),
    ui.dot({ size = up and 11 or 8, color = "fg", opacity = up and 1 or 0.6, glow = up and 6 or nil, offset = { sun[1] - w / 2, sun[2] - h / 2 } }),
  }
end

-- Apple's layouts: the next sunrise or sunset big, the other one under it.
local function family(s, f)
  local up = s.now >= s.rise and s.now < s.set
  local name, time, symbol = "Sunset", clock(s.set), "sunset.fill"
  local other = "Sunrise " .. clock(s.rise)
  if not up then
    name, time, symbol, other = "Sunrise", clock(s.rise), "sunrise.fill", "Sunset " .. clock(s.set)
  end
  if f == "inline" then
    return ui.hstack { spacing = 4, ui.symbol(symbol, ui.font("subheadline")), ui.text(name .. " " .. time, ui.font("subheadline", { mono = true })) }
  elseif f == "circular" then
    return ui.vstack {
      spacing = 3,
      ui.symbol(symbol, { size = 22, weight = "medium" }),
      ui.text(time, { size = 15, weight = "semibold", mono = true }),
    }
  elseif f == "rectangular" then
    return ui.vstack {
      spacing = 4, align = "leading", fill = "both",
      ui.hstack { spacing = 5, ui.symbol(symbol, ui.font("headline")), ui.text(name .. " " .. time, ui.font("headline", { mono = true })) },
      path(s, 172, 48),
    }
  end
  local header = ui.vstack {
    spacing = 0, align = "leading",
    ui.hstack { spacing = 4, ui.symbol(symbol, ui.font("footnote", { weight = "semibold" })), ui.text(name, ui.font("subheadline", { weight = "semibold" })), color = "muted" },
    ui.text(time, ui.font("large_title", { weight = "medium", mono = true })),
  }
  if f == "small" then
    return ui.vstack {
      spacing = 0, align = "leading", fill = "both",
      header,
      ui.spacer(),
      path(s, 138, 46),
      ui.text(other, ui.font("footnote", { weight = "medium", color = "muted", mono = true, padding = { 4, 0, 0, 0 } })),
    }
  end
  return ui.vstack {
    spacing = 0, fill = "both",
    ui.hstack {
      align = "top",
      header,
      ui.spacer(),
      ui.vstack {
        spacing = 2, align = "trailing", padding = { 4, 0, 0, 0 },
        ui.text(other, ui.font("subheadline", { weight = "medium", mono = true })),
        ui.text("Daylight " .. span(s.set - s.rise), ui.font("subheadline", { color = "muted", mono = true })),
      },
    },
    ui.spacer(),
    path(s, 332, 56),
  }
end

locky.widget.define("sun", {
  description = "Sunrise, sunset, and the sun's path today",
  opts = { width = 240, location = "", every = 30, size = 12, color = "warning", path = "muted" },
  families = { "inline", "circular", "rectangular", "small", "medium" },
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
    if self.family then
      return family(s, self.family)
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
