-- Mission's widgets: a spaceflight console.
--   mission.header      the console's title bar: station, console, and status
--   mission.met         mission elapsed time since the screen locked: T+ HH:MM:SS, ticking each second
--   mission.clocks      UTC, local time, Unix time, and the day of the year
--   mission.telemetry   CPU, memory, disk, and battery as segmented bars, each with a status word
local ui = locky.ui

local small = { size = 11, design = "monospaced", color = "muted", tracking = 2 }

locky.widget.define("mission.header", {
  description = "The console's title bar",
  opts = { width = 1360, title = "LOCKY FLIGHT CONTROL" },
  render = function(self)
    local o = self.opts
    return ui.vstack {
      spacing = 6, width = o.width,
      ui.hstack {
        ui.text(o.title, { size = 13, design = "monospaced", weight = "bold", tracking = 4, color = "accent" }),
        ui.spacer(),
        ui.text("CONSOLE 3  ·  FLIGHT DIRECTOR", small),
        ui.spacer(),
        ui.hstack { spacing = 6, ui.dot({ size = 8, color = "success", glow = 4 }), ui.text("STATUS: SECURED", { size = 11, design = "monospaced", tracking = 2, color = "success" }) },
      },
      ui.rect({ height = 1, fill = "width", color = "border" }),
    }
  end,
})

locky.widget.define("mission.met", {
  description = "Mission elapsed time since the screen locked",
  opts = { size = 64 },
  init = function(self)
    self.state.start = os.time()
    self:every(1, function(self) self:set({ now = os.time() }) end, { align = true })
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.now then return nil end
    local e = s.now - s.start
    return ui.vstack {
      spacing = 4, align = "leading",
      ui.text("MISSION ELAPSED TIME", small),
      ui.text(("T+ %02d:%02d:%02d"):format(e // 3600, e % 3600 // 60, e % 60), { size = o.size, design = "monospaced", weight = "medium", color = "fg", glow = 6 }),
    }
  end,
})

locky.widget.define("mission.clocks", {
  description = "UTC, local, Unix time, and the day of the year",
  init = function(self)
    self:every(1, function(self) self:set({ now = os.time() }) end, { align = true })
  end,
  render = function(self)
    local now = self.state.now
    if not now then return nil end
    local function row(label, value, color)
      return ui.hstack {
        width = 300,
        ui.text(label, small),
        ui.spacer(),
        ui.text(value, { size = 20, design = "monospaced", color = color or "fg" }),
      }
    end
    return ui.vstack {
      spacing = 8,
      row("UTC", locky.date.format("HH:mm:ss", now, "UTC"), "secondary"),
      row("LOCAL", locky.date.format("HH:mm:ss", now)),
      row("UNIX", tostring(now)),
      row("DOY", locky.date.format("DDD", now) .. " / " .. locky.date.format("yyyy", now)),
    }
  end,
})

local function segments(value, color)
  local cells = {}
  local lit = math.floor(value / 5 + 0.5)
  for i = 1, 20 do
    cells[i] = ui.rect({ width = 9, height = 14, color = i <= lit and color or "surface" })
  end
  return ui.hstack { spacing = 3, cells }
end

locky.widget.define("mission.telemetry", {
  description = "CPU, memory, disk, and battery as segmented bars",
  init = function(self)
    locky.sys.cpu()
    local function read(self)
      self:system({ "df", "-k", "/System/Volumes/Data" }, function(self, result)
        local used, free = result.stdout:match("\n%S+%s+%d+%s+(%d+)%s+(%d+)")
        if used then
          self:set({ disk = tonumber(used) / (tonumber(used) + tonumber(free)) * 100 })
        end
      end)
      local battery = locky.sys.battery()
      self:set({ cpu = locky.sys.cpu().usage, mem = locky.sys.memory().percent, bat = battery.present and battery.percent or nil })
    end
    self:after(1, read)
    self:every(5, read, { now = false })
  end,
  render = function(self)
    local s = self.state
    if not s.cpu then return nil end
    local rows = {}
    local function row(label, value, high_is_bad)
      if not value then return end
      local bad = high_is_bad and value >= 85 or (not high_is_bad and value <= 15)
      local caution = high_is_bad and value >= 65 or (not high_is_bad and value <= 30)
      local color = bad and "danger" or caution and "warning" or "secondary"
      rows[#rows + 1] = ui.hstack {
        spacing = 14,
        ui.text(label, { size = 12, design = "monospaced", tracking = 2, color = "muted", width = 70, text_align = "leading" }),
        segments(value, color),
        ui.text(("%5.1f"):format(value), { size = 14, design = "monospaced", width = 56, text_align = "trailing" }),
        ui.text(bad and "ALARM" or caution and "CAUTION" or "NOMINAL", { size = 11, design = "monospaced", tracking = 1.5, color = color, width = 70, text_align = "leading" }),
      }
    end
    row("CPU", s.cpu, true)
    row("MEM", s.mem, true)
    row("DISK", s.disk, true)
    row("POWER", s.bat, false)
    return ui.vstack { spacing = 12, align = "leading", ui.text("TELEMETRY", small), rows }
  end,
})
