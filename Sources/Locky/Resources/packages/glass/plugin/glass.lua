-- The Liquid Glass theme's widgets.
--
-- glass.clock: the time, huge. Its digits change without rolling: at 270 points the rolling animation costs
-- about a second of CPU at every minute.
--   opts.format    "time" (the system's 12 or 24 hours, default) or a template such as "HH:mm"
--   opts.size, opts.weight, opts.design, opts.tracking, opts.shadow, opts.color
--
-- glass.gauges: Liquid Glass circles under the clock, like the lock screen's circular widgets. Each one is a
-- glass disc with an open ring, a value in the middle, and a small symbol in the ring's gap: battery, CPU,
-- memory, and the herdr agents that need you. A circle hides when its data is missing (no battery, herdr not
-- running), and the row stays centered.
--   opts.size      circle diameter (default 64)
--   opts.spacing   space between circles (default 22)
--   opts.stroke    ring width (default 4.5)
--   opts.color     ring color (default "accent"); opts.track the ring's track (default "track")
--   opts.shade     a tint inside each circle that keeps white legible on bright glass (default "#0000001f", or a
--                  deeper blue "#17377a3d" over the theme's bright fallback scene)
--   opts.every     seconds between CPU and memory readings (default 5)
--   opts.agents    seconds between herdr checks (default 5); false hides the agents circle
--   opts.low       battery percent at or below which the ring turns "danger" (default 20)
local ui = locky.ui
local herdr = require("locky.herdr")

-- Shallow equality, so the widget redraws only when what it shows changes.
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if b[k] ~= v then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function update(self, key, value)
  if not same(self.state[key], value) then
    self:set({ [key] = value })
  end
end

local function battery_symbol(b)
  if b.charging then
    return "bolt.fill"
  end
  local p = b.percent
  return ("battery.%dpercent"):format(p >= 88 and 100 or p >= 63 and 75 or p >= 38 and 50 or p >= 13 and 25 or 0)
end

-- One circle: the ring opens at the bottom (270 degrees, from 7:30 clockwise to 4:30), the symbol sits in the gap.
local function gauge(o, shade, id, value, color, label, symbol)
  local d, r = o.size, o.size - 14
  local ring = { size = r, stroke_width = o.stroke, stroke = "#00000000", rotation = 225 }
  return ui.zstack {
    id = id, width = d, height = d, background = "glass", radius = d / 2,
    ui.circle({ width = d, height = d, color = shade }),  -- a little depth, so white reads on bright glass
    ui.ring(0.75, locky.tbl.extend("force", ring, { color = o.track })),
    ui.ring(0.75 * math.max(0, math.min(1, value)), locky.tbl.extend("force", ring, { color = color })),
    ui.text(label, { size = d * 0.27, weight = "semibold", design = "rounded", mono = true, color = "fg", shadow = 3 }),
    ui.symbol(symbol, { size = d * 0.16, weight = "bold", color = "fg", offset = { 0, d * 0.335 } }),
  }
end

locky.widget.define("glass.clock", {
  description = "The time, huge, with digits that change without rolling",
  opts = { format = "time", size = 270, weight = "heavy", design = "rounded", tracking = -8, shadow = 24, color = "fg" },
  render = function(self)
    local o = self.opts
    return ui.time(o.format, {
      size = o.size, weight = o.weight, design = o.design, tracking = o.tracking, shadow = o.shadow, color = o.color,
      mono = true, numeric = false,
    })
  end,
})

locky.widget.define("glass.gauges", {
  description = "Battery, CPU, memory, and herdr agents as Liquid Glass circles",
  opts = { size = 64, spacing = 22, stroke = 4.5, color = "accent", track = "track", every = 5, agents = 5, low = 20 },
  init = function(self)
    local o = self.opts
    self:every(30, function(self)
      local b = locky.sys.battery()
      update(self, "battery", b.present and b.percent and { percent = b.percent, charging = b.charging == true } or false)
    end)
    -- CPU use is measured between two calls: start the count now, read it half a second later, then every
    -- `every` seconds. Until then the CPU circle shows a dash.
    locky.sys.cpu()
    self.state.load = { cpu = -1, memory = math.floor(locky.sys.memory().percent + 0.5) }
    local function read(self)
      local cpu, memory = locky.sys.cpu(), locky.sys.memory()
      update(self, "load", { cpu = math.floor(cpu.usage + 0.5), memory = math.floor(memory.percent + 0.5) })
    end
    self:after(0.5, read)
    self:every(o.every, read, { now = false })
    if o.agents then
      herdr.watch(self, o.agents, function(self, data)
        update(self, "agents", data and { need = data.need, total = #data.agents, blocked = data.counts.blocked } or false)
      end)
    end
  end,
  render = function(self)
    local o, s = self.opts, self.state
    local b, load, agents = s.battery, s.load, s.agents
    local shade = o.shade or (self.theme.background.shader and "#17377a3d" or "#0000001f")
    local circles = {}
    if b then
      local color = b.charging and "success" or (b.percent <= o.low and "danger" or o.color)
      circles[#circles + 1] = gauge(o, shade, "battery", b.percent / 100, color, b.percent, battery_symbol(b))
    end
    if load then
      circles[#circles + 1] = gauge(o, shade, "cpu", math.max(load.cpu, 0) / 100, o.color, load.cpu < 0 and "–" or load.cpu, "cpu")
      circles[#circles + 1] = gauge(o, shade, "memory", load.memory / 100, o.color, load.memory, "memorychip")
    end
    if agents then
      local share = agents.total > 0 and agents.need / agents.total or 0
      circles[#circles + 1] = gauge(o, shade, "agents", share, agents.blocked > 0 and "warning" or o.color, agents.need, "sparkles")
    end
    if #circles == 0 then
      return nil
    end
    return ui.hstack { spacing = o.spacing, circles }
  end,
})
