-- Days until the vacation on December 20. Written by a coding agent with Locky's skill, from the prompt
-- "Make a Locky widget that shows the days until my vacation on December 20."
local ui = locky.ui

locky.widget.define("vacation", {
  description = "Days until vacation",
  card = true,
  opts = { month = 12, day = 20, label = "until vacation" },
  init = function(self)
    self:every(3600, function(self)
      local now = os.date("*t")
      local target = os.time({ year = now.year, month = self.opts.month, day = self.opts.day, hour = 0 })
      -- Past this year's date: count to next year's.
      if target < os.time() then
        target = os.time({ year = now.year + 1, month = self.opts.month, day = self.opts.day, hour = 0 })
      end
      local today = os.time({ year = now.year, month = now.month, day = now.day, hour = 0 })
      self:set({ days = (target - today) // 86400 })
    end)
  end,
  render = function(self)
    local days = self.state.days
    if not days then return nil end
    return ui.hstack {
      spacing = 14,
      ui.symbol("beach.umbrella.fill", { size = 34, color = "accent" }),
      ui.vstack {
        spacing = 0,
        align = "leading",
        ui.text(days, { size = 40, weight = "semibold", mono = true }),
        ui.text(days == 1 and "day " .. self.opts.label or "days " .. self.opts.label, { size = 13, color = "muted" }),
      },
    }
  end,
})
