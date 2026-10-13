-- progress: how much of the day, week, month, and year has gone, after the "year progress" counters power users
-- keep on their desktops.
--   Families: circular (the year in a ring), rectangular (a bar for each span), inline (the first span and the last), small (a ring for each
--   span, like Apple's Batteries widget), medium (the rings in a row).
--   opts.style   "bars" (default), "rings", "dots" (a dot for each day of the year, the past ones filled), or "text"
--   opts.show    which spans, in order (default { "day", "week", "month", "year" })
--   opts.width   the bars' width (default 220); opts.size, opts.color, opts.track
local ui = locky.ui
local time = require("locky.time")

local names = { day = "Day", week = "Week", month = "Month", year = "Year" }

local function percent(v)
  return math.floor(v * 100) .. "%"
end

-- Apple's layouts, in the text color: the Lock Screen's are monochrome, and the rings read like Batteries'.
local function family(p, o, f, now)
  local show = o.show
  if f == "inline" then
    -- One line is short: the first span and the last.
    local parts = {}
    for _, key in ipairs({ show[1], #show > 1 and show[#show] or nil }) do
      parts[#parts + 1] = ("%s %s"):format(names[key] or key, percent(p[key] or 0))
    end
    return ui.hstack { spacing = 4, ui.symbol("hourglass", ui.font("subheadline")), ui.text(table.concat(parts, " · "), ui.font("subheadline", { mono = true, lines = 1 })) }
  elseif f == "circular" then
    return ui.zstack {
      ui.gauge(p.year, { style = "capacity", color = "fg", size = 64 }),
      ui.vstack {
        spacing = -1,
        ui.text(math.floor(p.year * 100), { size = 20, weight = "semibold", mono = true }),
        ui.text(tostring(now.year), { size = 9, weight = "semibold", color = "muted", mono = true }),
      },
    }
  elseif f == "rectangular" then
    return ui.vstack {
      spacing = 0, fill = "both",
      ui.each(show, function(key)
        return ui.hstack {
          spacing = 6, fill = "height",
          ui.text(names[key] or key, ui.font("footnote", { weight = "semibold", width = 42, text_align = "leading" })),
          ui.gauge(p[key] or 0, { style = "linear-capacity", color = "fg", size = 88 }),
          ui.text(percent(p[key] or 0), ui.font("footnote", { weight = "medium", color = "muted", mono = true, width = 34, text_align = "trailing" })),
        }
      end),
    }
  end
  local ring = function(key, size)
    return ui.zstack {
      ui.gauge(p[key] or 0, { style = "capacity", color = "fg", size = size }),
      ui.vstack {
        spacing = -1,
        ui.text(math.floor((p[key] or 0) * 100), { size = size * 0.3, weight = "semibold", mono = true }),
        ui.text(names[key] or key, { size = size * 0.17, weight = "semibold", color = "muted" }),
      },
    }
  end
  if f == "small" then
    return ui.grid { columns = 2, spacing = 14, fill = "both", ui.each(show, function(key) return ring(key, 60) end) }
  end
  return ui.hstack {
    fill = "both",
    ui.each(show, function(key)
      return ui.vstack {
        spacing = 8, fill = "width",
        ui.zstack {
          ui.gauge(p[key] or 0, { style = "capacity", color = "fg", size = 68 }),
          ui.text(percent(p[key] or 0), ui.font("callout", { weight = "semibold", mono = true })),
        },
        ui.text(names[key] or key, ui.font("subheadline", { weight = "medium", color = "muted" })),
      }
    end),
  }
end

locky.widget.define("progress", {
  description = "How much of the day, week, month, and year has gone",
  opts = { style = "bars", show = { "day", "week", "month", "year" }, width = 220, size = 12 },
  choices = { style = { "bars", "rings", "dots", "text" } },
  families = { "circular", "rectangular", "inline", "small", "medium" },
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
    if self.family then
      return family(p, o, self.family, self.state.now)
    end
    local s = o.size
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
