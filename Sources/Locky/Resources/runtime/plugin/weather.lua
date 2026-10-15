-- weather: the weather from Open-Meteo, kept for 30 minutes. Needs the network; shows nothing until the first reply.
--   Families: inline, circular (today's range, the temperature on it), rectangular, small, medium (with the next
--   hours), large (with the next days).
--   opts.style      without a family: "line" (symbol, temperature, condition), "hero" (big temperature), "detail" (hero with feels-like,
--                   wind, humidity, sunrise and sunset), or "forecast" (three days)
--   opts.location   "lat,lon" (what Customize writes), a place's name ("Tbilisi"), or "" (default) for the Mac's
--                   location: Location Services' once allowed, else its time zone's city
--   opts.place_name the name shown for "lat,lon"
--   opts.units      "automatic" (default: the Mac's temperature unit), "celsius", or "fahrenheit"
--   opts.every      minutes a reply is kept (default 30)
--   opts.place      false hides the place's name (privacy mode always does)
--   opts.size, opts.color, opts.multicolor (false draws the symbols in the text color)
local ui = locky.ui
local weather = require("locky.weather")

-- Minutes after midnight as the system's time, 12- or 24-hour.
local function clock(minutes)
  local today = os.date("*t")
  return locky.date.format("time", os.time({ year = today.year, month = today.month, day = today.day, hour = minutes // 60, min = minutes % 60 }))
end

local function weekday(date)
  local y, m, d = tostring(date or ""):match("^(%d+)-(%d+)-(%d+)$")
  if not y then
    return ""
  end
  return locky.date.format("EEE", os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }))
end

-- Apple's temperature colors, cold to hot, for the range gauge and bars.
local warmth = { "#5ac8fa", "#34c759", "#ffcc00", "#ff9500" }

local function deg(t)
  return t and (t .. "°") or "–"
end

local function hour_label(at, first)
  return first and "Now" or locky.date.format("skeleton:j", at)
end

local function symbol(name, size, o)
  return ui.symbol(name, { size = size, mode = o.multicolor ~= false and "multicolor" or nil })
end

-- One day's range as a bar on the week's: Apple's daily forecast.
local function range_bar(low, high, min, max, width)
  local span = math.max(max - min, 1)
  local x = (low - min) / span * width
  local w = math.max((high - low) / span * width, 6)
  return ui.zstack {
    align = "leading", width = width,
    ui.capsule({ color = "#ffffff26", width = width, height = 5 }),
    ui.capsule({ color = { warmth[1], warmth[3], warmth[4], angle = 90 }, width = w, height = 5, offset = { x, 0 } }),
  }
end

local function family(w, o, f)
  local place = o.place ~= false and w.place or "My Location"
  local hl = ("H:%s L:%s"):format(deg(w.high), deg(w.low))
  if f == "inline" then
    return ui.hstack { spacing = 4, symbol(w.symbol, 15, { multicolor = false }), ui.text(deg(w.temp) .. " " .. w.condition, ui.font("subheadline", { lines = 1 })) }
  elseif f == "circular" then
    local low, high = w.low or w.temp or 0, w.high or w.temp or 1
    return ui.gauge(w.temp or low, {
      min = math.min(low, w.temp or low), max = math.max(high, w.temp or high), size = 64,
      value_label = deg(w.temp), min_label = tostring(low), max_label = tostring(high),
      color = { warmth[1], warmth[2], warmth[3], warmth[4], angle = 90 },
    })
  elseif f == "rectangular" then
    return ui.vstack {
      spacing = 1, align = "leading", fill = "both",
      ui.hstack { spacing = 5, symbol(w.symbol, 15, { multicolor = false }), ui.text(place, ui.font("headline", { lines = 1 })) },
      ui.text(deg(w.temp) .. " " .. w.condition, ui.font("subheadline", { lines = 1 })),
      ui.text(hl, ui.font("subheadline", { color = "muted", lines = 1 })),
    }
  end
  local header = ui.vstack {
    spacing = 0, align = "leading",
    ui.hstack { spacing = 4, ui.text(place, ui.font("subheadline", { weight = "semibold", lines = 1 })), w.place and o.place ~= false and nil or ui.symbol("location.fill", { size = 10 }) },
    ui.text(deg(w.temp), { size = 44, weight = "light", mono = true }),
  }
  local summary = function(align)
    return ui.vstack {
      spacing = 2, align = align,
      symbol(w.symbol, 17, o),
      ui.text(w.condition, ui.font("footnote", { weight = "semibold", lines = 1 })),
      ui.text(hl, ui.font("footnote", { weight = "semibold", lines = 1 })),
    }
  end
  if f == "small" then
    return ui.vstack { spacing = 0, align = "leading", fill = "both", header, ui.spacer(), summary("leading") }
  end
  local hours = ui.hstack {
    ui.each(w.hours or {}, function(h, i)
      return ui.vstack {
        spacing = 6, fill = "width",
        ui.text(hour_label(h.at, i == 1), ui.font("caption", { weight = "semibold", color = "muted" })),
        symbol(h.symbol, 18, o),
        ui.text(deg(h.temp), ui.font("subheadline", { weight = "medium", mono = true })),
      }
    end),
  }
  local top = ui.hstack { align = "top", header, ui.spacer(), summary("trailing") }
  if f == "medium" then
    return ui.vstack { spacing = 0, fill = "both", top, ui.spacer(), hours }
  end
  local lo, hi = math.huge, -math.huge
  for _, d in ipairs(w.days or {}) do
    lo, hi = math.min(lo, d.low or lo), math.max(hi, d.high or hi)
  end
  local days = ui.each(w.days or {}, function(d, i)
    return ui.hstack {
      spacing = 10,
      ui.text(i == 1 and "Today" or weekday(d.date), ui.font("subheadline", { weight = "semibold", width = 54, text_align = "leading" })),
      symbol(d.symbol, 17, { multicolor = o.multicolor, width = 28 }),
      ui.spacer(),
      ui.text(deg(d.low), ui.font("subheadline", { weight = "medium", color = "muted", mono = true, width = 36, text_align = "trailing" })),
      d.low and d.high and range_bar(d.low, d.high, lo, hi, 96),
      ui.text(deg(d.high), ui.font("subheadline", { weight = "medium", mono = true, width = 36, text_align = "trailing" })),
    }
  end)
  local function detail(icon, label, value)
    return ui.vstack {
      spacing = 3, align = "leading", fill = "width",
      ui.hstack { spacing = 3, ui.symbol(icon, { size = 10, weight = "semibold" }), ui.text(label, ui.font("caption2", { weight = "semibold", case = "upper", lines = 1 })), color = "muted" },
      ui.text(value, ui.font("title3", { weight = "medium", mono = true })),
    }
  end
  return ui.vstack {
    spacing = 14, fill = "both",
    top, hours,
    ui.divider(),
    ui.vstack { spacing = 12, days },
    ui.spacer(),
    ui.hstack {
      align = "top",
      detail("thermometer.medium", "Feels", deg(w.feels)),
      detail("humidity", "Humidity", (w.humidity or "–") .. "%"),
      detail("wind", "Wind", tostring(w.wind or "–")),
      detail("sun.max", "UV", tostring(w.uv or "–")),
    },
  }
end

locky.widget.define("weather", {
  description = "The weather where you are, from Open-Meteo",
  opts = { style = "line", location = "", units = "automatic", every = 30, size = 15, place = true, multicolor = true },
  choices = { style = { "line", "hero", "detail", "forecast" }, units = { "automatic", "celsius", "fahrenheit" } },
  families = { "inline", "circular", "rectangular", "small", "medium", "large" },
  init = function(self)
    weather.watch(self, self.opts, function(self, data)
      self:set({ data = data })
    end)
  end,
  render = function(self)
    local o, w = self.opts, self.state.data
    if not w then
      return nil
    end
    if self.family then
      return family(w, o, self.family)
    end
    local s = o.size
    local function symbol(name, size)
      return ui.symbol(name, { size = size, mode = o.multicolor and "multicolor" or nil, color = o.multicolor and nil or o.color })
    end
    local deg = function(t)
      return t and (t .. "°") or "–"
    end
    local place = o.place ~= false and w.place
    if o.style == "line" then
      return ui.hstack {
        spacing = s * 0.5,
        symbol(w.symbol, s * 1.2),
        ui.text(deg(w.temp), { size = s, weight = "semibold", mono = true, color = o.color }),
        ui.text(w.condition .. (place and (" · " .. place) or ""), { size = s, color = o.muted or "muted", lines = 1 }),
      }
    end
    if o.style == "forecast" then
      local columns = {}
      for i, day in ipairs(w.days) do
        columns[i] = ui.vstack {
          spacing = s * 0.4, width = s * 4,
          ui.text(i == 1 and "Today" or weekday(day.date), { size = s * 0.8, weight = "semibold", color = "muted", case = "upper", tracking = 1 }),
          symbol(day.symbol, s * 1.6),
          ui.text(deg(day.high) .. "  " .. deg(day.low), { size = s * 0.85, mono = true, color = o.color }),
        }
      end
      return ui.hstack { spacing = s, columns }
    end
    local hero = ui.hstack {
      spacing = s,
      symbol(w.symbol, s * 3),
      ui.vstack {
        spacing = 2, align = "leading",
        ui.text(deg(w.temp), { size = s * 3, weight = "light", mono = true, color = o.color }),
        ui.text(w.condition, { size = s, weight = "medium", color = o.color, lines = 1 }),
        ui.text(("H %s  L %s%s"):format(deg(w.high), deg(w.low), place and ("  ·  " .. place) or ""), { size = s * 0.85, color = "muted", lines = 1 }),
      },
    }
    if o.style ~= "detail" then
      return hero
    end
    local function row(icon, label, value)
      return ui.hstack {
        spacing = 8,
        ui.symbol(icon, { size = s * 0.85, color = "muted", width = s * 1.3 }),
        ui.text(label, { size = s * 0.85, color = "muted" }),
        ui.spacer(),
        ui.text(value, { size = s * 0.85, mono = true, color = o.color }),
      }
    end
    return ui.vstack {
      spacing = s * 0.8, align = "leading",
      hero,
      ui.vstack {
        spacing = 6, width = s * 16,
        row("thermometer.medium", "Feels like", deg(w.feels)),
        row("wind", "Wind", ("%s %s %s"):format(w.wind or "–", w.wind_unit, w.wind_dir or "")),
        row("humidity", "Humidity", (w.humidity or "–") .. "%"),
        w.sunrise and row("sunrise", "Sunrise", clock(w.sunrise)),
        w.sunset and row("sunset", "Sunset", clock(w.sunset)),
      },
    }
  end,
})
