-- locky.sky: the moon's phase, worked out on the Mac: no network.
--
--   local moon = require("locky.sky").moon(os.time())
--   moon.name, moon.symbol, moon.illumination, moon.days_to_full
local M = {}

local month = 29.530588853

local phases = {
  { "New Moon", "moonphase.new.moon" },
  { "Waxing Crescent", "moonphase.waxing.crescent" },
  { "First Quarter", "moonphase.first.quarter" },
  { "Waxing Gibbous", "moonphase.waxing.gibbous" },
  { "Full Moon", "moonphase.full.moon" },
  { "Waning Gibbous", "moonphase.waning.gibbous" },
  { "Last Quarter", "moonphase.last.quarter" },
  { "Waning Crescent", "moonphase.waning.crescent" },
}

local rad = math.pi / 180

--- The moon at `time` (seconds since 1970): age in days, phase (0 new, 0.5 full), illumination (0 to 100),
--- name, SF Symbol, and whole days to the next full and new moon. From the sun's and the moon's ecliptic
--- longitudes (the Astronomical Almanac's low-precision formulas), right to a few hours.
function M.moon(time)
  local d = (time - 946728000) / 86400  -- days since J2000.0
  local g = (357.529 + 0.98560028 * d) * rad
  local sun = 280.459 + 0.98564736 * d + 1.915 * math.sin(g) + 0.020 * math.sin(2 * g)
  local anomaly = (134.963 + 13.064993 * d) * rad
  local elongation_mean = (297.850 + 12.190749 * d) * rad
  local moon = 218.316 + 13.176396 * d + 6.289 * math.sin(anomaly) - 1.274 * math.sin(anomaly - 2 * elongation_mean)
    + 0.658 * math.sin(2 * elongation_mean)
  local angle = (moon - sun) % 360
  local phase = angle / 360
  local illumination = math.floor((1 - math.cos(angle * rad)) / 2 * 100 + 0.5)
  local entry = phases[math.floor(phase * 8 + 0.5) % 8 + 1]
  -- Whole days until the moon is at `target` (0.5 full, 0 new); within half a day after it, that is today.
  local function ahead(target)
    local days = (target - phase) % 1 * month
    return days > month - 0.5 and 0 or math.floor(days + 0.5)
  end
  return {
    age = phase * month, phase = phase, illumination = illumination, name = entry[1], symbol = entry[2],
    days_to_full = ahead(0.5), days_to_new = ahead(0),
  }
end

return M
