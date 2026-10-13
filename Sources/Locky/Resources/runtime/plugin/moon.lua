-- moon: tonight's moon, worked out on the Mac (no network): its phase, how much of it is lit, and the days to the
-- next full moon.
--   opts.style   "full" (default: the moon, its name, and the numbers), "symbol" (the moon alone), or "row"
--   opts.size    the moon's size in points (default 64); text scales with it
--   opts.color   the moon's color (default "fg")
local ui = locky.ui
local sky = require("locky.sky")

locky.widget.define("moon", {
  description = "The moon's phase tonight",
  opts = { style = "full", size = 64 },
  choices = { style = { "full", "symbol", "row" } },
  init = function(self)
    self:every(3600, function(self)
      self:set({ moon = sky.moon(os.time()) })
    end)
  end,
  render = function(self)
    local o, m = self.opts, self.state.moon
    if not m then
      return nil
    end
    local moon = ui.symbol(m.symbol, { size = o.size, color = o.color, mode = "hierarchical" })
    if o.style == "symbol" then
      return moon
    end
    local text = math.max(11, o.size * 0.22)
    local full = m.days_to_full == 0 and "Full tonight" or ("Full moon in %d day%s"):format(m.days_to_full, m.days_to_full == 1 and "" or "s")
    if o.style == "row" then
      return ui.hstack {
        spacing = 8,
        ui.symbol(m.symbol, { size = text * 1.4, color = o.color }),
        ui.text(m.name, { size = text, weight = "medium", color = o.color }),
        ui.text(m.illumination .. "%", { size = text, color = "muted", mono = true }),
      }
    end
    return ui.vstack {
      spacing = text * 0.6,
      moon,
      ui.text(m.name, { size = text * 1.1, weight = "semibold", color = o.color }),
      ui.text(("%d%% lit · %s"):format(m.illumination, full), { size = text * 0.85, color = "muted" }),
    }
  end,
})
