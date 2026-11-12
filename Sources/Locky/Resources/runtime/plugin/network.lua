-- network: the connection in use, its address, and how fast data moves, from `route`, `ipconfig`, and `netstat`.
--   opts.style   "line" (default: down and up speed, interface, address) or "chart" (download over the last minutes)
--   opts.every   seconds between readings (default 2); opts.size, opts.color, opts.width
--   Families: circular (download speed), rectangular, inline, small, medium (both speeds over the last minutes).
-- Privacy mode hides the address.
local ui = locky.ui

local function rate(bytes_per_second)
  local units = { "B/s", "KB/s", "MB/s", "GB/s" }
  local n, i = bytes_per_second, 1
  while n >= 1000 and i < #units do
    n, i = n / 1000, i + 1
  end
  return (i == 1 and "%.0f %s" or "%.1f %s"):format(n, units[i])
end

-- The connection's symbol, from its name.
local function connection(name)
  if name == "VPN" then
    return "lock.shield"
  elseif name:match("Wi%-Fi") then
    return "wifi"
  elseif name:match("Ethernet") or name:match("LAN") then
    return "cable.connector.horizontal"
  end
  return "network"
end

-- "1.2 MB/s" → "1.2", "MB/s".
local function split(bytes_per_second)
  return rate(bytes_per_second):match("^(%S+) (%S+)$")
end

-- Apple's layouts for each family. `s` is nil when offline.
local function family(f, s, name, o)
  if f == "large" then
    return nil
  end
  local symbol = s and connection(name) or "wifi.slash"
  name = s and name or "Offline"
  if f == "inline" then
    if not s then
      return ui.hstack { spacing = 4, ui.symbol(symbol, ui.font("subheadline")), ui.text(name, ui.font("subheadline")) }
    end
    return ui.hstack {
      spacing = 4,
      ui.symbol("arrow.down", ui.font("subheadline", { weight = "semibold" })), ui.text(rate(s.down), ui.font("subheadline", { mono = true })),
      ui.symbol("arrow.up", ui.font("subheadline", { weight = "semibold", padding = { 0, 6, 0, 0 } })), ui.text(rate(s.up), ui.font("subheadline", { mono = true })),
    }
  elseif f == "circular" then
    if not s then
      return ui.symbol(symbol, { size = 26, weight = "medium" })
    end
    local value, unit = split(s.down)
    return ui.vstack {
      spacing = 0,
      ui.symbol("arrow.down", { size = 13, weight = "bold" }),
      ui.text(value, { size = 20, weight = "semibold", mono = true }),
      ui.text(unit, { size = 11, weight = "medium", color = "muted" }),
    }
  end
  local header = ui.hstack {
    spacing = 5,
    ui.symbol(symbol, f == "rectangular" and ui.font("headline") or { size = 13, weight = "semibold", color = o.color or "accent" }),
    ui.text(name, ui.font(f == "rectangular" and "headline" or "subheadline", { weight = "semibold", lines = 1 })),
  }
  if not s then
    return ui.vstack {
      spacing = 2, align = "leading", fill = "both",
      header,
      f ~= "rectangular" and ui.spacer(),
      ui.text("Not connected", ui.font(f == "rectangular" and "subheadline" or "footnote", { weight = "medium", color = "muted" })),
    }
  end
  if f == "rectangular" then
    local function line(icon, bps)
      return ui.hstack { spacing = 5, ui.symbol(icon, ui.font("subheadline", { weight = "semibold", width = 14 })), ui.text(rate(bps), ui.font("subheadline", { mono = true })) }
    end
    return ui.vstack { spacing = 2, align = "leading", fill = "both", header, line("arrow.down", s.down), line("arrow.up", s.up) }
  end
  -- A speed in two sizes: the number big, its unit small, as Apple's Stocks and Fitness widgets do.
  local function speed(icon, label, bps, color)
    local value, unit = split(bps)
    return ui.vstack {
      spacing = 0, align = "leading",
      ui.hstack {
        spacing = 3,
        ui.symbol(icon, { size = 11, weight = "bold", color = color }),
        ui.text(label, ui.font("caption", { weight = "semibold", color = "muted" })),
      },
      ui.hstack {
        spacing = 3, align = "bottom",
        ui.text(value, ui.font("title2", { weight = "semibold", mono = true })),
        ui.text(unit, ui.font("footnote", { weight = "semibold", color = "muted", padding = { 0, 0, 3, 0 } })),
      },
    }
  end
  local down = speed("arrow.down", "Download", s.down, o.color or "accent")
  local up = speed("arrow.up", "Upload", s.up, "muted")
  if f == "small" then
    return ui.vstack { spacing = 10, align = "leading", fill = "both", header, ui.spacer(), down, up }
  end
  -- Bars, as in Apple's Screen Time: all the traffic in gray, the download part of it tinted.
  local total, peak = {}, 1
  for i, v in ipairs(s.history) do
    total[i] = v + (s.up_history[i] or 0)
    peak = math.max(peak, total[i])
  end
  return ui.hstack {
    spacing = 16, fill = "both",
    ui.vstack { spacing = 10, align = "leading", width = 116, fill = "height", header, ui.spacer(), down, up },
    ui.zstack {
      ui.chart(total, { min = 0, max = peak, slots = 30, width = 200, height = 138, style = "bar", color = "fg", opacity = 0.28 }),
      ui.chart(s.history, { min = 0, max = peak, slots = 30, width = 200, height = 138, style = "bar", color = o.color or "accent" }),
    },
  }
