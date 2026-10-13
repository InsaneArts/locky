-- date: the date in the user's language.
--   opts.format   "date" (weekday, month, day), or a template such as "EEEE d MMMM" or "EEE dd.MM"
--   opts.size, opts.weight, opts.design, opts.font, opts.color, opts.case, opts.tracking, opts.shadow
--   (0 for none), opts.shadow_color, opts.glow, opts.numeric
--   Families: inline ("Tue 13 Oct", as above the iPhone's clock), small (the weekday in red over a big day).
local ui = locky.ui

local function family(f)
  if f == "inline" then
    return ui.time("skeleton:EEEdMMM", ui.font("subheadline", { weight = "semibold" }))
  end
  return ui.vstack {
    spacing = 0, align = "leading", fill = "both",
    ui.time("EEEE", ui.font("subheadline", { weight = "bold", case = "upper", color = "danger" })),
    ui.time("d", { size = 76, weight = "light", mono = true, numeric = false }),
    ui.spacer(),
    ui.time("LLLL", ui.font("subheadline", { weight = "semibold" })),
    ui.time("yyyy", ui.font("subheadline", { color = "muted", mono = true })),
  }
end

locky.widget.define("date", {
  description = "Today's date",
  families = { "inline", "small" },
  opts = { format = "date", size = 22, weight = "semibold", shadow = 8 },
  render = function(self)
    if self.family == "inline" or self.family == "small" then
      return family(self.family)
    end
    local o = self.opts
    return ui.time(o.format, {
      size = o.size, weight = o.weight, design = o.design, font = o.font, color = o.color or "fg",
      case = o.case, tracking = o.tracking, shadow = o.shadow, shadow_color = o.shadow_color, glow = o.glow,
      numeric = o.numeric, opacity = o.opacity,
    })
  end,
})
