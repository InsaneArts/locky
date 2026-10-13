-- worldclock: the time in other cities.
--   opts.zones   a list of { "City", "Area/Zone" } (default Tokyo, London, New York); zone names as in
--                /usr/share/zoneinfo, such as "Europe/Berlin" or "America/Los_Angeles"
--   opts.style   "rows" (default) or "columns"; opts.size, opts.color
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

locky.widget.define("worldclock", {
  description = "The time in other cities",
  opts = { style = "rows", size = 14, zones = { { "Tokyo", "Asia/Tokyo" }, { "London", "Europe/London" }, { "New York", "America/New_York" } } },
  choices = { style = { "rows", "columns" } },
  init = function(self)
    self:every(60, function(self)
      local now = os.time()
      local here = offset(locky.date.format("ZZZZZ", now))
      local today = locky.date.format("yyyyMMdd", now)
      local list = {}
      for _, zone in ipairs(self.opts.zones) do
        local day = locky.date.format("yyyyMMdd", now, zone[2])
        list[#list + 1] = {
          name = zone[1], time = locky.date.format("time", now, zone[2]),
          hour = tonumber(locky.date.format("H", now, zone[2])),
          note = day > today and "tomorrow" or day < today and "yesterday" or nil,
          diff = difference(offset(locky.date.format("ZZZZZ", now, zone[2])) - here),
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
