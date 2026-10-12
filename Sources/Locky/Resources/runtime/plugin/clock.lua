-- clock: the time, updating itself every second without running Lua.
--   opts.format   "time" (the system's hours and minutes, 12 or 24 hour), or a template such as "HH:mm"
--   opts.size     font size in points (default 180)
--   opts.weight, opts.design, opts.font, opts.color, opts.tracking, opts.shadow, opts.shadow_color, opts.glow
--   opts.numeric  false to switch digits without rolling (rolling costs CPU each minute on a big clock)
--   opts.stacked  true: hours above minutes, like StandBy
local ui = locky.ui

locky.widget.define("clock", {
  description = "The time, large",
  opts = { format = "time", size = 180, weight = "semibold", design = "rounded", tracking = -3, shadow = 18, stacked = false },
  render = function(self)
    local o = self.opts
    local style = {
      size = o.size, weight = o.weight, design = o.design, font = o.font, color = o.color,
      tracking = o.tracking, shadow = o.shadow, shadow_color = o.shadow_color, glow = o.glow,
      numeric = o.numeric, mono = true, opacity = o.opacity, case = o.case,
    }
    if o.stacked then
      local hours = locky.date.locale().hour24 and "HH" or "hh"
      return ui.vstack {
        spacing = o.spacing or -o.size * 0.18,
        ui.time(o.hours or hours, style),
        ui.time("mm", locky.tbl.extend("force", style, { color = o.minutes_color or o.color })),
      }
    end
    return ui.time(o.format, style)
  end,
})
