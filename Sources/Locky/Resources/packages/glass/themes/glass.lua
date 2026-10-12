-- Liquid Glass: the lock screen of iOS 26 and macOS Tahoe, on your own wallpaper. A huge rounded clock, the
-- date above it, and four glass gauges under it. The password field stays hidden until you type or move the
-- mouse. Without a desktop picture, the "glass" shader paints a sky-and-wave scene instead.

-- The ring tint: the most colorful of the wallpaper's dominant colors, made light so it reads on glass.
local function hsl(hex)
  local r, g, b = tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local l = (max + min) / 2
  if max == min then
    return 0, 0, l
  end
  local d = max - min
  local s = l > 0.5 and d / (2 - max - min) or d / (max + min)
  local h = max == r and (g - b) / d + (g < b and 6 or 0) or max == g and (b - r) / d + 2 or (r - g) / d + 4
  return h / 6, s, l
end

local function hex(h, s, l)
  local function channel(n)
    local k = (n + h * 12) % 12
    local value = l - s * math.min(l, 1 - l) * math.max(-1, math.min(k - 3, 9 - k, 1))
    return math.floor(value * 255 + 0.5)
  end
  return ("#%02x%02x%02x"):format(channel(0), channel(8), channel(4))
end

local function tint(colors)
  local best, score = nil, 0.12
  for i, color in ipairs(colors) do
    local h, s, l = hsl(color)
    local vivid = s * (1 - math.abs(l - 0.5) * 1.2) * (1 - (i - 1) * 0.06)  -- colorful, not too dark or light, common
    if vivid > score then
      best, score = { h, s }, vivid
    end
  end
  return best and hex(best[1], math.max(0.45, math.min(best[2], 0.8)), 0.74)
end

-- A dynamic wallpaper gives only its thumbnail: about 200 pixels wide, often a mosaic of its times of day.
-- That cannot look sharp behind the clock, so the theme paints its own scene then, as with no wallpaper.
local wallpaper = locky.sys.wallpaper()
if wallpaper and wallpaper:find("/.thumbnails/", 1, true) then
  wallpaper = nil
end

local background = wallpaper and { wallpaper = true, blur = 1, dim = 0.12 }
  or { shader = "glass", colors = { "sky", "sand", "wave", "crest", "cream" }, resolution = 1, fps = 15, dim = 0.06 }

return {
  name = "Liquid Glass",
  description = "A huge clock and glass gauges on your own wallpaper, after iOS 26 and macOS Tahoe.",
  palette = {
    bg = "#1c3a66", fg = "#ffffff", muted = "#ffffffb3",
    accent = wallpaper and tint(locky.sys.wallpaper_colors()) or "#8ec5ff",
    surface = "#ffffff1f", border = "#ffffff40", track = "#ffffff40",
    -- The fallback scene's colors, read by shaders/glass.metal.
    sky = "#8ec5ff", sand = "#ebdcc3", wave = "#1e4fd8", crest = "#bfe0ff", cream = "#ffe9b0",
  },
  font = { design = "default" },
  background = background,
  card = { style = "glass", radius = 24 },
  auth = {
    style = "pill", anchor = "bottom", offset = { 0, -64 }, width = 260, avatar = true, name = true,
    reveal = "activity", idle = 20, dim = 0.25,
  },
  widgets = {
    { "date", anchor = "top", offset = { 0, 130 }, opts = { size = 22, weight = "semibold", color = "#ffffffe6", shadow = 12 } },
    { "glass.clock", anchor = "top", offset = { 0, 104 } },
    { "glass.gauges", anchor = "top", offset = { 0, 402 } },
  },
}
