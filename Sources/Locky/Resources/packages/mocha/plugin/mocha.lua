-- Mocha's widgets: Catppuccin Mocha around an i3lock-color ring. Colors are palette roles, so a user's
-- palette recolors them all.
--   mocha.center   inside the ring: the time, the date, and the keyboard layout, on a dark disc.
--                  opts.disc (diameter, default 300; false for none), opts.size (the time's size, 56)
--   mocha.user     "user@host": user in mauve, host in text
--   mocha.status   battery and uptime, for the top-right corner. opts.low (default 20)
--   mocha.agents   one dot per herdr agent that needs you or is working: blocked peach, done green,
--                  working blue, and their counts. Hidden when herdr is not running.
--   mocha.label    a small word, "mocha" by default (opts.text)
local ui = locky.ui
local herdr = require("locky.herdr")

locky.widget.define("mocha.center", {
  description = "The time, date, and keyboard layout, inside the ring",
  opts = { size = 56, disc = 300, keyboard = true },
  init = function(self)
    if self.opts.keyboard then
      self:every(1, function(self)
        local name = locky.sys.keyboard().name
        if name ~= self.state.keyboard then
          self:set({ keyboard = name })
        end
      end)
    end
  end,
  render = function(self)
    local o, s = self.opts, self.state
    local hour24 = locky.date.locale().hour24
    local text = ui.vstack {
      spacing = 0,
      ui.time(hour24 and "HH:mm" or "h:mm", { size = o.size, weight = "bold", color = "fg", mono = true }),
      ui.time("skeleton:EEEEdMMMM", { size = 14, weight = "medium", color = "subtext0", padding = { 2, 0, 0, 0 } }),
      s.keyboard and s.keyboard ~= "" and ui.hstack {
        spacing = 6, padding = { 12, 0, 0, 0 },
        ui.symbol("keyboard", { size = 11, color = "overlay0" }),
        ui.text(s.keyboard, { size = 12, color = "overlay0", lines = 1 }),
      },
    }
    if not o.disc then
      return text
    end
    return ui.zstack {
      -- The disc's soft shadow reaches under the ring, so the ring reads on any wallpaper.
      ui.circle({ width = o.disc, height = o.disc, color = "disc", shadow = 28, shadow_color = "#11111bcc" }),
      text,
    }
  end,
})

locky.widget.define("mocha.user", {
  description = "user@host",
  opts = { size = 14 },
  render = function(self)
    local size = self.opts.size
    local host = locky.sys.hostname().host:gsub("%.local$", "")
    return ui.hstack {
      spacing = 0,
      ui.text(locky.sys.user().name, { size = size, weight = "bold", color = "mauve" }),
      ui.text("@", { size = size, color = "subtext0" }),
      ui.text(host, { size = size, weight = "medium", color = "fg", lines = 1 }),
    }
  end,
})

local function battery_symbol(b)
  if b.charging then
    return "battery.100percent.bolt"
  end
  local p = b.percent or 0
  local level = p >= 88 and 100 or p >= 63 and 75 or p >= 38 and 50 or p >= 13 and 25 or 0
  return ("battery.%dpercent"):format(level)
end

locky.widget.define("mocha.status", {
  description = "Battery and uptime",
  opts = { size = 13, low = 20 },
  init = function(self)
    self:every(60, function(self)
      local b, up = locky.sys.battery(), locky.sys.uptime()
      local d, h, m = up // 86400, up % 86400 // 3600, up % 3600 // 60
      local battery = b.present and { percent = b.percent or 0, charging = b.charging, symbol = battery_symbol(b) } or nil
      local uptime = d > 0 and ("%dd %dh"):format(d, h) or ("%dh %02dm"):format(h, m)
      local key = locky.json.encode({ battery = battery or false, uptime = uptime })
      if key ~= self.state.key then
        self:set({ battery = battery, uptime = uptime, key = key })
      end
    end)
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.uptime then
      return nil
    end
    local b = s.battery
    local color = b and (b.charging and "green" or b.percent <= o.low and "red" or b.percent <= 40 and "yellow" or "green")
    return ui.hstack {
      spacing = 18,
      b and ui.hstack {
        spacing = 7,
        ui.symbol(b.symbol, { size = o.size + 1, color = color }),
        ui.text(b.percent .. "%", { size = o.size, weight = "medium", color = "fg" }),
      },
      ui.hstack {
        spacing = 7,
        ui.symbol("power", { size = o.size - 1, weight = "semibold", color = "blue" }),
        ui.text(s.uptime, { size = o.size, weight = "medium", color = "fg" }),
      },
    }
  end,
})

local dot_colors = { blocked = "peach", done = "green", working = "blue" }

locky.widget.define("mocha.agents", {
  description = "herdr agents as dots: blocked peach, done green, working blue",
  opts = { size = 12, dot = 9, max = 16 },
  init = function(self)
    herdr.watch(self, function(self, data)
      local key = "off"
      if data then
        local parts = {}
        for _, a in ipairs(data.agents) do
          parts[#parts + 1] = a.status
        end
        key = table.concat(parts, ",")
      end
      if key ~= self.state.key then
        self:set({ data = data, key = key })
      end
    end)
  end,
  render = function(self)
    local o, data = self.opts, self.state.data
    if not data then
      return nil
    end
    local dots = {}
    for _, a in ipairs(data.agents) do
      local color = dot_colors[a.status]
      if color and #dots < o.max then
        dots[#dots + 1] = ui.dot({ size = o.dot, color = color })
      end
    end
    local c = data.counts
    local words = {}
    if c.blocked > 0 then words[#words + 1] = c.blocked .. " blocked" end
    if c.done > 0 then words[#words + 1] = c.done .. " done" end
    if c.working > 0 then words[#words + 1] = c.working .. " working" end
    if #words == 0 then words[1] = #data.agents > 0 and "all idle" or "no agents" end
    return ui.hstack {
      spacing = 12,
      #dots > 0 and ui.hstack { spacing = 6, dots },
      ui.text(table.concat(words, " · "), { size = o.size, color = "overlay0", lines = 1 }),
    }
  end,
})

locky.widget.define("mocha.label", {
  description = "A small word in a corner",
  opts = { text = "mocha", size = 12 },
  render = function(self)
    return ui.text(self.opts.text, { size = self.opts.size, weight = "medium", color = "overlay0", tracking = 1 })
  end,
})
