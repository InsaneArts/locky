-- moon: tonight's moon, worked out on the Mac (no network): its phase, how much of it is lit, and the days to the
-- next full moon.
--   Families: inline, circular (the moon and how much of it is lit), rectangular, small, medium (with the next
--   full and new moons), after Apple Weather's moon.
--   opts.style   "full" (default: the moon, its name, and the numbers), "symbol" (the moon alone), or "row"
--   opts.size    the moon's size in points (default 64); text scales with it
--   opts.color   the moon's color (default "fg")
local ui = locky.ui
local sky = require("locky.sky")

local function in_days(n, what)
  return n == 0 and (what .. " tonight") or ("%s in %d day%s"):format(what, n, n == 1 and "" or "s")
end

local function family(m, o, f)
  local lit = m.illumination .. "%"
  if f == "inline" then
    return ui.hstack { spacing = 4, ui.symbol(m.symbol, ui.font("subheadline")), ui.text(m.name .. " · " .. lit, ui.font("subheadline", { mono = true, lines = 1 })) }
  elseif f == "circular" then
    return ui.vstack {
      spacing = 3,
      ui.symbol(m.symbol, { size = 30, mode = "hierarchical" }),
      ui.text(lit, { size = 13, weight = "semibold", mono = true }),
    }
  elseif f == "rectangular" then
    return ui.vstack {
      spacing = 1, align = "leading", fill = "both",
      ui.hstack { spacing = 5, ui.symbol(m.symbol, ui.font("headline")), ui.text(m.name, ui.font("headline", { lines = 1 })) },
      ui.text(lit .. " illuminated", ui.font("subheadline", { mono = true, lines = 1 })),
      ui.text(in_days(m.days_to_full, "Full moon"), ui.font("subheadline", { color = "muted", lines = 1 })),
    }
  end
  local moon = function(size)
    return ui.symbol(m.symbol, { size = size, color = o.color, mode = "hierarchical" })
  end
  if f == "small" then
    return ui.vstack {
      spacing = 0, align = "leading", fill = "both",
      moon(56),
      ui.spacer(),
      ui.text(m.name, ui.font("subheadline", { weight = "semibold", lines = 1 })),
      ui.text(lit .. " illuminated", ui.font("footnote", { weight = "medium", color = "muted", mono = true, lines = 1 })),
      ui.text(in_days(m.days_to_full, "Full moon"), ui.font("footnote", { weight = "medium", color = "muted", lines = 1 })),
    }
  end
  local function when(days)
    return days == 0 and "Tonight" or locky.date.format("skeleton:EEEdMMM", os.time() + days * 86400)
  end
  local function row(label, value)
    return ui.hstack {
      ui.text(label, ui.font("subheadline", { color = "muted", lines = 1 })),
      ui.spacer(),
      ui.text(value, ui.font("subheadline", { weight = "medium", mono = true, lines = 1 })),
    }
  end
  return ui.hstack {
    spacing = 16, fill = "both",
    moon(96),
    ui.vstack {
      spacing = 7, align = "leading", fill = "width",
      ui.text(m.name, ui.font("headline", { lines = 1 })),
      ui.divider(),
      row("Illumination", lit),
      row("Next Full Moon", when(m.days_to_full)),
      row("Next New Moon", when(m.days_to_new)),
    },
  }
end

locky.widget.define("moon", {
  description = "The moon's phase tonight",
  opts = { style = "full", size = 64 },
  choices = { style = { "full", "symbol", "row" } },
  families = { "inline", "circular", "rectangular", "small", "medium" },
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
    if self.family then
      return family(m, o, self.family)
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
