-- weather: the weather from wttr.in, kept for 30 minutes. Needs the network; shows nothing until the first reply.
--   opts.style      "line" (symbol, temperature, condition), "hero" (big temperature), "detail" (hero with feels-like,
--                   wind, humidity, sunrise and sunset), or "forecast" (three days)
--   opts.location   a city ("Tbilisi"), an airport code ("JFK"), "lat,lon", or "" (default) for wttr.in's guess
--   opts.units      "metric", "imperial", or nil to follow your region
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

locky.widget.define("weather", {
  description = "The weather where you are, from wttr.in",
  opts = { style = "line", location = "", every = 30, size = 15, place = true, multicolor = true },
  choices = { style = { "line", "hero", "detail", "forecast" } },
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
