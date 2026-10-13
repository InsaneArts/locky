-- locky.weather: the weather from wttr.in (https://wttr.in), for any widget. No key, no account: wttr.in finds
-- the place from your IP address unless you name one.
--
--   local weather = require("locky.weather")
--   init = function(self)
--     weather.watch(self, { location = "", every = 30 }, function(self, data) self:set({ weather = data }) end)
--   end
--
-- A reply is kept in ~/Library/Caches/Locky for `every` minutes (default 30), so a lock shows the last weather
-- at once, and widgets in one lock share one request. data is false while there is none, otherwise:
--   { place, temp, feels, high, low, unit ("C" or "F"), condition, code, symbol, night, humidity, wind,
--     wind_unit, wind_dir, uv, sunrise, sunset (minutes after midnight), moon_phase, moon_illumination,
--     days = { { date, high, low, code, symbol, condition }, ... three days },
--     hours = { { at (seconds since 1970), temp, code, symbol }, ... the next five three-hour forecasts },
--     fetched (seconds since 1970) }
-- In privacy mode (locky.config.privacy) place is nil: the city would say where the Mac is.
local M = {}

-- wttr.in's weather codes (World Weather Online's) as SF Symbols, by day and by night.
local symbols = {
  [113] = { "sun.max.fill", "moon.stars.fill" },
  [116] = { "cloud.sun.fill", "cloud.moon.fill" },
  [119] = { "cloud.fill" }, [122] = { "smoke.fill" },
  [143] = { "cloud.fog.fill" }, [248] = { "cloud.fog.fill" }, [260] = { "cloud.fog.fill" },
  [200] = { "cloud.bolt.fill" }, [386] = { "cloud.bolt.rain.fill" }, [389] = { "cloud.bolt.rain.fill" },
  [392] = { "cloud.bolt.fill" }, [395] = { "cloud.snow.fill" },
  [227] = { "wind.snow" }, [230] = { "wind.snow" },
}
for _, code in ipairs({ 176, 263, 266, 293, 296, 353 }) do symbols[code] = { "cloud.drizzle.fill" } end
for _, code in ipairs({ 299, 302, 305, 308, 356, 359 }) do symbols[code] = { "cloud.rain.fill" } end
for _, code in ipairs({ 179, 182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377 }) do symbols[code] = { "cloud.sleet.fill" } end
for _, code in ipairs({ 323, 326, 329, 332, 335, 338, 368, 371 }) do symbols[code] = { "cloud.snow.fill" } end

--- The SF Symbol for a weather code, by night when `night` is true.
function M.symbol(code, night)
  local pair = symbols[tonumber(code)] or { "cloud.fill" }
  return night and pair[2] or pair[1]
end

-- "07:11 AM" → 431.
local function minutes(text)
  local h, m, half = tostring(text or ""):match("^(%d+):(%d+)%s*([AP]M)")
  if not h then
    return nil
  end
  h, m = tonumber(h) % 12, tonumber(m)
  return (half == "PM" and h + 12 or h) * 60 + m
end

local function number(value)
  return tonumber(value)
end

--- Whether to show °F and mph: opts.units "imperial" or "metric", or by the user's region.
function M.imperial(units)
  if units == "imperial" then
    return true
  elseif units == "metric" then
    return false
  end
  local id = locky.date.locale().identifier or ""
  return id:match("_US") ~= nil or id:match("_LR") ~= nil or id:match("_MM") ~= nil
end

