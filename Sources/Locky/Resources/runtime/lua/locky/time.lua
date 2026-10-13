-- locky.time: time arithmetic for widgets: how far through the day or year, days until a date, the time in
-- words, binary digits, and Swatch Internet Time.
local M = {}

local function start_of(t)
  return os.time({ year = t.year, month = t.month, day = t.day, hour = 0 })
end

--- How far `now` is through its day, week (from the user's first weekday), month, and year, each 0 to 1.
function M.progress(now, first_weekday)
  local t = os.date("*t", now)
  local day_start = start_of(t)
  local day_end = os.time({ year = t.year, month = t.month, day = t.day + 1, hour = 0 })
  local back = (t.wday - (first_weekday or 2)) % 7
  local week_start = os.time({ year = t.year, month = t.month, day = t.day - back, hour = 0 })
  local week_end = os.time({ year = t.year, month = t.month, day = t.day - back + 7, hour = 0 })
  local month_start = os.time({ year = t.year, month = t.month, day = 1, hour = 0 })
  local month_end = os.time({ year = t.year, month = t.month + 1, day = 1, hour = 0 })
  local year_start = os.time({ year = t.year, month = 1, day = 1, hour = 0 })
  local year_end = os.time({ year = t.year + 1, month = 1, day = 1, hour = 0 })
  local function part(a, b)
    return math.min(math.max((now - a) / (b - a), 0), 1)
  end
  return {
    day = part(day_start, day_end), week = part(week_start, week_end), month = part(month_start, month_end),
    year = part(year_start, year_end),
    days_left_in_year = math.floor((year_end - day_start) / 86400 + 0.5) - 1,
  }
end

--- "2026-12-25" or "2026-12-25 18:30" → seconds since 1970 (local time), or nil.
function M.parse_date(text)
  local y, m, d, rest = tostring(text or ""):match("^(%d%d%d%d)-(%d%d?)-(%d%d?)(.*)$")
  if not y then
    return nil
  end
  local hour, min = rest:match("^[ T](%d%d?):(%d%d)")
  return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(hour) or 0, min = tonumber(min) or 0 })
end

--- Calendar days from `now`'s day to `target`'s day: positive ahead, negative past, 0 the same day.
function M.days_between(now, target)
  local a, b = os.date("*t", now), os.date("*t", target)
  local da = os.time({ year = a.year, month = a.month, day = a.day, hour = 12 })
  local db = os.time({ year = b.year, month = b.month, day = b.day, hour = 12 })
  return math.floor((db - da) / 86400 + 0.5)
end

local hours = { "twelve", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven" }
local phrases = {
  [0] = "%s o'clock", [5] = "five past %s", [10] = "ten past %s", [15] = "quarter past %s", [20] = "twenty past %s",
  [25] = "twenty-five past %s", [30] = "half past %s", [35] = "twenty-five to %s", [40] = "twenty to %s",
  [45] = "quarter to %s", [50] = "ten to %s", [55] = "five to %s",
}

--- The time in words, to the nearest five minutes: "ten past four", "quarter to nine", "nearly noon".
function M.fuzzy(hour, minute)
  local five = math.floor((minute + 2.5) / 5) * 5
  if five == 60 then
    five, hour = 0, hour + 1
  end
  local next = five >= 35 and hour + 1 or hour
  if five == 0 and next % 24 == 0 then
    return "midnight"
  elseif five == 0 and next % 24 == 12 then
    return "noon"
  end
  return phrases[five]:format(hours[next % 12 + 1])
end

--- A number's bits, highest first, as `width` booleans.
function M.bits(value, width)
  local list = {}
  for i = width - 1, 0, -1 do
    list[#list + 1] = (value >> i) & 1 == 1
  end
  return list
end

--- Swatch Internet Time: thousandths of the day in Biel (UTC+1), "@" and three digits.
function M.beat(now)
  local seconds = (now + 3600) % 86400
  return ("@%03d"):format(math.floor(seconds / 86.4))
end

return M
