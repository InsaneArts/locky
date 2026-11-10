-- Material You: a Material 3 lock screen whose colors are generated from your wallpaper. Soft rounded cards,
-- a big friendly clock, pill chips. Every Mac looks different because it follows your picture.
local function hex2rgb(h) h = h:gsub("#", ""); return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16) end
local function clamp(x) return math.max(0, math.min(255, math.floor(x + 0.5))) end
local function rgb2hex(r, g, b) return string.format("#%02x%02x%02x", clamp(r), clamp(g), clamp(b)) end
local function mix(a, b, t) local r1, g1, b1 = hex2rgb(a); local r2, g2, b2 = hex2rgb(b); return rgb2hex(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t) end

-- Dominant wallpaper colors, most common first (empty in render / without a wallpaper).
local w = locky.sys.wallpaper_colors()
local primary = w[1] or "#86d0c4"
local secondary = w[2] or mix(primary, "#ffffff", 0.35)
local tertiary = w[3] or mix(primary, "#ffb085", 0.5)
-- M3 neutral surfaces, faintly tinted by the primary.
local bg = mix(primary, "#0c0e12", 0.90)
local surface = mix(primary, "#191c21", 0.84)
local surface2 = mix(primary, "#232730", 0.80)

return {
  name = "Material You",
  description = "Material 3, colored by your wallpaper: soft rounded cards, a friendly clock, and pill chips.",
  author = "Locky",
  palette = {
    bg = bg, fg = "#f2f4f5", muted = "#aab2bb", accent = primary, surface = surface, border = mix(surface, "#ffffff", 0.08),
    success = "#86d0c4", warning = tertiary, danger = "#ff8a80",
    primary = primary, secondary = secondary, tertiary = tertiary, surface2 = surface2,
  },
  font = { design = "rounded", weight = "medium" },
  background = locky.sys.wallpaper()
    and { wallpaper = true, blur = 48, dim = 0.34, tint = "bg", tint_amount = 0.42 }
    or { gradient = { mix(primary, "#0c0e12", 0.78), bg }, angle = 160, noise = 0.02 },
  card = { style = "solid", radius = 30, fill = "surface", border = "border" },
  auth = {
    style = "pill", anchor = "bottom", offset = { 0, -56 }, width = 300, avatar = false, name = false,
    placeholder = "password", focus = "primary", font = { size = 15 },
  },
  widgets = {
    { "greeting", anchor = "top", offset = { 0, 120 }, opts = { size = 18, weight = "medium", color = "primary" } },
    { "clock", anchor = "top", offset = { 0, 150 }, opts = { size = 158, weight = "medium", color = "fg", tracking = -3, shadow = 0, numeric = false } },
    { "date", anchor = "top", offset = { 0, 320 }, opts = { format = "skeleton:EEEEdMMMM", size = 19, weight = "medium", color = "secondary" } },
    -- A soft weather chip
    { "weather", anchor = "center", offset = { 0, 40 }, size = { 300, 120 }, card = true, align = "center", opts = { style = "line", size = 17 } },
    -- A bottom cluster of rounded stat cards
    { "system", anchor = "bottom-left", offset = { 120, -150 }, size = { 220, 120 }, card = true, opts = { style = "rings", color = "primary", color2 = "tertiary", size = 13, ring = 56 } },
    { "battery", anchor = "bottom", offset = { 0, -150 }, size = { 200, 120 }, card = true, align = "center", opts = { style = "ring", size = 16, color = "primary" } },
    { "calendar", anchor = "bottom-right", offset = { -120, -150 }, size = { 220, 120 }, card = true, opts = { today_color = "primary" } },
  },
}
