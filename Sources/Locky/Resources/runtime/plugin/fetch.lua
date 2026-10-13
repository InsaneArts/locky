-- fetch: neofetch on the lock screen: user@host, the system, the machine, uptime, memory, and the palette's colors.
--   opts.logo     "lock" (default: a padlock in block characters), or false
--   opts.colors   false leaves out the row of color blocks
--   opts.size, opts.color (the labels, default "accent"), opts.fields (which lines, in order)
-- Privacy mode gives generic user and host names, as locky.sys does.
local ui = locky.ui

local logo = {
  "    ▄▀▀▀▀▄    ",
  "   █      █   ",
  "   █      █   ",
  " ▄██████████▄ ",
  " ████▀  ▀████ ",
  " ████▄  ▄████ ",
  " ██████████▀▀ ",
  "  ▀▀▀▀▀▀▀▀    ",
}

local function size(bytes)
  return ("%.1f GiB"):format(bytes / 1073741824)
end

local function span(seconds)
  local d, h, m = seconds // 86400, seconds % 86400 // 3600, seconds % 3600 // 60
  if d > 0 then
    return ("%d day%s, %d hour%s"):format(d, d == 1 and "" or "s", h, h == 1 and "" or "s")
  end
  return ("%d hour%s, %d min"):format(h, h == 1 and "" or "s", m)
end

locky.widget.define("fetch", {
  description = "neofetch: the system, the machine, and the palette",
  opts = { logo = "lock", colors = true, size = 13, fields = { "os", "host", "kernel", "uptime", "shell", "cpu", "memory", "battery" } },
  init = function(self)
    self:system({ "uname", "-r" }, function(self, result)
      self:set({ kernel = result.stdout:match("%S+") })
    end)
    self:every(60, function(self)
      self:set({ uptime = locky.sys.uptime(), memory = locky.sys.memory(), battery = locky.sys.battery() })
    end)
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.uptime then
      return nil
    end
    local sys, machine = locky.sys.os(), locky.sys.machine()
    local user, host = locky.sys.user().name, locky.sys.hostname().host:gsub("%.local$", "")
    local values = {
      os = ("%s %s %s"):format(sys.name, sys.codename, sys.version),
      host = machine.model,
      kernel = s.kernel and ("Darwin " .. s.kernel),
      uptime = span(s.uptime),
      shell = (os.getenv("SHELL") or ""):match("([^/]+)$"),
      cpu = machine.chip,
      memory = s.memory.used and ("%s / %s"):format(size(s.memory.used), size(s.memory.total)),
      battery = s.battery.present and (s.battery.percent .. "%" .. (s.battery.charging and " (charging)" or "")),
    }
    local labels = { os = "OS", host = "Host", kernel = "Kernel", uptime = "Uptime", shell = "Shell", cpu = "CPU", memory = "Memory", battery = "Battery" }
    local text = { size = o.size, design = "monospaced" }
    local lines = {
      ui.hstack { spacing = 0, ui.text(user, { size = o.size, design = "monospaced", weight = "bold", color = o.color or "accent" }),
        ui.text("@", text), ui.text(host, { size = o.size, design = "monospaced", weight = "bold", color = o.color or "accent" }) },
      ui.text(string.rep("─", #user + 1 + #host), { size = o.size, design = "monospaced", color = "muted" }),
    }
    for _, key in ipairs(o.fields) do
      if values[key] and values[key] ~= "" then
        lines[#lines + 1] = ui.hstack {
          spacing = 0,
          ui.text((labels[key] or key) .. ": ", { size = o.size, design = "monospaced", weight = "bold", color = o.color or "accent" }),
          ui.text(values[key], { size = o.size, design = "monospaced", lines = 1 }),
        }
      end
    end
    if o.colors ~= false then
      local blocks = {}
      for i, role in ipairs({ "bg", "danger", "success", "warning", "accent", "muted", "fg" }) do
        blocks[i] = ui.rect({ width = o.size * 2.2, height = o.size * 1.2, color = role })
      end
      lines[#lines + 1] = ui.hstack { spacing = 0, padding = { o.size * 0.6, 0, 0, 0 }, blocks }
    end
    local info = ui.vstack { spacing = o.size * 0.25, align = "leading", lines }
    if not o.logo then
      return info
    end
    local art = {}
    for i, row in ipairs(logo) do
      art[i] = ui.text(row, { size = o.size, design = "monospaced", color = o.color or "accent" })
    end
    return ui.hstack { spacing = o.size * 2, align = "top", ui.vstack { spacing = 0, art }, info }
  end,
})
