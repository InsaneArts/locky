-- Event Horizon: a black hole seen almost edge-on, its accretion disk turning and its light bent around the shadow,
-- after Interstellar's Gargantua and the black-hole wallpapers that top Wallpaper Engine's charts.
return {
  name = "Event Horizon",
  description = "A black hole with a turning accretion disk and light bent around its shadow.",
  palette = {
    bg = "#010103", fg = "#f6efe2", muted = "#f6efe28c", accent = "#ffb347", surface = "#ffffff12", border = "#ffffff1f",
    -- The disk, from its hot inner edge out.
    hot = "#fff3d6", warm = "#ffa53a", cool = "#b8360c",
  },
  font = { family = "Avenir Next", weight = "ultralight" },
  background = {
    -- params: the hole's center (points from the top), the shadow's radius, the disk's speed.
    shader = "eventhorizon", colors = { "bg", "hot", "warm", "cool" }, params = { 530, 104, 1 }, resolution = 0.5, fps = 30,
  },
  card = { style = "glass", radius = 18 },
  auth = {
    style = "underline", anchor = "bottom", offset = { 0, -64 }, width = 240, avatar = false, name = false,
    placeholder = "password", focus = "accent", font = { family = "Avenir Next", size = 14 },
  },
  widgets = {
    { "clock", anchor = "top", offset = { 0, 64 },
      opts = { format = "HH:mm", size = 132, font = "Avenir Next", weight = "ultralight", tracking = 14, shadow = 0, color = "fg", numeric = false } },
    { "date", anchor = "top", offset = { 0, 238 },
      opts = { format = "EEEE  d  MMMM", size = 13, font = "Avenir Next", weight = "medium", case = "upper", tracking = 7, color = "muted", shadow = 0 } },
    { "weather", anchor = "bottom-left", offset = { 44, -40 }, opts = { style = "line", size = 13 } },
    { "battery", anchor = "bottom-right", offset = { -44, -40 }, card = false, opts = { style = "compact", size = 13 } },
  },
}