--- wttr.in's JSON (format=j1) as the table above, or nil. `now` is the time to judge day and night by.
function M.parse(json, imperial, now)
  local ok, reply = pcall(locky.json.decode, json)
  if not ok or type(reply) ~= "table" or type(reply.current_condition) ~= "table" then
    return nil
  end
  local current = reply.current_condition[1]
  local today = type(reply.weather) == "table" and reply.weather[1] or {}
  if type(current) ~= "table" then
    return nil
  end
  local astronomy = type(today.astronomy) == "table" and today.astronomy[1] or {}
  local sunrise, sunset = minutes(astronomy.sunrise), minutes(astronomy.sunset)
  local clock = os.date("*t", now or os.time())
  local at = clock.hour * 60 + clock.min
  local night = sunrise and sunset and (at < sunrise or at >= sunset) or false
  local function temp(t, c, f)
    return number(t[imperial and f or c])
  end
  local function description(t)
    return type(t.weatherDesc) == "table" and t.weatherDesc[1] and tostring(t.weatherDesc[1].value or ""):gsub("%s+$", "") or ""
  end
  local days = {}
  for i, day in ipairs(type(reply.weather) == "table" and reply.weather or {}) do
    -- The forecast for midday stands for the day.
    local noon = type(day.hourly) == "table" and (day.hourly[5] or day.hourly[1]) or {}
    days[i] = {
      date = day.date, high = temp(day, "maxtempC", "maxtempF"), low = temp(day, "mintempC", "mintempF"),
      code = number(noon.weatherCode), symbol = M.symbol(noon.weatherCode, false), condition = description(noon),
    }
  end
  -- wttr.in forecasts every three hours ("0", "300", ... "2100"); the next five from now, today's and tomorrow's.
  local hours, at_time = {}, now or os.time()
  for _, day in ipairs(type(reply.weather) == "table" and reply.weather or {}) do
    local y, m, d = tostring(day.date or ""):match("^(%d+)-(%d+)-(%d+)$")
    for _, hour in ipairs(y and type(day.hourly) == "table" and day.hourly or {}) do
      local hhmm = tonumber(hour.time)
      if type(hour) == "table" and hhmm then
        local at = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = hhmm // 100, min = hhmm % 100 })
        if at > at_time - 1800 and #hours < 5 then
          local h = hhmm // 100 * 60
          local dark = sunrise and sunset and (h < sunrise or h >= sunset) or false
          hours[#hours + 1] = { at = at, temp = temp(hour, "tempC", "tempF"), code = number(hour.weatherCode), symbol = M.symbol(hour.weatherCode, dark) }
        end
      end
    end
  end
  local area = type(reply.nearest_area) == "table" and reply.nearest_area[1] or {}
  local place = type(area.areaName) == "table" and area.areaName[1] and area.areaName[1].value or nil
  return {
    place = locky.config.privacy ~= true and place or nil,
    temp = temp(current, "temp_C", "temp_F"), feels = temp(current, "FeelsLikeC", "FeelsLikeF"),
    high = temp(today, "maxtempC", "maxtempF"), low = temp(today, "mintempC", "mintempF"),
    unit = imperial and "F" or "C",
    condition = description(current), code = number(current.weatherCode),
    symbol = M.symbol(current.weatherCode, night), night = night,
    humidity = number(current.humidity), uv = number(current.uvIndex),
    wind = number(current[imperial and "windspeedMiles" or "windspeedKmph"]), wind_unit = imperial and "mph" or "km/h",
    wind_dir = current.winddir16Point,
    sunrise = sunrise, sunset = sunset,
    moon_phase = astronomy.moon_phase, moon_illumination = number(astronomy.moon_illumination),
    days = days,
    hours = hours,
  }
end

--- wttr.in's address for a location. Spaces become "+", as wttr.in writes them; anything else that is not plain
--- (such as "?", "#", "/", or "é") is percent-encoded, so a location stays one part of the path.
function M.url(location)
  local path = location:gsub(" ", "+"):gsub("[^%w%-._~,+@]", function(c)
    return ("%%%02X"):format(c:byte())
  end)
  return "https://wttr.in/" .. path .. "?format=j1"
end

local cache_dir = locky.fs.home .. "/Library/Caches/Locky"

local function cache_file(location)
  local key = location == "" and "here" or location:lower():gsub("[^%w]+", "-")
  return ("%s/weather-%s.json"):format(cache_dir, key)
end

local function read_cache(location)
  local text = locky.fs.read(cache_file(location))
  local ok, cached = pcall(locky.json.decode, text or "")
  if ok and type(cached) == "table" and type(cached.json) == "string" and type(cached.fetched) == "number" then
    return cached
  end
  return nil
end

local function write_cache(location, json)
  local file = io.open(cache_file(location), "w")
  if file then
    file:write(locky.json.encode({ fetched = os.time(), json = json }))
    file:close()
  end
end

-- Requests in flight, by location, and who waits for each.
local waiting = {}

--- Shows the weather now (the cached reply, if any) and keeps it fresh, owned by the widget `self`. opts:
--- location (a city, an airport code, "lat,lon", or "" for wttr.in's guess), every (minutes), units.
function M.watch(self, opts, fn)
  locky.validate("opts", opts, "table")
  locky.validate("fn", fn, "callable")
  local location = tostring(opts.location or "")
  local every = math.max(10, tonumber(opts.every) or 30) * 60
  local imperial = M.imperial(opts.units)
  local shown
  local function show(self, cached)
    if cached and cached.fetched ~= shown then
      shown = cached.fetched
      local data = M.parse(cached.json, imperial)
      if data then
        data.fetched = cached.fetched
      end
      fn(self, data or false)
    end
  end
  local function refresh(self)
    local cached = read_cache(location)
    show(self, cached)
    if cached and os.time() - cached.fetched < every then
      return
    end
    local entry = { self = self, show = show, fail = function(self) if not shown then fn(self, false) end end }
    if waiting[location] then
      table.insert(waiting[location], entry)
      return
    end
    waiting[location] = { entry }
    local url = M.url(location)
    self:system({ "mkdir", "-p", cache_dir }, function(self)
      self:system({ "curl", "-sfL", "--max-time", "10", url }, { timeout = 12 }, function(self, result)
        local ok = result.code == 0 and M.parse(result.stdout, imperial) ~= nil
        if ok then
          write_cache(location, result.stdout)
        end
        local list = waiting[location] or {}
        waiting[location] = nil
        local fresh = ok and read_cache(location) or nil
        for _, entry in ipairs(list) do
          if fresh then
            entry.show(entry.self, fresh)
          else
            entry.fail(entry.self)
          end
        end
      end)
    end)
  end
  -- Check every few minutes; a request goes out only when the cache is older than `every`.
  self:every(300, refresh)
end

return M
