-- Memento's widget:
--   memento.day   "Day 286 of 365", and how much of the year is gone. opts.size (default 72)
local ui = locky.ui

locky.widget.define("memento.day", {
  description = "The day of the year, and how much of it is gone",
  opts = { size = 72 },
  init = function(self)
    self:every(3600, function(self) self:set({ now = os.time() }) end)
  end,
  render = function(self)
    local o, now = self.opts, self.state.now
    if not now then return nil end
    local t = os.date("*t", now)
    local days = os.date("*t", os.time({ year = t.year, month = 12, day = 31, hour = 12 })).yday
    return ui.vstack {
      spacing = 6,
      ui.hstack {
        spacing = o.size * 0.25, align = "bottom",
        ui.text("Day", { size = o.size * 0.4, font = "Hoefler Text", italic = true, color = "muted" }),
        ui.text(tostring(t.yday), { size = o.size, font = "Hoefler Text", weight = "regular" }),
        ui.text("of " .. days, { size = o.size * 0.4, font = "Hoefler Text", italic = true, color = "muted" }),
      },
      ui.text(("%d%% of %d is behind you. %d days remain."):format(math.floor(t.yday / days * 100), t.year, days - t.yday),
        { size = o.size * 0.22, font = "Hoefler Text", color = "muted" }),
    }
  end,
})
