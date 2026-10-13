-- fetch: neofetch on the lock screen: user@host, the system, the machine, uptime, memory, and the palette's colors.
--   opts.logo     "lock" (default: a padlock in block characters), or false
--   opts.colors   false leaves out the row of color blocks
--   opts.size, opts.color (the labels, default "accent"), opts.fields (which lines, in order)
--   Families: rectangular, inline, small, medium, large: About This Mac (the model, chip, memory, and macOS), no
--   user or host names.
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

-- The Mac's own picture, from its model name.
local function picture(model)
  if model:match("^MacBook") then
    return "laptopcomputer"
  elseif model:match("^iMac") then
    return "desktopcomputer"
  elseif model:match("^Mac mini") then
    return "macmini"
  elseif model:match("^Mac Studio") then
    return "macstudio"
  elseif model:match("^Mac Pro") then
    return "macpro.gen3"
  end
  return "desktopcomputer"
end

-- About This Mac, in Apple's layouts for each family.
local function family(f, s, o)
  local sys, machine, hw = locky.sys.os(), locky.sys.machine(), s.hardware or {}
  local model = hw.model or "Mac"
  local chip = hw.chip or machine.chip
  local memory = hw.memory or ("%.0f GB"):format(machine.memory / 1073741824)
  local macos = ("macOS %s %s"):format(sys.codename, sys.version):gsub("  ", " ")
  local symbol = picture(model)
  if f == "inline" then
    return ui.hstack { spacing = 4, ui.symbol(symbol, ui.font("subheadline")), ui.text(macos, ui.font("subheadline", { lines = 1 })) }
  elseif f == "rectangular" then
    return ui.vstack {
      spacing = 1, align = "leading", fill = "both",
      ui.hstack { spacing = 5, ui.symbol(symbol, ui.font("headline")), ui.text(model, ui.font("headline", { lines = 1 })) },
      ui.text(chip, ui.font("subheadline", { lines = 1 })),
      ui.text(macos, ui.font("subheadline", { color = "muted", lines = 1 })),
    }
  elseif f == "small" then
    return ui.vstack {
      spacing = 0, align = "leading", fill = "both",
      ui.symbol(symbol, { size = 40, weight = "light", mode = "hierarchical", color = o.color }),
      ui.spacer(),
      ui.text(model, ui.font("headline", { lines = 1 })),
      ui.text(chip, ui.font("footnote", { weight = "medium", lines = 1 })),
      ui.text(macos, ui.font("footnote", { weight = "medium", color = "muted", lines = 1 })),
    }
  end
  -- Label and value, as About This Mac lists them.
  local function row(label, value, width)
    return value and ui.hstack {
      spacing = 10,
      ui.text(label, ui.font("footnote", { weight = "medium", color = "muted", width = width, text_align = "trailing" })),
      ui.text(value, ui.font("footnote", { weight = "medium", lines = 1 })),
      ui.spacer(),
    }
  end
  local uptime = s.uptime and span(s.uptime)
  if f == "medium" then
    return ui.hstack {
      spacing = 18, fill = "both",
      ui.symbol(symbol, { size = 76, weight = "ultralight", mode = "hierarchical", color = o.color, width = 110 }),
      ui.vstack {
        spacing = 0, align = "leading",
        ui.text(model, ui.font("title3", { weight = "semibold", lines = 1 })),
        ui.text(macos, ui.font("subheadline", { weight = "medium", color = "muted", lines = 1 })),
        ui.spacer(),
        ui.vstack {
          spacing = 4, align = "leading",
          row("Chip", chip, 52),
          row("Memory", memory, 52),
          row("Uptime", uptime, 52),
        },
      },
    }
  end
  local used = s.memory and s.memory.used and s.memory.used / math.max(s.memory.total, 1)
  local battery = s.battery and s.battery.present and (s.battery.percent .. "%" .. (s.battery.charging and ", charging" or ""))
  return ui.vstack {
    spacing = 0, fill = "both",
    ui.spacer(),
    ui.symbol(symbol, { size = 104, weight = "ultralight", mode = "hierarchical", color = o.color }),
    ui.text(model, ui.font("title2", { weight = "semibold", lines = 1, padding = { 14, 0, 0, 0 } })),
    ui.text(macos, ui.font("subheadline", { weight = "medium", color = "muted", lines = 1 })),
    ui.spacer(),
    ui.vstack {
      spacing = 6, align = "leading",
      row("Chip", chip, 96),
      row("Memory", memory, 96),
      row("macOS", sys.build ~= "" and ("%s (%s)"):format(sys.version, sys.build) or sys.version, 96),
      row("Uptime", uptime, 96),
      row("Battery", battery, 96),
    },
    ui.spacer(),
    used and ui.vstack {
      spacing = 6, align = "leading",
      ui.hstack {
        ui.text("Memory in use", ui.font("caption", { weight = "semibold", color = "muted" })),
        ui.spacer(),
        ui.text(math.floor(used * 100 + 0.5) .. "%", ui.font("caption", { weight = "semibold", color = "muted", mono = true })),
      },
      ui.gauge(used, { style = "linear-capacity", size = 332, color = o.color or "accent" }),
    },
  }
end

locky.widget.define("fetch", {
  description = "neofetch: the system, the machine, and the palette",
  families = { "rectangular", "inline", "small", "medium", "large" },
  opts = { logo = "lock", colors = true, size = 13, fields = { "os", "host", "kernel", "uptime", "shell", "cpu", "memory", "battery" } },
  init = function(self)
    -- The model's name ("MacBook Pro") is not in sysctl. Only these three lines are read: the report also has
    -- the serial number.
    if self.family then
      self:system({ "system_profiler", "SPHardwareDataType" }, function(self, result)
        local text = result.stdout
        self:set({ hardware = { model = text:match("Model Name: ([^\n]+)"), chip = text:match("Chip: ([^\n]+)"), memory = text:match("Memory: ([^\n]+)") } })
      end)
    end
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
    if self.family then
      if self.family == "circular" then
        return nil
      end
      return family(self.family, s, o)
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
