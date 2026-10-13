-- Snowfall: a winter night in the woods. Snow falls at every depth, snowy pines fade into the blue, and a cabin's
-- windows glow warm while smoke curls from its chimney. After the snowy forest wallpapers on Wallpaper Engine's charts.
return {
  name = "Snowfall",
  description = "Snow falling on a pine forest at night, and a cabin with warm windows and chimney smoke.",
  palette = {
    bg = "#0a1426", fg = "#f4f8ff", muted = "#dbe7f7b3", accent = "#ffc27a", surface = "#ffffff14", border = "#ffffff26",
    -- The scene: the sky low down, the snow, the pines, and the cabin's light.
    mist = "#3a5878", snow = "#e8f1ff", pine = "#0b1a24", window = "#ffb45e",
  },
  font = { family = "Avenir Next", weight = "light" },
  background = {
    -- params: how much snow, the wind.
    shader = "snowfall", colors = { "bg", "mist", "snow", "pine", "window" }, params = { 1, 1 }, resolution = 0.5, fps = 24,
  },
  card = { style = "glass", radius = 18 },
  auth = {
    style = "pill", anchor = "bottom", offset = { 0, -56 }, width = 250, avatar = false, name = false,
    placeholder = "password", focus = "accent", font = { family = "Avenir Next", size = 14 },
  },
  widgets = {
    { "clock", anchor = "top", offset = { 0, 76 },
      opts = { format = "HH:mm", size = 140, font = "Avenir Next", weight = "light", tracking = 2, shadow = 18, color = "fg", numeric = false } },
    { "date", anchor = "top", offset = { 0, 252 },
      opts = { format = "EEEE, d MMMM", size = 19, font = "Avenir Next", weight = "medium", color = "muted", shadow = 8 } },
    { "countdown", anchor = "top", offset = { 0, 290 }, opts = { style = "line", size = 14, color = "accent" } },
    { "weather", anchor = "top-left", offset = { 44, 40 }, opts = { style = "line", size = 13 } },
    { "battery", anchor = "top-right", offset = { -44, 40 }, card = false, opts = { style = "compact", size = 13 } },
  },
}
