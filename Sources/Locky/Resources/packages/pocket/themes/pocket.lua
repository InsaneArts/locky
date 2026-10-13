-- Pocket: a handheld game's four-shade green screen. The battery is your lives, the uptime your score, the day of the
-- year the level, and the game is Conway's Life.
return {
  name = "Pocket",
  description = "A four-shade handheld LCD: battery as hearts, a pixel clock, and the Game of Life.",
  palette = {
    bg = "#9bbc0f", fg = "#0f380f", muted = "#306230", accent = "#306230", surface = "#8bac0f", border = "#306230",
    success = "#0f380f", warning = "#306230", danger = "#0f380f", grid = "#8bac0f", rim = "#0f380f",
  },
  font = { design = "monospaced", weight = "bold" },
  background = { shader = "pocket", colors = { "bg", "grid", "rim" }, resolution = 1, fps = 1 },
  card = { style = "solid", radius = 6, fill = "surface", border = "fg" },
  auth = {
    style = "box", anchor = "bottom", offset = { 0, -70 }, width = 280, avatar = false, name = false,
    placeholder = "PRESS START", focus = "fg", font = { design = "monospaced", size = 16 },
  },
  widgets = {
    { "pocket.hud", anchor = "top", offset = { 0, 44 } },
    { "pocket.clock", anchor = "top", offset = { 0, 120 }, opts = { pixel = 13 } },
    { "life", anchor = "center", offset = { 0, 70 }, card = true,
      opts = { columns = 44, rows = 16, cell = "■", size = 13, color = "fg", every = 1 } },
    { "date", anchor = "top", offset = { 0, 262 },
      opts = { format = "EEE d MMM", size = 18, design = "monospaced", weight = "bold", case = "upper", tracking = 3, color = "muted", shadow = 0 } },
  },
}
