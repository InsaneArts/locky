-- analog: an analog clock drawn with shapes.
--   opts.style     "minimal" (default), "railway" (Swiss station clock, red second disc), or "braun"
--   opts.size      diameter in points (default 260)
--   opts.seconds   show the second hand (default true)
--   opts.face, opts.hands, opts.ticks, opts.second  colors (palette roles or hex)
--   Families: circular (a monochrome face, as on the Lock Screen), small (Apple's Clock widget: a white face
--   with numerals and an orange second hand).
local ui = locky.ui

local styles = {
  minimal = { face = "surface", hands = "fg", ticks = "muted", second = "accent", numerals = false },
  railway = { face = "#fafaf8", hands = "#111111", ticks = "#111111", second = "#e2001a", numerals = false },
  braun = { face = "#0e0e0e", hands = "#f2f2f0", ticks = "#f2f2f0", second = "#f2c200", numerals = true },
}

local function hand(length, width, angle, color, tail)
  tail = tail or 0
  return ui.capsule({
    width = width, height = length + tail, color = color,
    offset = { 0, -(length - tail) / 2 }, rotation = angle,
  })
end

-- The first three letters of a city, as Apple's Clock widget marks its faces: "Cupertino" → "CUP".
local function code(city)
  return city:sub(1, (utf8.offset(city, 4) or #city + 1) - 1)
end

-- Apple's Clock widget face: twelve numerals inside minute ticks, black hands, an orange second hand.
-- d is the diameter; look holds face, hands, ticks, numerals, and second colors (second false: no second hand).
local function face(d, now, look, city)
  local r = d / 2
  local children = { look.face and ui.circle({ width = d, height = d, color = look.face }) }
  for i = 0, 59 do
    local hour = i % 5 == 0
    if hour or look.minutes then
      local length = r * (hour and 0.08 or 0.045)
      children[#children + 1] = ui.rect({
        width = hour and r * 0.03 or r * 0.015, height = length, color = look.ticks, opacity = hour and 1 or 0.55,
        offset = { 0, -(r * 0.93 - length / 2) }, rotation = i * 6,
      })
    end
  end
  if look.numerals then
    for h = 1, 12 do
      local angle = math.rad(h * 30)
      children[#children + 1] = ui.text(h, {
        size = r * 0.2, weight = "medium", color = look.numerals,
        offset = { math.sin(angle) * r * 0.68, -math.cos(angle) * r * 0.68 },
      })
    end
  end
  if city then
    children[#children + 1] = ui.text(code(city), {
      size = r * (look.numerals and 0.16 or 0.24), weight = "semibold", case = "upper", color = look.ticks, offset = { 0, -r * 0.36 },
    })
  end
  local minutes = now.min + now.sec / 60
  local hours = (now.hour % 12) + minutes / 60
  -- A hand as Apple draws it: a thin stem from the center, then the wide blade.
  local function hand(length, width, angle)
    return {
      ui.capsule({ width = r * 0.035, height = r * 0.2, color = look.hands, offset = { 0, -r * 0.1 }, rotation = angle }),
      ui.capsule({ width = width, height = length - r * 0.14, color = look.hands, offset = { 0, -(length + r * 0.14) / 2 }, rotation = angle }),
    }
  end
  local width = r * (look.numerals and 0.075 or 0.1)
  children[#children + 1] = hand(r * 0.55, width, hours * 30)
  children[#children + 1] = hand(r * 0.86, width, minutes * 6)
  children[#children + 1] = ui.circle({ width = r * 0.13, height = r * 0.13, color = look.hands })
  if look.second then
    children[#children + 1] = ui.capsule({
      width = r * 0.025, height = r * 1.1, color = look.second, offset = { 0, -r * 0.35 }, rotation = now.sec * 6,
    })
    children[#children + 1] = ui.circle({ width = r * 0.08, height = r * 0.08, color = look.second })
  end
  children[#children + 1] = ui.circle({ width = r * 0.03, height = r * 0.03, color = look.face or "black" })
  return ui.zstack { width = d, height = d, children }
end

local function family(f, o, now)
  -- The city would say where the Mac is: none in privacy mode.
  local city = locky.config.privacy ~= true and locky.date.format("VVV") or nil
  if f == "circular" then
    -- The Lock Screen's monochrome face on its disc.
    return face(70, now, { hands = "fg", ticks = "fg", numerals = false, minutes = true, second = false }, city)
  end
  return ui.zstack {
    fill = "both",
    face(138, now, {
      face = o.face or "#ffffff", hands = o.hands or "#000000", ticks = o.ticks or "#8e8e93", numerals = o.hands or "#000000",
      minutes = true, second = o.seconds and (o.second or "#ff9500"),
    }, city),
  }
end

locky.widget.define("analog", {
  description = "An analog clock",
  opts = { style = "minimal", size = 260, seconds = true },
  choices = { style = { "minimal", "railway", "braun" } },
  families = { "circular", "small" },
  init = function(self)
    local every = (self.opts.seconds and self.family ~= "circular") and 1 or 60
    self:every(every, function(self) self:set({ t = os.time() }) end, { align = true })
  end,
  render = function(self)
    local o = self.opts
    if self.family == "circular" or self.family == "small" then
      return family(self.family, o, os.date("*t", self.state.t or os.time()))
    end
    local look = locky.tbl.extend("force", styles[o.style] or styles.minimal, {
      face = o.face, hands = o.hands, ticks = o.ticks, second = o.second,
    })
    local now = os.date("*t", self.state.t or os.time())
    local r = o.size / 2
    local children = { ui.circle({ width = o.size, height = o.size, color = look.face, shadow = o.style == "railway" and 20 or nil }) }
    for i = 0, 59 do
      local hour = i % 5 == 0
      if hour or o.style ~= "braun" then
        local length = hour and r * (o.style == "railway" and 0.24 or o.style == "braun" and 0.07 or 0.12) or r * 0.055
        local width = hour and r * (o.style == "railway" and 0.07 or 0.025) or r * 0.02
        children[#children + 1] = ui.rect({
          width = width, height = length, color = look.ticks, opacity = hour and 1 or 0.6,
          offset = { 0, -(r * 0.94 - length / 2) }, rotation = i * 6,
        })
      end
    end
    if look.numerals then
      for h = 1, 12 do
        local angle = math.rad(h * 30)
        children[#children + 1] = ui.text(h, {
          size = o.size * 0.075, weight = "medium", font = "Helvetica Neue", color = look.hands,
          offset = { math.sin(angle) * r * 0.7, -math.cos(angle) * r * 0.7 },
        })
      end
    end
    local minutes = now.min + now.sec / 60
    local hours = (now.hour % 12) + minutes / 60
    children[#children + 1] = hand(r * 0.58, r * 0.085, hours * 30, look.hands, r * 0.18)
    children[#children + 1] = hand(r * 0.86, r * 0.06, minutes * 6, look.hands, r * 0.18)
    if o.seconds then
      local angle = now.sec * 6
      children[#children + 1] = hand(r * 0.6, r * 0.02, angle, look.second, r * 0.28)
      if o.style == "railway" then
        local a = math.rad(angle)
        children[#children + 1] = ui.circle({ width = r * 0.21, height = r * 0.21, color = look.second, offset = { math.sin(a) * r * 0.6, -math.cos(a) * r * 0.6 } })
      end
    end
    children[#children + 1] = ui.circle({ width = r * 0.06, height = r * 0.06, color = o.seconds and look.second or look.hands })
    return ui.zstack(children)
  end,
})
