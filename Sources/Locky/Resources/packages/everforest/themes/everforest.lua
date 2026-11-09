-- Everforest: a warm, low-contrast forest. Sand-coloured text on a soft dim-green ground, a rounded clock,
-- a cosy greeting, an aqua weather card, and along the base the day/week/year filling up beside the sun's arc,
-- so the passing of the day is felt rather than read.
return {
  name = "Everforest",
  description = "A cosy low-contrast forest: sand text, a rounded clock, a greeting, weather, and the day quietly passing.",
  author = "Locky",
  palette = {
    bg = "#2d353b", fg = "#d3c6aa", muted = "#859289", subtle = "#9da9a0",
    surface = "#343f44", surface2 = "#3d484d", border = "#4a555b",
    accent = "#a7c080", success = "#a7c080", warning = "#dbbc7f", danger = "#e67e80",
    green = "#a7c080", aqua = "#83c092", yellow = "#dbbc7f", orange = "#e69875", blue = "#7fbbb3", purple = "#d699b6",
  },
  font = { design = "rounded", weight = "regular" },
  background = { gradient = { "#232a2e", "#333c43" }, angle = 180, noise = 0.03 },
  card = { style = "solid", radius = 20, fill = "surface", border = "border" },
  auth = {
    style = "pill", anchor = "bottom", offset = { 0, -100 }, width = 300, avatar = false, name = false,
    placeholder = "password", focus = "green", font = { size = 14 },
  },
  widgets = {
    -- A soft rounded clock, warm sand, centred and high.
    { "clock", anchor = "center", offset = { 0, -118 },
      opts = { size = 152, weight = "medium", color = "fg", tracking = -2, shadow = 0, numeric = false } },
    -- A cosy greeting, warm orange, just under the clock.
    { "greeting", anchor = "center", offset = { 0, -6 }, opts = { size = 21, weight = "medium", color = "orange" } },
    -- The date beneath the greeting, muted.
    { "date", anchor = "center", offset = { 0, 28 }, opts = { format = "EEEE d MMMM", size = 16, weight = "regular", color = "muted" } },
    -- A soft aqua weather card in the upper right.
    { "weather", anchor = "top-right", offset = { -80, 80 }, card = true, opts = { style = "detail", color = "aqua" } },
    -- The day, week and year filling up, bottom left, so time is felt passing.
    { "progress", anchor = "bottom-left", offset = { 80, -70 }, card = true,
      opts = { style = "bars", show = { "day", "week", "year" }, width = 240, size = 13, color = "green" } },
    -- The sun's arc across the day, bottom right, warm yellow.
    { "sun", anchor = "bottom-right", offset = { -80, -70 }, card = true,
      opts = { width = 220, color = "yellow", path = "muted", place = false } },
  },
}
