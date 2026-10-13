-- Deep Blue: under the sea, looking up through shifting rays of light, while a whale glides past far off. After
-- "Wake up" and the underwater wallpapers on Wallpaper Engine's top charts.
return {
  name = "Deep Blue",
  description = "Underwater: rays of light, caustics, drifting plankton, and a whale gliding past.",
  palette = {
    bg = "#001321", fg = "#eaf8ff", muted = "#cdeaffa6", accent = "#7fd6ff", surface = "#ffffff12", border = "#ffffff24",
    -- The scene: the water higher up, the light at the surface, and the whale.
    water = "#03507e", light = "#a9e4ff", whale = "#001827",
  },
  font = { family = "Avenir Next", weight = "ultralight" },
  background = {
    -- params: seconds between the whale's passes, how bright the rays are.
    shader = "deepblue", colors = { "bg", "water", "light", "whale" }, params = { 150, 1 }, resolution = 0.5, fps = 24,
  },
  card = { style = "glass", radius = 20 },
  auth = {
    style = "pill", anchor = "bottom", offset = { 0, -80 }, width = 250, avatar = false, name = false,
    placeholder = "password", focus = "accent", font = { family = "Avenir Next", size = 14 },
  },
  widgets = {
    { "clock", anchor = "top", offset = { 0, 110 },
      opts = { format = "HH:mm", size = 150, font = "Avenir Next", weight = "ultralight", tracking = 2, shadow = 20, color = "fg", numeric = false } },
    { "date", anchor = "top", offset = { 0, 300 },
      opts = { format = "EEEE  ·  d MMMM", size = 15, font = "Avenir Next", weight = "medium", case = "upper", tracking = 5, color = "muted", shadow = 6 } },
    { "weather", anchor = "bottom-left", offset = { 44, -40 }, opts = { style = "line", size = 13 } },
    { "battery", anchor = "bottom-right", offset = { -44, -40 }, card = false, opts = { style = "compact", size = 13 } },
  },
}
