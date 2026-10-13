-- countdown: the days until a date, or since one.
--   Families: circular (the days in a ring that fills as the date nears), rectangular, inline, small.
--   opts.to      "2026-12-25" (or "2026-12-25 18:30"); without it, the next New Year
--   opts.since   a date to count up from instead, such as "2024-03-01" (with opts.label "since I quit coffee")
--   opts.label   what the date is ("Vacation", "since launch"); opts.style "big" (default) or "line"
--   opts.size, opts.color
local ui = locky.ui
local time = require("locky.time")

-- The count: days (never negative), the old caption, and what the families show: the event's name, its
-- date, and whether it is today, past ("ago"), or counted from ("since").
local function count(o, now)
  if o.since then
    local from = time.parse_date(o.since)
    if not from then
      error("countdown: opts.since must be a date such as \"2024-03-01\"")
    end
    local days = -time.days_between(now, from)
    return { days = days, caption = o.label or ("since " .. o.since), since = true, date = from }
  end
  local target = o.to and time.parse_date(o.to)
  if o.to and not target then
    error("countdown: opts.to must be a date such as \"2026-12-25\"")
  end
  local caption, name
  if not target then
    local t = os.date("*t", now)
    target = os.time({ year = t.year + 1, month = 1, day = 1, hour = 0 })
    caption = o.label or ("until " .. (t.year + 1))
    name = o.label or "New Year"
  end
  local days = time.days_between(now, target)
  local c = { days = days, caption = caption or o.label or ("until " .. o.to), name = name or o.label, date = target }
  if days < 0 then
    c.days, c.caption, c.ago = -days, (o.label or o.to) .. ", days ago", true
  elseif days == 0 then
    c.today = true
  end
  return c
end

-- Apple's layouts. The ring fills over the last year before the date, or over each year since it.
local function family(c, o, f)
  local unit = c.days == 1 and "day" or "days"
  local date = locky.date.format("skeleton:EEEdMMMyyyy", c.date)
  local name, line, note
  if c.since then
    local label = o.label and (o.label:gsub("^%l", string.upper))
    name = label or ("Since " .. locky.date.format("skeleton:dMMMyyyy", c.date))
    line = label and date
    note = unit
  else
    name = c.name or date
    line = name ~= date and date or nil
    note = c.today and "Today" or c.ago and (unit .. " ago") or (unit .. " to go")
  end
  local fill = c.since and (c.days % 365) / 365 or c.ago and 1 or 1 - math.min(c.days, 365) / 365
  local symbol = c.since and "calendar.badge.clock" or "calendar"
  if f == "inline" then
    local text = c.today and (name .. " is today")
      or c.since and ("%d %s %s"):format(c.days, unit, o.label or ("since " .. locky.date.format("skeleton:dMMMyyyy", c.date)))
      or ("%d %s %s %s"):format(c.days, unit, c.ago and "since" or "until", name)
    return ui.hstack { spacing = 4, ui.symbol(symbol, ui.font("subheadline")), ui.text(text, ui.font("subheadline", { lines = 1 })) }
  elseif f == "circular" then
    return ui.zstack {
      ui.gauge(fill, { style = "capacity", color = "fg", size = 64 }),
      c.today and ui.symbol("party.popper.fill", { size = 24 }) or ui.vstack {
        spacing = -1,
        ui.text(c.days, { size = c.days >= 1000 and 15 or 20, weight = "semibold", mono = true }),
        ui.text(c.days == 1 and "DAY" or "DAYS", { size = 9, weight = "semibold", color = "muted", tracking = 0.5 }),
      },
    }
  elseif f == "rectangular" then
    return ui.vstack {
      spacing = 1, align = "leading", fill = "both",
      ui.hstack { spacing = 5, ui.symbol(symbol, ui.font("headline")), ui.text(name, ui.font("headline", { lines = 1 })) },
      ui.text(c.today and "Today" or (c.days .. " " .. unit), ui.font("title2", { weight = "semibold", mono = true, lines = 1 })),
      line and ui.text(line, ui.font("subheadline", { color = "muted", lines = 1 })),
    }
  end
  return ui.vstack {
    spacing = 0, align = "leading", fill = "both",
    ui.text(name, ui.font("subheadline", { weight = "semibold", color = "accent", lines = 1 })),
    line and ui.text(line, ui.font("footnote", { weight = "medium", color = "muted", lines = 1 })),
    ui.spacer(),
    c.today and ui.symbol("party.popper.fill", { size = 44 })
      or ui.text(c.days, { size = c.days >= 1000 and 44 or 56, weight = "semibold", mono = true, lines = 1 }),
    ui.text(note, ui.font("subheadline", { weight = "medium", color = "muted", lines = 1 })),
  }
end

locky.widget.define("countdown", {
  description = "Days until a date, or since one",
  opts = { style = "big", size = 15 },
  choices = { style = { "big", "line" } },
  families = { "circular", "rectangular", "inline", "small" },
  init = function(self)
    self:every(3600, function(self)
      self:set({ now = os.time() })
    end)
  end,
  render = function(self)
    local o, now = self.opts, self.state.now
    if not now then
      return nil
    end
    local c = count(o, now)
    if self.family then
      return family(c, o, self.family)
    end
    if c.today then
      return ui.text(((o.label or o.to) .. " is today"), { size = o.size * 1.4, weight = "semibold", color = o.color or "accent" })
    end
    local days, caption = c.days, c.caption
    local unit = days == 1 and "day" or "days"
    if o.style == "line" then
      return ui.text(("%d %s %s"):format(days, unit, caption), { size = o.size, color = o.color })
    end
    return ui.vstack {
      spacing = 2,
      ui.text(tostring(days), { size = o.size * 4, weight = "bold", mono = true, color = o.color or "accent" }),
      ui.text(unit .. " " .. caption, { size = o.size, color = "muted", case = "upper", tracking = 1.5 }),
    }
  end,
})
