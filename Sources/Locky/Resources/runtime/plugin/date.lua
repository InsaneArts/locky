-- date: the date in the user's language.
--   opts.format   "date" (weekday, month, day), or a template such as "EEEE d MMMM" or "EEE dd.MM"
--   opts.size, opts.weight, opts.design, opts.font, opts.color, opts.case, opts.tracking, opts.shadow
--   (0 for none), opts.shadow_color, opts.glow, opts.numeric
local ui = locky.ui

locky.widget.define("date", {
  description = "Today's date",
  opts = { format = "date", size = 22, weight = "semibold", shadow = 8 },
  render = function(self)
    local o = self.opts
    return ui.time(o.format, {
      size = o.size, weight = o.weight, design = o.design, font = o.font, color = o.color or "fg",
      case = o.case, tracking = o.tracking, shadow = o.shadow, shadow_color = o.shadow_color, glow = o.glow,
      numeric = o.numeric, opacity = o.opacity,
    })
  end,
})
