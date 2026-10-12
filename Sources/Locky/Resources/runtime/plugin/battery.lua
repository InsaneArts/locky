-- battery: charge, and time left or charging state.
--   opts.style    "row" (symbol, percent, detail), "compact" (symbol and percent), or "ring"
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

locky.widget.define("battery", {
  description = "Battery charge and time left",
  card = true,
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
