-- countdown: the days until a date, or since one.
--   opts.to      "2026-12-25" (or "2026-12-25 18:30"); without it, the next New Year
--   opts.since   a date to count up from instead, such as "2024-03-01" (with opts.label "since I quit coffee")
--   opts.label   what the date is ("Vacation", "since launch"); opts.style "big" (default) or "line"
--   opts.size, opts.color
local ui = locky.ui
local time = require("locky.time")

locky.widget.define("countdown", {
  description = "Days until a date, or since one",
  opts = { style = "big", size = 15 },
  choices = { style = { "big", "line" } },
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
    local days, caption
    if o.since then
      local from = time.parse_date(o.since)
      if not from then
        error("countdown: opts.since must be a date such as \"2024-03-01\"")
      end
      days = -time.days_between(now, from)
      caption = o.label or ("since " .. o.since)
    else
      local target = o.to and time.parse_date(o.to)
      if o.to and not target then
        error("countdown: opts.to must be a date such as \"2026-12-25\"")
      end
      if not target then
        local t = os.date("*t", now)
        target = os.time({ year = t.year + 1, month = 1, day = 1, hour = 0 })
        caption = o.label or ("until " .. (t.year + 1))
      end
      days = time.days_between(now, target)
      caption = caption or o.label or ("until " .. o.to)
      if days < 0 then
        days, caption = -days, (o.label or o.to) .. ", days ago"
      elseif days == 0 then
        return ui.text(((o.label or o.to) .. " is today"), { size = o.size * 1.4, weight = "semibold", color = o.color or "accent" })
      end
    end
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
