-- Synthwave widgets: a chrome clock, a neon date, battery, and herdr agents as neon dots.
-- Colors are palette roles: chrome1-3 (the clock's gradient, top to bottom), accent (pink: glows, blocked
-- agents), accent2 (cyan: date, battery, done agents), sun (orange: working agents), danger (low battery).
local ui = locky.ui
local herdr = require("locky.herdr")

-- synthwave.clock: the time in a chrome gradient with a pink glow. It updates itself, without Lua. The
-- digits switch without rolling: a roll redraws the big glowing text for every frame it moves.
--   opts.format (default "time": the system's hours and minutes), opts.size, opts.font, opts.tracking,
--   opts.glow (radius)
locky.widget.define("synthwave.clock", {
  description = "The time in chrome condensed capitals with a neon glow",
  opts = { format = "time", size = 200, font = "Futura-CondensedExtraBold", tracking = 3, glow = 24 },
  render = function(self)
    local o = self.opts
    return ui.time(o.format, {
      size = o.size, font = o.font, weight = "regular", tracking = o.tracking, glow = o.glow, numeric = false,
      color = { "chrome1", "chrome2", "chrome3", angle = 180 },
    })
  end,
})

-- synthwave.date: the date in tracked neon capitals, in the user's language.
--   opts.format (a date template, default "EEEE d MMMM"), opts.size, opts.tracking, opts.color, opts.glow
locky.widget.define("synthwave.date", {
  description = "The date in tracked neon capitals",
  opts = { format = "EEEE d MMMM", size = 17, tracking = 6, color = "accent2", glow = 10 },
  init = function(self)
    self:every(60, function(self)
      local text = locky.date.format(self.opts.format)
      if text ~= self.state.text then
        self:set({ text = text })
      end
    end, { align = true })
  end,
  render = function(self)
    local o = self.opts
    if not self.state.text then
      return nil
    end
    return ui.text(self.state.text, { size = o.size, weight = "medium", case = "upper", tracking = o.tracking, color = o.color, glow = o.glow })
  end,
})

local function battery_symbol(b)
  if b.charging then
    return "battery.100percent.bolt"
  end
  local p = b.percent
  return ("battery.%dpercent"):format(p >= 88 and 100 or p >= 63 and 75 or p >= 38 and 50 or p >= 13 and 25 or 0)
end

-- synthwave.battery: percent and a battery symbol in neon; danger at or below opts.low. Hidden on a Mac
-- without a battery.
--   opts.size, opts.color, opts.low (default 20)
locky.widget.define("synthwave.battery", {
  description = "Battery charge in neon",
  opts = { size = 15, color = "accent2", low = 20 },
  init = function(self)
    self:every(30, function(self)
      local b = locky.sys.battery()
      local key = b.present and b.percent and (b.percent .. (b.charging and "+" or "")) or "none"
      if key ~= self.state.key then
        self:set({ key = key, battery = b })
      end
    end)
  end,
  render = function(self)
    local o, b = self.opts, self.state.battery
    if not b or not b.present or not b.percent then
      return nil
    end
    local color = not b.charging and b.percent <= o.low and "danger" or o.color
    return ui.hstack {
      spacing = 8,
      ui.text(b.percent .. "%", { size = o.size, weight = "medium", tracking = 1.5, color = color, glow = 6 }),
      ui.symbol(battery_symbol(b), { size = o.size + 3, color = color, glow = 6 }),
    }
  end,
})

-- synthwave.agents: one neon dot per herdr agent, most urgent first: blocked pink, done cyan, working
-- orange, idle dim. Hidden when herdr is off or has no agents.
--   opts.size, opts.gap, opts.max (most dots), opts.label (false hides it), opts.every (seconds)
local colors = { blocked = "accent", done = "accent2", working = "sun" }

locky.widget.define("synthwave.agents", {
  description = "herdr agents as small neon dots",
  opts = { size = 8, gap = 7, max = 24, label = "AGENTS", every = 3 },
  init = function(self)
    herdr.watch(self, self.opts.every, function(self, data)
      local key = ""
      for _, a in ipairs(data and data.agents or {}) do
        key = key .. a.status:sub(1, 2)
      end
      if key ~= self.state.key then
        self:set({ key = key, agents = data and data.agents or false })
      end
    end)
  end,
  render = function(self)
    local o, agents = self.opts, self.state.agents
    if not agents or #agents == 0 then
      return nil
    end
    local dots = { spacing = o.gap }
    for i = 1, math.min(#agents, o.max) do
      local color = colors[agents[i].status]
      dots[i] = ui.dot({ size = o.size, color = color or "muted", opacity = color and 1 or 0.35, glow = color and 5 or nil })
    end
    return ui.hstack {
      spacing = 12,
      o.label and ui.text(o.label, { size = 12, weight = "medium", tracking = 3, color = "muted" }),
      ui.hstack(dots),
    }
  end,
})
