-- Sakura: a spring night under a full moon. A cherry branch in bloom, petals drifting down, a mountain and a pagoda in
-- the mist, and the month's old Japanese name hanging like a scroll. After the falling-sakura wallpapers at the top
-- of Wallpaper Engine's charts.
return {
  name = "Sakura",
  description = "A cherry branch in bloom under the moon, falling petals, and the month's old Japanese name.",
  palette = {
    bg = "#140f2b", fg = "#fff1f4", muted = "#f3d7e0b3", accent = "#ffb7c5", surface = "#ffffff14", border = "#ffffff26",
    -- The scene: the sky low down, the blossoms and their light centers, the moon, and the silhouettes.
    dusk = "#4a2c5e", blossom = "#f48fb1", petal = "#ffe4ec", moon = "#fff4e0", ink = "#0b0816",
  },
  font = { family = "Hiragino Mincho ProN" },
  background = {
    -- params: how many petals, the wind.
    shader = "sakura", colors = { "bg", "dusk", "blossom", "petal", "moon", "ink" }, params = { 1, 1 }, resolution = 0.5, fps = 24,
  },
  card = { style = "glass", radius = 16 },
  auth = {
    style = "underline", anchor = "bottom", offset = { 0, -74 }, width = 240, avatar = false, name = false,
    placeholder = "password", focus = "accent", font = { family = "Hiragino Mincho ProN", size = 14 },
  },
  widgets = {
    { "clock", anchor = "left", offset = { 130, 10 },
      opts = { format = "HH:mm", size = 120, font = "Hiragino Mincho ProN", weight = "regular", tracking = 4, shadow = 16, color = "fg", numeric = false } },
    { "date", anchor = "left", offset = { 136, 100 },
      opts = { format = "EEEE, d MMMM", size = 19, font = "Hiragino Mincho ProN", color = "muted", shadow = 8 } },
    { "sakura.month", anchor = "top-right", offset = { -80, 360 } },
    { "weather", anchor = "bottom-left", offset = { 44, -40 }, opts = { style = "line", size = 13 } },
    { "battery", anchor = "bottom-right", offset = { -44, -40 }, card = false, opts = { style = "compact", size = 13 } },
  },
}
