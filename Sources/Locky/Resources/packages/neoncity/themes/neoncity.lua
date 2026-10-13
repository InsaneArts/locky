-- Neon City: a city at 2 AM in the rain, seen from high up, with the time as a neon sign. After the lo-fi and
-- cyberpunk city wallpapers that fill Wallpaper Engine's charts.
return {
  name = "Neon City",
  description = "A rainy city at 2 AM: towers drifting past, neon signs, flying cars, and a neon clock.",
  palette = {
    bg = "#07051a", fg = "#fff4fb", muted = "#e6d9f2b3", accent = "#ff2a8a", surface = "#0b0820cc", border = "#ff2a8a66",
    -- The scene: the haze, warm windows, the two neons, and the towers.
    neon = "#ff4fa3", haze = "#3a1a5c", windows = "#ffb85c", pink = "#ff2a8a", cyan = "#22e4ff", towers = "#0a0818",
  },
  font = { family = "Avenir Next Condensed", weight = "demibold" },
  background = {
    -- params: how fast the city drifts, how much rain.
    shader = "neoncity", colors = { "bg", "haze", "windows", "pink", "cyan", "towers" }, params = { 1, 1 }, resolution = 0.5, fps = 30,
  },
  card = { style = "solid", radius = 6, fill = "surface", border = "border" },
  auth = {
    style = "box", anchor = "bottom", offset = { 0, -70 }, width = 280, avatar = false, name = false,
    placeholder = "PASSWORD", focus = "cyan", font = { family = "Avenir Next Condensed", size = 15 },
  },
  widgets = {
    { "clock", anchor = "top", offset = { 0, 58 },
      opts = { format = "HH:mm", size = 168, font = "Avenir Next Condensed", weight = "bold", tracking = 6, shadow = 30, glow = 30, color = "neon", numeric = false } },
    { "date", anchor = "top", offset = { 0, 262 },
      opts = { format = "EEEE d MMMM", size = 18, font = "Avenir Next Condensed", weight = "demibold", case = "upper", tracking = 8, shadow = 12, glow = 12, color = "cyan" } },
    { "weather", anchor = "top-left", offset = { 40, 36 }, opts = { style = "line", size = 15 } },
    { "battery", anchor = "top-right", offset = { -40, 36 }, card = false, opts = { style = "compact", size = 15 } },
    { "agents", anchor = "bottom-left", offset = { 40, -36 }, card = false, opts = { style = "summary", offline = false, size = 13 } },
  },
}
