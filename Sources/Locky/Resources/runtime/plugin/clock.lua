-- clock: the time, updating itself every second without running Lua.
--   opts.format   "time" (the system's hours and minutes, 12 or 24 hour), or a template such as "HH:mm"
--   opts.size     font size in points (default 180)
--   opts.weight, opts.design, opts.font, opts.color, opts.tracking, opts.shadow, opts.shadow_color, opts.glow
--   opts.numeric  false to switch digits without rolling (rolling costs CPU each minute on a big clock)
--   opts.stacked  true: hours above minutes, like StandBy
--   Families: circular (hours over minutes), rectangular, inline, small, and medium (your city, the date,
--   and the time big).
local ui = locky.ui

-- The time with AM or PM after it on a 12-hour clock.
local function time(style, size)
  return ui.hstack {
    spacing = 2, align = "bottom",
    ui.time("time", locky.tbl.extend("force", { size = size, mono = true, numeric = false }, style)),
    not locky.date.locale().hour24 and ui.time("a", ui.font("subheadline", { weight = "semibold", padding = { 0, 0, size * 0.16, 0 } })),
  }
end

local function family(f)
  -- The city would say where the Mac is: privacy mode shows none.
  local city = locky.config.privacy ~= true and locky.date.format("VVV") or "Local Time"
  if f == "inline" then
    return ui.hstack { spacing = 4, ui.symbol("clock", ui.font("subheadline")), ui.time("time", ui.font("subheadline", { weight = "semibold", mono = true })) }
  elseif f == "circular" then
    local hours = locky.date.locale().hour24 and "HH" or "h"
    return ui.vstack {
      spacing = -7,
      ui.time(hours, { size = 26, weight = "semibold", mono = true, numeric = false }),
      ui.time("mm", { size = 26, weight = "semibold", mono = true, numeric = false }),
    }
  elseif f == "rectangular" then
    return ui.vstack {
      spacing = -2, align = "leading", fill = "both",
      ui.hstack { spacing = 4, ui.symbol("location.fill", { size = 11 }), ui.text(city, ui.font("headline", { lines = 1 })) },
      time({ weight = "semibold" }, 44),
    }
  elseif f == "small" then
    return ui.vstack {
      spacing = 0, align = "leading", fill = "both",
      ui.text(city, ui.font("headline", { lines = 1 })),
      ui.time("EEEE", ui.font("subheadline", { color = "muted" })),
      ui.spacer(),
      time({ weight = "medium" }, 50),
    }
  end
  return ui.vstack {
    spacing = 0, align = "leading", fill = "both",
    ui.hstack {
      ui.text(city, ui.font("headline", { lines = 1 })),
      ui.spacer(),
      ui.time("skeleton:EEEEdMMMM", ui.font("subheadline", { color = "muted" })),
    },
    ui.spacer(),
    time({ weight = "medium" }, 88),
  }
end

locky.widget.define("clock", {
  description = "The time, large",
  opts = { format = "time", size = 180, weight = "semibold", design = "rounded", tracking = -3, shadow = 18, stacked = false },
  families = { "circular", "rectangular", "inline", "small", "medium" },
  render = function(self)
    if self.family and self.family ~= "large" then
      return family(self.family)
    end
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
