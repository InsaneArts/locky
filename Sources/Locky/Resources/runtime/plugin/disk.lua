-- disk: how full the disk is, from `df`.
--   opts.style   "ring" (default), "bar", or "text"
--   opts.path    the volume (default "/System/Volumes/Data", where your files are); opts.label (default "Disk")
--   opts.size, opts.color, opts.width (the bar's), opts.warn (percent full at which it turns "warning", default 90)
local ui = locky.ui

local function bytes(n)
  local units = { "B", "KB", "MB", "GB", "TB", "PB" }
  local i = 1
  while n >= 1000 and i < #units do
    n, i = n / 1000, i + 1
  end
  return (n >= 100 and "%.0f %s" or "%.1f %s"):format(n, units[i])
end

locky.widget.define("disk", {
  description = "How full the disk is",
  opts = { style = "ring", path = "/System/Volumes/Data", label = "Disk", size = 13, width = 200, warn = 90 },
  choices = { style = { "ring", "bar", "text" } },
  init = function(self)
    self:every(300, function(self)
      self:system({ "df", "-k", self.opts.path }, function(self, result)
        local total, used, free = result.stdout:match("\n%S+%s+(%d+)%s+(%d+)%s+(%d+)")
        if total then
          self:set({ total = tonumber(total) * 1024, used = tonumber(used) * 1024, free = tonumber(free) * 1024 })
        end
      end)
    end)
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.total then
      return nil
    end
    -- APFS volumes share their space: full is what is used out of used plus free.
    local fraction = s.used / math.max(s.used + s.free, 1)
    local percent = math.floor(fraction * 100 + 0.5)
    local color = percent >= o.warn and "warning" or (o.color or "accent")
    local caption = ("%s free of %s"):format(bytes(s.free), bytes(s.total))
    if o.style == "text" then
      return ui.text(("%s %d%% · %s"):format(o.label, percent, caption), { size = o.size, mono = true, color = o.color })
    elseif o.style == "bar" then
      return ui.vstack {
        spacing = 5, align = "leading",
        ui.hstack {
          width = o.width,
          ui.text(o.label, { size = o.size, color = "muted", case = "upper", tracking = 1 }),
          ui.spacer(),
          ui.text(percent .. "%", { size = o.size, mono = true }),
        },
        ui.progress(fraction, { width = o.width, size = o.size * 0.4, color = color, background = "surface" }),
        ui.text(caption, { size = o.size * 0.85, color = "muted" }),
      }
    end
    return ui.hstack {
      spacing = 12,
      ui.zstack {
        ui.ring(fraction, { size = o.size * 4, stroke_width = o.size * 0.4, color = color, stroke = "surface" }),
        ui.symbol("internaldrive", { size = o.size * 1.2, color = "muted" }),
      },
      ui.vstack {
        spacing = 2, align = "leading",
        ui.text(percent .. "% full", { size = o.size * 1.15, weight = "semibold", mono = true }),
        ui.text(caption, { size = o.size * 0.9, color = "muted" }),
      },
    }
  end,
})
