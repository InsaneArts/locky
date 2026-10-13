-- battery: charge, and time left or charging state.
--   Families: circular (a ring with the charge), rectangular, inline, small, medium.
--   opts.style    without a family: "row" (symbol, percent, detail), "compact" (symbol and percent), or "ring"
--   opts.low      percent at or below which it turns the palette's danger color (default 20)
local ui = locky.ui

local function symbol(b)
  if b.charging then
    return "battery.100percent.bolt"
  end
  local p = b.percent or 0
  local level = p >= 88 and 100 or p >= 63 and 75 or p >= 38 and 50 or p >= 13 and 25 or 0
  return ("battery.%dpercent"):format(level)
end

local function detail(b)
  if b.state == "charged" then
    return "Charged"
  elseif b.charging then
    return b.until_full and ("%d:%02d until full"):format(b.until_full // 60, b.until_full % 60) or "Charging"
  elseif b.plugged then
    return "Plugged in"
  elseif b.remaining then
    return ("%d h %02d min left"):format(b.remaining // 60, b.remaining % 60)
  end
  return "On battery"
end

-- The Mac's own picture: a laptop has a battery, so it is a laptop.
local device = "laptopcomputer"

-- Apple's layouts for each family.
local function family(b, o, color)
  local percent = b.percent .. "%"
  local tint = color or "fg"
  local state = b.charging and "bolt.fill" or nil
  if o.family == "inline" then
    return ui.hstack { spacing = 4, ui.symbol(symbol(b), ui.font("subheadline")), ui.text(percent, ui.font("subheadline", { weight = "semibold", mono = true })) }
  elseif o.family == "circular" then
    return ui.zstack {
      ui.gauge(b.percent / 100, { style = "capacity", color = tint, size = 64 }),
      ui.vstack {
        spacing = 0,
        ui.symbol(device, { size = 17, weight = "medium" }),
        ui.text(b.percent, { size = 15, weight = "semibold", mono = true }),
      },
    }
  elseif o.family == "rectangular" then
    return ui.vstack {
      spacing = 3, align = "leading", fill = "both",
      ui.hstack { spacing = 5, ui.symbol(device, ui.font("headline")), ui.text("Mac", ui.font("headline")), state and ui.symbol(state, ui.font("footnote", { color = "success" })) },
      ui.text(percent, ui.font("title2", { weight = "semibold", mono = true })),
      ui.gauge(b.percent / 100, { style = "linear-capacity", color = tint, size = 172 }),
    }
  end
  local ring = ui.zstack {
    ui.gauge(b.percent / 100, { style = "capacity", color = tint, size = o.family == "small" and 92 or 104 }),
    ui.symbol(device, { size = o.family == "small" and 30 or 34, weight = "regular" }),
    state and ui.symbol(state, { size = 13, color = tint, offset = { 0, -46 } }),
  }
  if o.family == "small" then
    return ui.vstack {
      spacing = 0, fill = "both",
      ui.spacer(),
      ring,
      ui.spacer(),
      ui.text(percent, ui.font("title", { weight = "semibold", mono = true, numeric = true })),
      ui.text(detail(b), ui.font("footnote", { weight = "medium", color = "muted", lines = 1 })),
    }
  end
  return ui.hstack {
    spacing = 20, fill = "both",
    ring,
    ui.vstack {
      spacing = 2, align = "leading",
      ui.text("Mac", ui.font("headline", { color = "muted" })),
      ui.text(percent, ui.font("large_title", { size = 44, weight = "semibold", mono = true, numeric = true })),
      ui.text(detail(b), ui.font("subheadline", { weight = "medium", color = "muted", lines = 1 })),
    },
    ui.spacer(),
  }
end

locky.widget.define("battery", {
  description = "Battery charge and time left",
  card = true,
  families = { "circular", "rectangular", "inline", "small", "medium" },
  opts = { style = "row", low = 20, size = 15 },
  choices = { style = { "row", "compact", "ring" } },
  init = function(self)
    self:every(30, function(self)
      self:set({ battery = locky.sys.battery() })
    end)
  end,
  render = function(self)
    local b, o = self.state.battery, self.opts
    if not b or not b.present then
      return nil
    end
    local color = b.charging and "success" or (b.percent <= o.low and "danger" or o.color)
    if self.family then
      return family(b, { family = self.family }, color)
    end
    if o.style == "ring" then
      return ui.zstack {
        ui.ring(b.percent / 100, { size = o.ring_size or 44, stroke_width = 4, color = color or "accent" }),
        ui.text(b.percent, { size = 12, weight = "bold", mono = true }),
      }
    end
    local percent = ui.text(b.percent .. "%", { size = o.size, weight = "semibold", mono = true, numeric = true })
    if o.style == "compact" then
      return ui.hstack { spacing = 6, ui.symbol(symbol(b), { size = o.size + 2, color = color }), percent }
    end
    return ui.hstack {
      spacing = 12,
      ui.symbol(symbol(b), { size = o.size + 9, color = color }),
      ui.vstack {
        spacing = 1, align = "leading",
        percent,
        ui.text(detail(b), { size = o.size - 3, weight = "medium", color = "muted" }),
      },
    }
  end,
})
