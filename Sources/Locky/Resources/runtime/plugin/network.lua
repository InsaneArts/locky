-- network: the connection in use, its address, and how fast data moves, from `route`, `ipconfig`, and `netstat`.
--   opts.style   "line" (default: down and up speed, interface, address) or "chart" (download over the last minutes)
--   opts.every   seconds between readings (default 2); opts.size, opts.color, opts.width
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

locky.widget.define("network", {
  description = "The connection, its address, and its speed",
  opts = { style = "line", every = 2, size = 13, width = 240, history = 60 },
  choices = { style = { "line", "chart" } },
  init = function(self)
    self.state.history, self.state.ports = {}, {}
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
        end)
      end)
    end)
    self:every(self.opts.every, function(self)
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
          self:set({ down = down, up = up })
        end
        s.last = { down = inbytes, up = outbytes, at = now }
      end)
    end)
  end,
  render = function(self)
    local o, s = self.opts, self.state
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
