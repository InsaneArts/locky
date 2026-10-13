-- worldclock: the time in other cities.
--   opts.zones   a list of { "City", "Area/Zone" } (default Tokyo, London, New York); zone names as in
--                /usr/share/zoneinfo, such as "Europe/Berlin" or "America/Los_Angeles"
--   opts.style   "rows" (default) or "columns"; opts.size, opts.color
--   Families: inline and circular (the first city), rectangular and small (the cities and their times), medium
--   (Apple's four faces: your city first, white by day and dark by night).
local ui = locky.ui

-- "+09:00" → minutes east of UTC.
local function offset(text)
  local sign, h, m = tostring(text):match("^([+-])(%d%d):?(%d%d)$")
  if not sign then
    return 0
  end
  local minutes = tonumber(h) * 60 + tonumber(m)
  return sign == "-" and -minutes or minutes
end

local function difference(minutes)
  if minutes == 0 then
    return "same time"
  end
  local h, m = math.abs(minutes) // 60, math.abs(minutes) % 60
  return (minutes > 0 and "+" or "−") .. h .. (m > 0 and (":" .. ("%02d"):format(m)) or "") .. "h"
end

-- "Today, +3h", as under Apple's world clock faces.
local function day_and_hours(c)
  local h = c.delta / 60
  local hours = (h >= 0 and "+" or "−") .. (math.abs(h) == math.floor(math.abs(h)) and ("%d"):format(math.abs(h)) or ("%.1f"):format(math.abs(h))) .. "h"
  return (c.note and (c.note:sub(1, 1):upper() .. c.note:sub(2)) or "Today") .. ", " .. hours
end

-- An analog face with hour and minute ticks: white by day, dark by night, or bare on the Lock Screen's disc.
local function face(d, c, bare)
  local r = d / 2
  local day = c.hour >= 6 and c.hour < 18
  local ink = bare and "fg" or day and "#000000" or "#ffffff"
  local children = { not bare and ui.circle({ width = d, height = d, color = day and "#ffffff" or "#1c1c1e" }) }
  for i = 0, 59 do
    local hour = i % 5 == 0
    local length = r * (hour and 0.12 or 0.06)
    children[#children + 1] = ui.rect({
      width = r * (hour and 0.04 or 0.02), height = length, color = ink, opacity = hour and 0.9 or 0.35,
      offset = { 0, -(r * 0.92 - length / 2) }, rotation = i * 6,
    })
  end
  if bare then
    children[#children + 1] = ui.text(c.name:sub(1, (utf8.offset(c.name, 4) or #c.name + 1) - 1), {
      size = r * 0.24, weight = "semibold", case = "upper", color = ink, offset = { 0, -r * 0.38 },
    })
  end
  local minutes = c.min
  local hours = (c.hour % 12) + minutes / 60
  local function hand(length, angle)
    return ui.capsule({ width = r * 0.1, height = length, color = ink, offset = { 0, -length / 2 + r * 0.05 }, rotation = angle })
  end
  children[#children + 1] = hand(r * 0.55, hours * 30)
  children[#children + 1] = hand(r * 0.85, minutes * 6)
  children[#children + 1] = ui.circle({ width = r * 0.16, height = r * 0.16, color = ink })
  return ui.zstack { width = d, height = d, children }
end

local function family(f, list)
  local first = list[1]
  if f == "inline" then
    return ui.hstack {
      spacing = 4,
      ui.symbol("globe", ui.font("subheadline")),
      ui.text(first.name .. " " .. first.time, ui.font("subheadline", { weight = "semibold", mono = true, lines = 1 })),
    }
  elseif f == "circular" then
    return face(70, first, true)
  elseif f == "medium" then
    return ui.hstack {
      spacing = 0, fill = "both",
      ui.each({ table.unpack(list, 1, 4) }, function(c)
        return ui.vstack {
          spacing = 1, fill = "width",
          face(74, c),
          ui.text(c.name, ui.font("caption", { weight = "semibold", lines = 1, padding = { 8, 0, 0, 0 } })),
          ui.text(day_and_hours(c), ui.font("caption2", { color = "muted", lines = 1 })),
        }
      end),
    }
  end
  -- rectangular and small: a city on each line, the time on the right.
  local small = f == "small"
  return ui.vstack {
    spacing = small and 0 or 2, align = "leading", fill = "both",
    ui.each({ table.unpack(list, 1, small and 4 or 3) }, function(c, i)
      return {
        small and i > 1 and ui.spacer(),
        ui.hstack {
          spacing = 6,
          ui.vstack {
            spacing = 0, align = "leading",
            ui.text(c.name, ui.font(small and "subheadline" or "headline", { weight = "semibold", lines = 1 })),
            small and ui.text(day_and_hours(c), ui.font("caption", { color = "muted", lines = 1 })),
          },
          ui.spacer(),
          ui.text(c.time, ui.font(small and "title3" or "headline", { weight = small and "regular" or "semibold", mono = true })),
        },
      }
    end),
  }
end

locky.widget.define("worldclock", {
  description = "The time in other cities",
  opts = { style = "rows", size = 14, zones = { { "Tokyo", "Asia/Tokyo" }, { "London", "Europe/London" }, { "New York", "America/New_York" } } },
  choices = { style = { "rows", "columns" } },
  families = { "inline", "circular", "rectangular", "small", "medium" },
  init = function(self)
    -- Apple's medium widget starts with your own city (none in privacy mode: it would say where the Mac is).
    local zones = self.opts.zones
    if self.family == "medium" and #zones < 4 then
      zones = { { locky.config.privacy ~= true and locky.date.format("VVV") or "Local" }, table.unpack(zones) }
    end
    self:every(60, function(self)
      local now = os.time()
      local here = offset(locky.date.format("ZZZZZ", now))
      local today = locky.date.format("yyyyMMdd", now)
      local list = {}
      for _, zone in ipairs(zones) do
        local day = locky.date.format("yyyyMMdd", now, zone[2])
        list[#list + 1] = {
          name = zone[1], time = locky.date.format("time", now, zone[2]),
          hour = tonumber(locky.date.format("H", now, zone[2])),
          note = day > today and "tomorrow" or day < today and "yesterday" or nil,
          diff = difference(offset(locky.date.format("ZZZZZ", now, zone[2])) - here),
          min = tonumber(locky.date.format("m", now, zone[2])),
          delta = offset(locky.date.format("ZZZZZ", now, zone[2])) - here,
        }
      end
      self:set({ list = list })
    end, { align = true })
  end,
  render = function(self)
    local o, list = self.opts, self.state.list
    if not list then
      return nil
    end
    if self.family == "inline" or self.family == "circular" or self.family == "rectangular" or self.family == "small" or self.family == "medium" then
      return family(self.family, list)
    end
    local s = o.size
    local function sky(hour)
      return (hour >= 7 and hour < 19) and "sun.max.fill" or "moon.fill"
    end
    local items = {}
    for i, c in ipairs(list) do
      if o.style == "columns" then
        items[i] = ui.vstack {
          spacing = 3,
          ui.text(c.name, { size = s * 0.8, color = "muted", case = "upper", tracking = 1 }),
          ui.text(c.time, { size = s * 1.8, weight = "medium", mono = true, color = o.color }),
          ui.text(c.note or c.diff, { size = s * 0.75, color = "muted" }),
        }
      else
        items[i] = ui.hstack {
          spacing = s * 0.6, width = s * 17,
          ui.symbol(sky(c.hour), { size = s * 0.9, color = "muted", width = s * 1.2 }),
          ui.text(c.name, { size = s, weight = "medium", color = o.color }),
          ui.text(c.note and (c.diff .. " · " .. c.note) or c.diff, { size = s * 0.8, color = "muted", lines = 1 }),
          ui.spacer(),
          ui.text(c.time, { size = s * 1.2, mono = true, color = o.color }),
        }
      end
    end
    if o.style == "columns" then
      return ui.hstack { spacing = s * 2, items }
    end
    return ui.vstack { spacing = s * 0.6, items }
  end,
})
