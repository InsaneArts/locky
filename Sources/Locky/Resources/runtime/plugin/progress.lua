-- progress: how much of the day, week, month, and year has gone, after the "year progress" counters power users
-- keep on their desktops.
--   opts.style   "bars" (default), "rings", "dots" (a dot for each day of the year, the past ones filled), or "text"
--   opts.show    which spans, in order (default { "day", "week", "month", "year" })
--   opts.width   the bars' width (default 220); opts.size, opts.color, opts.track
local ui = locky.ui
local time = require("locky.time")

local names = { day = "Day", week = "Week", month = "Month", year = "Year" }

locky.widget.define("progress", {
  description = "How much of the day, week, month, and year has gone",
  opts = { style = "bars", show = { "day", "week", "month", "year" }, width = 220, size = 12 },
  choices = { style = { "bars", "rings", "dots", "text" } },
  init = function(self)
    local first = locky.date.locale().first_weekday
    self:every(60, function(self)
      local now = os.time()
      self:set({ p = time.progress(now, first), now = os.date("*t", now) })
    end, { align = true })
  end,
  render = function(self)
    local o, p = self.opts, self.state.p
    if not p then
      return nil
    end
    local s = o.size
    local function percent(v)
      return math.floor(v * 100) .. "%"
    end
    if o.style == "dots" then
      local t = self.state.now
      local days = os.date("*t", os.time({ year = t.year, month = 12, day = 31, hour = 12 })).yday
      local dots = {}
      for d = 1, days do
        dots[d] = ui.dot({ size = s * 0.55, color = d < t.yday and (o.color or "fg") or d == t.yday and "accent" or (o.track or "surface") })
      end
      return ui.vstack {
        spacing = s, align = "leading",
        ui.grid { columns = o.columns or 30, spacing = s * 0.35, dots },
        ui.hstack {
          ui.text(tostring(t.year), { size = s * 0.75, weight = "semibold", mono = true }),
          ui.spacer(),
          ui.text(("%s · %d days left"):format(percent(p.year), p.days_left_in_year), { size = s * 0.75, color = "muted", mono = true }),
        },
      }
    end
    if o.style == "text" then
      local parts = {}
      for _, key in ipairs(o.show) do
        parts[#parts + 1] = ("%s %s"):format(names[key] or key, percent(p[key] or 0))
      end
      return ui.text(table.concat(parts, "  ·  "), { size = s, mono = true, color = o.color })
    end
    if o.style == "rings" then
      local rings = {}
      for _, key in ipairs(o.show) do
        rings[#rings + 1] = ui.vstack {
          spacing = 6,
          ui.zstack {
            ui.ring(p[key] or 0, { size = s * 4.4, stroke_width = s * 0.4, color = o.color or "accent", stroke = o.track or "surface" }),
            ui.text(percent(p[key] or 0), { size = s, weight = "semibold", mono = true }),
          },
          ui.text(names[key] or key, { size = s * 0.85, color = "muted", case = "upper", tracking = 1 }),
        }
      end
      return ui.hstack { spacing = s * 1.5, rings }
    end
    local rows = {}
    for _, key in ipairs(o.show) do
      rows[#rows + 1] = ui.vstack {
        spacing = 5, align = "leading",
        ui.hstack {
          width = o.width,
          ui.text(names[key] or key, { size = s, color = "muted", case = "upper", tracking = 1 }),
          ui.spacer(),
          ui.text(percent(p[key] or 0), { size = s, mono = true, color = o.color }),
        },
        ui.progress(p[key] or 0, { width = o.width, size = s * 0.4, color = o.color or "accent", background = o.track or "surface" }),
      }
    end
    return ui.vstack { spacing = s, align = "leading", rows }
  end,
})
