-- calendar: this month as a grid, today marked. Starts on the user's first weekday, in their language.
--   Families: circular (weekday over the day), rectangular (this week), small (the month), medium (today and
--   the month), large (today over a big month).
--   opts.size, opts.today_color (default "accent"), opts.title (true: month and year above)
local ui = locky.ui

-- This month for a 7-column grid, Apple's way: weekday letters, then the days, today on a red disc.
-- width and height are the grid's; size is the day numbers' font size.
local function month(width, height, size)
  local now = os.date("*t")
  local locale = locky.date.locale()
  local first = os.date("*t", os.time({ year = now.year, month = now.month, day = 1, hour = 12 }))
  local days = os.date("*t", os.time({ year = now.year, month = now.month + 1, day = 0, hour = 12 })).day
  local lead = (first.wday - locale.first_weekday) % 7
  local w, h = width / 7, height / (math.ceil((lead + days) / 7) + 1)
  local cells = {}
  for i = 0, 6 do
    local symbol = locale.weekdays_short[(locale.first_weekday - 1 + i) % 7 + 1]
    cells[#cells + 1] = ui.text(symbol, { size = size - 1, weight = "semibold", color = "muted", width = w, height = h })
  end
  for _ = 1, lead do
    cells[#cells + 1] = ui.text(" ", { size = size, width = w, height = h })
  end
  local disc = math.min(w, h + 2)
  for day = 1, days do
    local today = day == now.day
    cells[#cells + 1] = ui.zstack {
      width = w, height = h,
      today and ui.circle({ width = disc, height = disc, color = "danger" }),
      ui.text(day, { size = size, weight = "semibold", mono = true, color = today and "white" or "fg" }),
    }
  end
  return ui.grid { columns = 7, spacing = 0, cells }
end

-- Apple's Calendar header: the weekday in red, the day big below it.
local function today(size)
  return ui.vstack {
    spacing = -4, align = "leading",
    ui.time("EEEE", ui.font("caption", { weight = "bold", case = "upper", color = "danger", tracking = 0.5 })),
    ui.time("d", { size = size, weight = "light", mono = true, numeric = false }),
  }
end

local function family(f)
  if f == "circular" then
    return ui.vstack {
      spacing = -4,
      ui.time("EEE", ui.font("caption", { weight = "bold", case = "upper" })),
      ui.time("d", { size = 30, weight = "semibold", mono = true, numeric = false }),
    }
  elseif f == "rectangular" then
    -- This week, today knocked out of a white disc.
    local now = os.date("*t")
    local locale = locky.date.locale()
    local back = (now.wday - locale.first_weekday) % 7
    local week = {}
    for i = 0, 6 do
      local d = os.date("*t", os.time({ year = now.year, month = now.month, day = now.day - back + i, hour = 12 }))
      local current = i == back
      week[#week + 1] = ui.vstack {
        spacing = 1, fill = "width",
        ui.text(locale.weekdays_short[d.wday], ui.font("caption2", { weight = "semibold", color = current and "fg" or "muted" })),
        ui.zstack {
          width = 22, height = 22,
          current and ui.circle({ width = 22, height = 22, color = "white" }),
          ui.text(d.day, ui.font("footnote", { weight = "semibold", mono = true, color = current and "black" or "fg" })),
        },
      }
    end
    return ui.vstack {
      spacing = 3, align = "leading", fill = "both",
      ui.time("skeleton:EEEEdMMM", ui.font("headline", { lines = 1 })),
      ui.hstack { spacing = 0, week },
    }
  elseif f == "small" then
    return ui.vstack {
      spacing = 4, align = "leading", fill = "both",
      ui.time("LLLL", ui.font("caption", { weight = "bold", case = "upper", color = "danger", tracking = 0.5 })),
      month(138, 118, 11),
    }
  elseif f == "medium" then
    return ui.hstack {
      spacing = 16, align = "top", fill = "both",
      ui.vstack {
        spacing = 0, align = "leading", fill = "height",
        today(54),
        ui.spacer(),
        ui.time("LLLL", ui.font("subheadline", { weight = "semibold" })),
        ui.time("yyyy", ui.font("subheadline", { color = "muted", mono = true })),
      },
      ui.spacer(),
      month(196, 138, 12),
    }
  end
  return ui.vstack {
    spacing = 0, align = "leading", fill = "both",
    ui.hstack {
      align = "bottom",
      today(60),
      ui.spacer(),
      ui.vstack {
        spacing = 0, align = "trailing", padding = { 0, 0, 10, 0 },
        ui.time("LLLL", ui.font("headline")),
        ui.time("yyyy", ui.font("subheadline", { color = "muted", mono = true })),
      },
    },
    ui.spacer(),
    month(332, 252, 16),
  }
end

locky.widget.define("calendar", {
  description = "This month, today marked",
  card = true,
  families = { "circular", "rectangular", "small", "medium", "large" },
  opts = { size = 12, title = true, today_color = "accent" },
  init = function(self)
    -- Redraw at each new day.
    self:every(3600, function(self) self:set({ day = os.date("*t").day }) end, { align = true })
  end,
  render = function(self)
    if self.family and self.family ~= "inline" then
      return family(self.family)
    end
    local o = self.opts
    local now = os.date("*t")
    local locale = locky.date.locale()
    local first = os.date("*t", os.time({ year = now.year, month = now.month, day = 1, hour = 12 }))
    local days = os.date("*t", os.time({ year = now.year, month = now.month + 1, day = 0, hour = 12 })).day
    local lead = (first.wday - locale.first_weekday) % 7
    local cells = {}
    for i = 0, 6 do
      local symbol = locale.weekdays_short[(locale.first_weekday - 1 + i) % 7 + 1]
      cells[#cells + 1] = ui.text(symbol, { size = o.size - 1, weight = "semibold", color = "muted", width = o.size * 2.2 })
    end
    for _ = 1, lead do
      cells[#cells + 1] = ui.text(" ", { size = o.size, width = o.size * 2.2 })
    end
    for day = 1, days do
      local today = day == now.day
      cells[#cells + 1] = ui.text(day, {
        size = o.size, mono = true, weight = today and "bold" or "regular", width = o.size * 2.2, height = o.size * 2,
        color = today and (o.today_text or "bg") or "fg",
        background = today and o.today_color or nil, radius = o.size,
      })
    end
    return ui.vstack {
      spacing = 8,
      o.title and ui.text(locky.date.format("LLLL yyyy"), { size = o.size + 2, weight = "semibold" }),
      ui.grid { columns = 7, spacing = 4, cells },
    }
  end,
})