end

locky.widget.define("network", {
  description = "The connection, its address, and its speed",
  families = { "circular", "rectangular", "inline", "small", "medium" },
  opts = { style = "line", every = 2, size = 13, width = 240, history = 60 },
  choices = { style = { "line", "chart" } },
  init = function(self)
    self.state.history, self.state.up_history, self.state.ports = {}, {}, {}
    -- One reading of the interface's byte counters; each one after the first gives the rates.
    local function read(self)
      local interface = self.state.interface
      if not interface then
        return
      end
      self:system({ "netstat", "-ibn", "-I", interface }, function(self, result)
        local inbytes, outbytes = result.stdout:match("<Link#%d+>%s+%S*%s+%d+%s+%S+%s+(%d+)%s+%d+%s+%S+%s+(%d+)")
        if not inbytes then
          return
        end
        local now, s = locky.now(), self.state
        inbytes, outbytes = tonumber(inbytes), tonumber(outbytes)
        if s.last and inbytes >= s.last.down and outbytes >= s.last.up then
          local dt = math.max(now - s.last.at, 0.1)
          local down, up = (inbytes - s.last.down) / dt, (outbytes - s.last.up) / dt
          local history = s.history
          history[#history + 1] = down
          if #history > self.opts.history then
            table.remove(history, 1)
          end
          local up_history = s.up_history
          up_history[#up_history + 1] = up
          if #up_history > self.opts.history then
            table.remove(up_history, 1)
          end
          self:set({ down = down, up = up })
        end
        s.last = { down = inbytes, up = outbytes, at = now }
      end)
    end
    self:system({ "networksetup", "-listallhardwareports" }, function(self, result)
      for port, device in result.stdout:gmatch("Hardware Port: ([^\n]+)\nDevice: (%S+)") do
        self.state.ports[device] = port
      end
    end)
    -- The interface carrying the default route, and its address, now and again a minute later.
    self:every(60, function(self)
      self:system({ "route", "-n", "get", "default" }, function(self, result)
        local interface = result.stdout:match("interface: (%S+)")
        if not interface then
          self:set({ interface = false })
          return
        end
        self:system({ "ipconfig", "getifaddr", interface }, function(self, address)
          self:set({ interface = interface, address = address.code == 0 and address.stdout:match("%S+") or nil })
          -- The first reading at once, so the rates show one interval into a lock rather than two.
          if not self.state.last then
            read(self)
          end
        end)
      end)
    end)
    self:every(self.opts.every, read)
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if self.family and s.interface == false then
      return family(self.family, nil, nil, o)
    end
    if s.interface == false then
      return ui.hstack { spacing = 6, ui.symbol("wifi.slash", { size = o.size, color = "muted" }), ui.text("Offline", { size = o.size, color = "muted" }) }
    end
    if not s.down then
      return nil
    end
    local name = s.ports[s.interface] or s.interface
    if s.interface:match("^utun") then
      name = "VPN"
    end
    if self.family then
      return family(self.family, s, name, o)
    end
    local where = name .. ((s.address and locky.config.privacy ~= true) and (" · " .. s.address) or "")
    local speeds = ui.hstack {
      spacing = 12,
      ui.hstack { spacing = 4, ui.symbol("arrow.down", { size = o.size * 0.9, color = o.color or "accent" }), ui.text(rate(s.down), { size = o.size, mono = true }) },
      ui.hstack { spacing = 4, ui.symbol("arrow.up", { size = o.size * 0.9, color = "muted" }), ui.text(rate(s.up), { size = o.size, mono = true }) },
    }
    if o.style == "chart" then
      local peak = 1
      for _, v in ipairs(s.history) do
        peak = math.max(peak, v)
      end
      return ui.vstack {
        spacing = 6, align = "leading",
        ui.hstack { width = o.width, speeds, ui.spacer() },
        ui.chart(s.history, { min = 0, max = peak, slots = o.history, width = o.width, height = o.height or 44, style = "area", color = o.color or "accent" }),
        ui.text(where, { size = o.size * 0.85, color = "muted", lines = 1 }),
      }
    end
    return ui.hstack { spacing = 14, speeds, ui.text(where, { size = o.size, color = "muted", lines = 1 }) }
  end,
})
