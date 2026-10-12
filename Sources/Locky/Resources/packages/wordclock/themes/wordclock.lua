-- Word Clock: the time in words on a matte black letter grid, after the QLOCKTWO. English only.
return {
  name = "Word Clock",
  description = "The time spelled out on a letter grid. English only.",
  palette = { bg = "#0D0D0D", fg = "#FFFFFF", muted = "#FFFFFF59", accent = "#FFFFFF", danger = "#FF3B30" },
  font = { family = "Avenir Next", weight = "semibold" },
  background = { color = "bg" },
  card = { style = "none" },
  auth = {
    style = "minimal", anchor = "bottom", offset = { 0, -44 }, avatar = false, name = false, placeholder = "",
    font = { family = "Avenir Next", weight = "medium" },
  },
  widgets = {
    { "wordclock.grid", anchor = "center", offset = { 0, -36 } },
    { "wordclock.date", anchor = "center", offset = { 0, 296 } },
  },
}
