-- Classic's widgets: a 1-bit desktop from the mid-1980s.
--   classic.menubar   the menu bar across the top, a padlock for its menu and the time at the right
--   classic.about     an "About" window: the Mac, its memory, and a bar of what is in use
--   classic.clock     the alarm clock desk accessory: the time with seconds, and the date
--   classic.icons     the desktop's icons down the right side: the disk and the trash
--   classic.dialog    the dialog the password field sits in; give it a size, such as { 440, 200 }
local ui = locky.ui

local title_font = { font = "Silom", size = 13, color = "ink" }
local body = { font = "Geneva", size = 12, color = "ink" }

-- A window: a title bar with stripes and a close box, a 1-pixel frame, a hard drop shadow.
local function window(title, width, height, content)
  local stripes = {}
  for i = 1, 6 do
    stripes[i] = ui.rect({ height = 1, fill = "width", color = "ink" })
  end
  local bar = ui.zstack {
    height = 22, width = width,
    ui.vstack { spacing = 1, padding = { 0, 3 }, stripes },
    ui.hstack {
      width = width, padding = { 0, 10 },
      ui.rect({ width = 13, height = 11, color = "paper", border = "ink", border_width = 1 }),
      ui.spacer(),
    },
    ui.text(title, { font = "Silom", size = 13, color = "ink", padding = { 3, 8 }, background = "paper" }),
  }
  local frame = ui.vstack {
    spacing = 0, width = width, height = height, background = "paper", border = "ink", border_width = 1,
    bar,
    ui.rect({ height = 1, fill = "width", color = "ink" }),
    ui.vstack { spacing = 6, padding = 12, fill = true, align = "leading", content },
  }
  return ui.zstack {
    width = width + 3, height = height + 3,
    ui.rect({ width = width, height = height, color = "ink", offset = { 1.5, 1.5 } }),
    ui.zstack { offset = { -1.5, -1.5 }, frame },
  }
end

locky.widget.define("classic.menubar", {
  description = "The menu bar",
  opts = { width = 1440 },
  init = function(self)
    self:every(60, function(self) self:set({ now = os.time() }) end, { align = true })
  end,
  render = function(self)
    local o = self.opts
    if not self.state.now then return nil end
    local menus = {}
    for i, name in ipairs({ "File", "Edit", "View", "Special" }) do
      menus[i] = ui.text(name, title_font)
    end
    return ui.vstack {
      spacing = 0, width = o.width,
      ui.hstack {
        spacing = 22, padding = { 4, 18 }, background = "paper", width = o.width,
        ui.symbol("lock.fill", { size = 14, color = "ink" }),
        menus,
        ui.spacer(),
        ui.text(locky.date.format("time", self.state.now), title_font),
      },
      ui.rect({ height = 1, fill = "width", color = "ink" }),
    }
  end,
})

locky.widget.define("classic.about", {
  description = "An About window: the Mac and its memory",
  init = function(self)
    self:every(30, function(self) self:set({ memory = locky.sys.memory() }) end)
  end,
  render = function(self)
    local m = self.state.memory
    if not m then return nil end
    local sys, machine = locky.sys.os(), locky.sys.machine()
    local total = m.total / 1073741824
    local used = (m.used or 0) / 1073741824
    local width = 380
    return window("About This Computer", width, 190, {
      ui.hstack {
        spacing = 12,
        ui.symbol("desktopcomputer", { size = 34, color = "ink" }),
        ui.vstack {
          spacing = 2, align = "leading",
          ui.text(("System Software %s"):format(sys.version), { font = "Silom", size = 13, color = "ink" }),
          ui.text(machine.chip, body),
        },
      },
      ui.rect({ height = 1, fill = "width", color = "ink" }),
      ui.text(("Total Memory:  %.0f GB"):format(total), body),
      ui.text(("In Use:  %.1f GB    Free:  %.1f GB"):format(used, total - used), body),
      ui.zstack {
        align = "leading", width = width - 26, height = 14,
        ui.rect({ width = width - 26, height = 14, color = "paper", border = "ink", border_width = 1 }),
        ui.rect({ width = (width - 26) * used / total, height = 14, color = "ink" }),
      },
    })
  end,
})

locky.widget.define("classic.clock", {
  description = "The alarm clock desk accessory",
  render = function(self)
    -- ui.time ticks by itself, so the window is drawn once.
    local hour24 = locky.date.locale().hour24
    return window("Alarm Clock", 220, 96, {
      ui.time(hour24 and "HH:mm:ss" or "h:mm:ss a", { font = "Silom", size = 22, color = "ink" }),
      ui.time("EEE, MMM d, yyyy", body),
    })
  end,
})

locky.widget.define("classic.icons", {
  description = "The desktop's icons",
  render = function(self)
    local function icon(symbol, label)
      return ui.vstack {
        spacing = 4,
        ui.symbol(symbol, { size = 40, color = "ink", background = "paper", padding = 6 }),
        ui.text(label, { font = "Geneva", size = 12, color = "ink", background = "paper", padding = { 1, 4 } }),
      }
    end
    return ui.vstack { spacing = 36, icon("internaldrive", "Locky HD"), icon("folder", "Documents"), icon("trash", "Trash") }
  end,
})

locky.widget.define("classic.dialog", {
  description = "The dialog the password field sits in",
  render = function(self)
    local inner = ui.vstack {
      spacing = 10, padding = 18, fill = true, align = "top-leading", background = "paper", border = "ink", border_width = 2,
      ui.hstack {
        spacing = 14, align = "top",
        ui.symbol("lock.shield", { size = 34, color = "ink" }),
        ui.vstack {
          spacing = 4, align = "leading",
          ui.text("This computer is locked.", { font = "Silom", size = 14, color = "ink" }),
          ui.text("Please enter your password to continue.", body),
        },
      },
    }
    return ui.zstack {
      fill = true, background = "paper", border = "ink", border_width = 1, padding = 3,
      inner,
    }
  end,
})
