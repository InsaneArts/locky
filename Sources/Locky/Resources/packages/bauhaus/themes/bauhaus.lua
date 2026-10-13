-- Bauhaus: the lock screen as a poster from the 1923 Weimar exhibition: primary colors in circle, square, and
-- triangle on cream paper, and the time set in Futura. A notch in the red circle sweeps once a minute.
return {
  name = "Bauhaus",
  description = "A Bauhaus poster: red circle, blue half disc, yellow triangle, and the time in Futura.",
  palette = {
    bg = "#efe6d2", fg = "#141414", muted = "#55524b", accent = "#d7263d", surface = "#e4d9c1", border = "#14141440",
    red = "#d7263d", blue = "#1b4f9c", yellow = "#f2b705", black = "#141414",
  },
  font = { family = "Futura", weight = "medium" },
  background = { shader = "bauhaus", colors = { "bg", "red", "blue", "yellow", "black" }, resolution = 1, fps = 2 },
  card = { style = "none" },
  auth = {
    style = "underline", anchor = "bottom-right", offset = { -110, -90 }, width = 300, avatar = false, name = false,
    placeholder = "", focus = "red", font = { family = "Futura", size = 15 },
  },
  widgets = {
    { "clock", anchor = "right", offset = { -110, -180 },
      opts = { format = "HH:mm", size = 190, font = "Futura", weight = "bold", tracking = -6, shadow = 0, numeric = false, color = "fg" } },
    { "date", anchor = "right", offset = { -118, -40 },
      opts = { format = "EEEE", size = 40, font = "Futura", weight = "bold", case = "upper", tracking = 6, color = "red", shadow = 0 } },
    { "date", anchor = "right", offset = { -118, 14 },
      opts = { format = "dd.MM.yyyy", size = 22, font = "Futura", weight = "medium", tracking = 4, color = "fg", shadow = 0 } },
    { "weather", anchor = "right", offset = { -118, 70 }, opts = { style = "line", size = 17, multicolor = false, color = "blue" } },
    { "bauhaus.title", anchor = "top-right", offset = { -40, 40 }, opts = { color = "blue" } },
  },
}
