-- calendar: this month as a grid, today marked. Starts on the user's first weekday, in their language.
--   opts.size, opts.today_color (default "accent"), opts.title (true: month and year above)
local ui = locky.ui

locky.widget.define("calendar", {
  description = "This month, today marked",
  card = true,
  opts = { size = 12, title = true, today_color = "accent" },
  init = function(self)
    -- Redraw at each new day.
    self:every(3600, function(self) self:set({ day = os.date("*t").day }) end, { align = true })
  end,
  render = function(self)
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
