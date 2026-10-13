-- Observatory: a clear night from a hill with a telescope dome. The stars turn slowly around the pole, and the
-- widgets read like an astronomer's notebook: the moon, the sun's path, and the weather for seeing.
return {
  name = "Observatory",
  description = "A turning night sky over an observatory dome, with tonight's moon and the sun's path.",
  palette = {
    bg = "#04060f", fg = "#e8ecff", muted = "#8f9bc4", accent = "#ffd27a", surface = "#ffffff12", border = "#ffffff24",
    sky_top = "#03050d", sky_low = "#101b38", glow = "#2b3f72", milky = "#c4cdff", ground = "#010205", window = "#ffb45e",
  },
  font = { family = "Avenir Next", weight = "regular" },
  background = { shader = "observatory", colors = { "sky_top", "sky_low", "glow", "milky", "ground", "window" },
                 params = { 1, 1 }, resolution = 0.5, fps = 24 },
  card = { style = "none" },
  auth = {
    style = "underline", anchor = "bottom", offset = { 0, -150 }, width = 240, avatar = false, name = false,
    placeholder = "", font = { family = "Avenir Next", size = 14 },
  },
  widgets = {
    { "clock", anchor = "top-left", offset = { 64, 52 },
      opts = { size = 120, weight = "ultralight", font = "Avenir Next", tracking = 2, shadow = 0, numeric = false } },
    { "date", anchor = "top-left", offset = { 72, 200 },
      opts = { format = "EEEE d MMMM", size = 15, weight = "medium", color = "muted", case = "upper", tracking = 4, shadow = 0 } },
    { "moon", anchor = "top-right", offset = { -80, 70 }, opts = { size = 110, color = "#f3f0e6" } },
    { "sun", anchor = "left", offset = { 72, 120 }, opts = { width = 260, color = "accent", path = "accent" } },
    { "weather", anchor = "top-left", offset = { 72, 236 }, opts = { style = "line", size = 14, multicolor = false, color = "fg" } },
  },
}
