-- E-Ink's widgets: a dashboard for an e-paper screen, after TRMNL and the Kindle dashboards.
--   eink.header   a black bar across the top: the dashboard's name, a dithered strip, and the date
--   eink.time     the time, large, with the date and when the screen locked, for a panel
local ui = locky.ui

locky.widget.define("eink.header", {
  description = "The dashboard's title bar",
  opts = { title = "LOCKY", width = 1360 },
  init = function(self)
    self:every(3600, function(self) self:set({ now = os.time() }) end)
  end,
  render = function(self)
    local o, now = self.opts, self.state.now
    if not now then return nil end
    -- A gradient from ink to paper, drawn as an e-paper screen draws gray: with a 4×4 ordered (Bayer) dither.
    local bayer = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } }
    local rows = {}
    for r = 1, 4 do
      local dots = {}
      for c = 1, 64 do
        local ink = 1 - (c - 1) / 63
        dots[c] = ui.rect({ width = 3, height = 3, color = ink * 16 > bayer[r][(c - 1) % 4 + 1] + 0.5 and "paper" or "ink" })
      end
      rows[r] = ui.hstack { spacing = 0, dots }
    end
    return ui.hstack {
      width = o.width, padding = { 10, 18 }, background = "ink",
      ui.text(o.title, { size = 18, weight = "heavy", tracking = 6, color = "paper" }),
      ui.spacer(),
      ui.vstack { spacing = 0, rows },
      ui.spacer(),
      ui.text(locky.date.format("EEEE, d MMMM yyyy", now):upper(), { size = 14, weight = "bold", tracking = 2, color = "paper" }),
    }
  end,
})

locky.widget.define("eink.time", {
  description = "The time, the date, and when the screen locked",
  init = function(self)
    self.state.since = os.time()
  end,
  render = function(self)
    return ui.vstack {
      spacing = 4, align = "leading",
      ui.time("HH:mm", { size = 150, weight = "black", tracking = -6, numeric = false }),
      ui.time("EEEE d MMMM", { size = 24, weight = "semibold" }),
      ui.text("Locked at " .. locky.date.format("time", self.state.since), { size = 14, color = "muted" }),
    }
  end,
})
