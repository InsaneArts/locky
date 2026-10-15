-- locky.weather: the weather from Open-Meteo (https://open-meteo.com), for any widget. No key, no account. Weather
-- data by Open-Meteo.com, under CC BY 4.0.
--
--   local weather = require("locky.weather")
--   init = function(self)
--     weather.watch(self, { location = "", every = 30 }, function(self, data) self:set({ data = data }) end)
--   end
--
-- A reply is kept in ~/Library/Caches/Locky for `every` minutes (default 30), so a lock shows the last weather
-- at once, and widgets in one lock share one request. data is false while there is none, otherwise:
--   { place, temp, feels, high, low, unit ("C" or "F"), condition, code (WMO), symbol, night, humidity, wind,
--     wind_unit, wind_dir, uv, sunrise, sunset (minutes after midnight), moon_phase, moon_illumination,
--     days = { { date, high, low, code, symbol, condition }, ... three days },
--     hours = { { at (seconds since 1970), temp, code, symbol }, ... this hour and the next four },
--     fetched (seconds since 1970) }
-- In privacy mode (locky.config.privacy) place is nil: the city would say where the Mac is.
local M = {}
local sky = require("locky.sky")

-- WMO weather codes, as Open-Meteo gives them, in Apple Weather's words and SF Symbols: by day, then by night.
local codes = {
  [0] = { "Sunny", "sun.max.fill", "Clear", "moon.stars.fill" },
  [1] = { "Mostly Sunny", "cloud.sun.fill", "Mostly Clear", "cloud.moon.fill" },
  [2] = { "Partly Cloudy", "cloud.sun.fill", "Partly Cloudy", "cloud.moon.fill" },
  [3] = { "Cloudy", "cloud.fill" },
  [45] = { "Fog", "cloud.fog.fill" }, [48] = { "Fog", "cloud.fog.fill" },
  [51] = { "Drizzle", "cloud.drizzle.fill" }, [53] = { "Drizzle", "cloud.drizzle.fill" }, [55] = { "Drizzle", "cloud.drizzle.fill" },
  [56] = { "Freezing Drizzle", "cloud.sleet.fill" }, [57] = { "Freezing Drizzle", "cloud.sleet.fill" },
  [61] = { "Rain", "cloud.rain.fill" }, [63] = { "Rain", "cloud.rain.fill" }, [65] = { "Heavy Rain", "cloud.heavyrain.fill" },
  [66] = { "Freezing Rain", "cloud.sleet.fill" }, [67] = { "Freezing Rain", "cloud.sleet.fill" },
  [71] = { "Snow", "cloud.snow.fill" }, [73] = { "Snow", "cloud.snow.fill" }, [75] = { "Heavy Snow", "cloud.snow.fill" },
  [77] = { "Snow", "cloud.snow.fill" },
  [80] = { "Showers", "cloud.sun.rain.fill", "Showers", "cloud.moon.rain.fill" },
  [81] = { "Showers", "cloud.rain.fill" }, [82] = { "Heavy Rain", "cloud.heavyrain.fill" },
  [85] = { "Snow Showers", "cloud.snow.fill" }, [86] = { "Snow Showers", "cloud.snow.fill" },
  [95] = { "Thunderstorms", "cloud.bolt.rain.fill" }, [96] = { "Thunderstorms", "cloud.bolt.rain.fill" },
  [99] = { "Thunderstorms", "cloud.bolt.rain.fill" },
}

--- A WMO weather code's words and SF Symbol, by night when `night` is true.
function M.condition(code, night)
  local entry = codes[tonumber(code)] or { "", "cloud.fill" }
  if night and entry[3] then
    return entry[3], entry[4]
  end
  return entry[1], entry[2]
end

--- The SF Symbol for a WMO weather code, by night when `night` is true.
function M.symbol(code, night)
  return select(2, M.condition(code, night))
end

--- Whether to show °F and mph: opts.units "fahrenheit" or "celsius" ("imperial" and "metric" too), or else the
--- Mac's own temperature unit (System Settings › General › Language & Region).
function M.imperial(units)
  if units == "fahrenheit" or units == "imperial" then
    return true
  elseif units == "celsius" or units == "metric" then
    return false
  end
  return locky.date.locale().temperature == "F"
end

local function round(value)
  return type(value) == "number" and math.floor(value + 0.5) or nil
end

local compass = { "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW" }

-- A time as minutes after midnight on the Mac's clock, as the sun widget counts them.
local function minutes(time)
  if type(time) ~= "number" then
    return nil
  end
  local t = os.date("*t", time)
  return t.hour * 60 + t.min
end

--- Open-Meteo's forecast (timeformat=unixtime) as the table above, without place and fetched, or nil. `now` is the
--- time to start the hours from, and to work out the moon for.
function M.parse(json, now)
  local ok, reply = pcall(locky.json.decode, json)
  if not ok or type(reply) ~= "table" or type(reply.current) ~= "table" then
    return nil
  end
  now = now or os.time()
  local current, units = reply.current, type(reply.current_units) == "table" and reply.current_units or {}
  local daily, hourly = type(reply.daily) == "table" and reply.daily or {}, type(reply.hourly) == "table" and reply.hourly or {}
  local function at(list, i)
    return type(list) == "table" and list[i] or nil
  end
  local imperial = tostring(units.temperature_2m or ""):find("F") ~= nil
  local night = current.is_day == 0
  local condition, symbol = M.condition(current.weather_code, night)
  local days = {}
  for i, time in ipairs(type(daily.time) == "table" and daily.time or {}) do
    local words, icon = M.condition(at(daily.weather_code, i), false)
    days[i] = {
      -- The day's date where the weather is: its midnight, in its own time zone.
      date = os.date("!%Y-%m-%d", time + (tonumber(reply.utc_offset_seconds) or 0)),
      high = round(at(daily.temperature_2m_max, i)), low = round(at(daily.temperature_2m_min, i)),
      code = at(daily.weather_code, i), symbol = icon, condition = words,
    }
  end
  local hours = {}
  for i, time in ipairs(type(hourly.time) == "table" and hourly.time or {}) do
    if time > now - 3600 and #hours < 5 then
      hours[#hours + 1] = {
        at = time, temp = round(at(hourly.temperature_2m, i)), code = at(hourly.weather_code, i),
        symbol = M.symbol(at(hourly.weather_code, i), at(hourly.is_day, i) == 0),
      }
    end
  end
  local direction = tonumber(current.wind_direction_10m)
  local moon = sky.moon(now)
  return {
    temp = round(current.temperature_2m), feels = round(current.apparent_temperature),
    high = days[1] and days[1].high, low = days[1] and days[1].low,
    unit = imperial and "F" or "C",
    condition = condition, code = current.weather_code, symbol = symbol, night = night,
    humidity = round(current.relative_humidity_2m), uv = round(current.uv_index),
    wind = round(current.wind_speed_10m), wind_unit = imperial and "mph" or "km/h",
    wind_dir = direction and compass[math.floor(direction / 22.5 + 0.5) % 16 + 1],
    sunrise = minutes(at(daily.sunrise, 1)), sunset = minutes(at(daily.sunset, 1)),
    moon_phase = moon.name, moon_illumination = moon.illumination,
    days = days,
    hours = hours,
  }
end

-- Everything but letters, digits, and "-._~" percent-encoded, so text stays one value of the query.
local function encode(text)
  return (text:gsub("[^%w%-._~]", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

--- Open-Meteo's forecast address for a place, in °F and mph when `imperial`.
function M.url(lat, lon, imperial)
  return ("https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f"
    .. "&current=temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m,wind_direction_10m,uv_index"
    .. "&hourly=temperature_2m,weather_code,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"
    .. "&timezone=auto&timeformat=unixtime&forecast_days=3%s"):format(lat, lon, imperial and "&temperature_unit=fahrenheit&wind_speed_unit=mph" or "")
end

--- Open-Meteo's geocoding address for a place's name: the part before the first comma, names in `language`.
function M.geocode_url(name, language)
  local city = locky.str.trim(name:match("^[^,]*"))
  return ("https://geocoding-api.open-meteo.com/v1/search?name=%s&count=10&language=%s&format=json"):format(encode(city), encode(language or "en"))
end

--- Open-Meteo's geocoding reply for `name` as { lat, lon, name }, or nil. After a comma, the rest of the name picks
--- among places with the same name: "Paris, Texas" finds the one whose state or country is Texas.
function M.parse_place(json, name)
  local ok, reply = pcall(locky.json.decode, json)
  if not ok or type(reply) ~= "table" or type(reply.results) ~= "table" then
    return nil
  end
  local rest = locky.str.trim(tostring(name or ""):match(",(.*)$") or ""):lower()
  local function matches(r)
    for _, field in ipairs({ "country", "country_code", "admin1", "admin2" }) do
      if type(r[field]) == "string" and r[field]:lower() == rest then
        return true
      end
    end
    return false
  end
  local found
  for _, result in ipairs(reply.results) do
    if type(result) == "table" and tonumber(result.latitude) and tonumber(result.longitude) then
      if rest == "" or matches(result) then
        found = result
        break
      end
      found = found or result
    end
  end
  return found and { lat = tonumber(found.latitude), lon = tonumber(found.longitude), name = found.name } or nil
end

--- "41.7151,44.8271" (spaces allowed) as two numbers, or nil.
function M.coordinates(text)
  local lat, lon = tostring(text or ""):match("^%s*(%-?[%d.]+)%s*,%s*(%-?[%d.]+)%s*$")
  lat, lon = tonumber(lat), tonumber(lon)
  if lat and lon and math.abs(lat) <= 90 and math.abs(lon) <= 180 then
    return lat, lon
  end
  return nil
end

--- Where the cache files go. Tests point it at their own folder.
M.cache_dir = locky.fs.home .. "/Library/Caches/Locky"

local function read_json(file)
  local ok, value = pcall(locky.json.decode, locky.fs.read(M.cache_dir .. "/" .. file) or "")
  return ok and type(value) == "table" and value or nil
end

local function write_json(file, value)
  local handle = io.open(M.cache_dir .. "/" .. file, "w")
  if handle then
    handle:write(locky.json.encode(value))
    handle:close()
  end
end

--- Gets `url` and calls done(self, body) with the body, or nil when it failed. Tests replace it, so no test goes to
--- the network.
function M.fetch(self, url, done)
  self:system({ "mkdir", "-p", M.cache_dir }, function(self)
    self:system({ "curl", "-sfL", "--max-time", "10", url }, { timeout = 12 }, function(self, result)
      done(self, result.code == 0 and result.stdout or nil)
    end)
  end)
end

-- Requests in flight, by address, and who waits for each: widgets in one lock share one request.
local waiting = {}

local function get(self, url, done)
  local entry = { self = self, done = done }
  if waiting[url] then
    table.insert(waiting[url], entry)
    return
  end
  waiting[url] = { entry }
  M.fetch(self, url, function(_, body)
    local list = waiting[url] or {}
    waiting[url] = nil
    for _, entry in ipairs(list) do
      entry.done(entry.self, body)
    end
  end)
end

--- Finds where `location` is and calls done(self, { lat, lon, name }) or done(self, nil). "lat,lon" is used as it
--- is, named `name`; "" and "current" are the Mac's location (locky.location()); anything else is a place's name,
--- looked up once with Open-Meteo's geocoding and kept.
function M.locate(self, location, name, done)
  local lat, lon = M.coordinates(location)
  if lat then
    return done(self, { lat = lat, lon = lon, name = name })
  end
  local key = locky.str.trim(location):lower()
  if key == "" or key == "current" then
    return done(self, locky.location())
  end
  local file = ("place-%s.json"):format((key:gsub("[^%w]+", "-")))
  local cached = read_json(file)
  if cached and tonumber(cached.lat) and tonumber(cached.lon) then
    return done(self, cached)
  end
  get(self, M.geocode_url(location, locky.date.locale().language), function(self, body)
    local place = body and M.parse_place(body, location)
    if place then
      write_json(file, place)
    end
    done(self, place)
  end)
end

--- Shows the weather now (the cached reply, if any) and keeps it fresh, owned by the widget `self`. opts:
--- location ("lat,lon", a place's name, or "" for the Mac's location), place_name (the name for "lat,lon"), every
--- (minutes), units ("automatic", "celsius", or "fahrenheit").
function M.watch(self, opts, fn)
  locky.validate("opts", opts, "table")
  locky.validate("fn", fn, "callable")
  local location = tostring(opts.location or "")
  local every = math.max(10, tonumber(opts.every) or 30) * 60
  local imperial = M.imperial(opts.units)
  local shown
  local function show(self, file, cached, place)
    local key = file .. cached.fetched
    if key ~= shown then
      shown = key
      local data = M.parse(cached.json)
      if data then
        data.fetched = cached.fetched
        data.place = locky.config.privacy ~= true and place and place.name or nil
      end
      fn(self, data or false)
    end
  end
  local function fail(self)
    if not shown then
      fn(self, false)
    end
  end
  local function refresh(self)
    M.locate(self, location, opts.place_name, function(self, place)
      if not place then
        return fail(self)
      end
      -- Rounded to about a kilometre, so a location that moves a little keeps its cache.
      local file = ("forecast-%.2f,%.2f-%s.json"):format(place.lat, place.lon, imperial and "f" or "c")
      local cached = read_json(file)
      cached = cached and type(cached.json) == "string" and type(cached.fetched) == "number" and cached or nil
      if cached then
        show(self, file, cached, place)
        if os.time() - cached.fetched < every then
          return
        end
      end
      get(self, M.url(place.lat, place.lon, imperial), function(self, body)
        if body and M.parse(body) then
          local fresh = { fetched = os.time(), json = body }
          write_json(file, fresh)
          show(self, file, fresh, place)
        else
          fail(self)
        end
      end)
    end)
  end
  -- Check every few minutes; a request goes out only when the cache is older than `every`.
  self:every(300, refresh)
end

return M
