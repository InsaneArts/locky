-- The starting point of File › New Theme… in the Themes window: a dark color, the date over the clock in the top
-- third, and the password field. Its file name starts with "_", so no theme list shows it. Only core widgets.
return {
  name = "Untitled Theme",
  palette = { bg = "#15171c", fg = "#f5f5f7", muted = "#f5f5f799", accent = "#0a84ff" },
  background = { color = "bg" },
  card = { style = "glass", radius = 20 },
  auth = { style = "pill", anchor = "bottom", offset = { 0, -60 } },
  widgets = {
    { "date", anchor = "top", offset = { 0, 110 }, opts = { size = 22, weight = "semibold", shadow = 0 } },
    { "clock", anchor = "top", offset = { 0, 130 }, opts = { size = 140, shadow = 0, numeric = false } },
  },
}
