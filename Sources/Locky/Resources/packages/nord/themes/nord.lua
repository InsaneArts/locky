-- Nord: arctic, frost, Scandinavian minimal. A cold flat gradient (polar night to a faint lit blue),
-- a thin snow-white clock aligned hard left, and a single frost accent. No northern lights — that is Aurora's.
return {
  name = "Nord",
  description = "Arctic frost: a cold flat gradient, a thin snow-white clock, and Scandinavian restraint.",
  author = "Locky",
  palette = {
    bg = "#2e3440", fg = "#eceff4", muted = "#616e88", accent = "#88c0d0", surface = "#3b4252cc", border = "#434c5e",
    success = "#a3be8c", warning = "#ebcb8b", danger = "#bf616a",
    frost = "#88c0d0", frost2 = "#81a1c1", teal = "#8fbcbb", snow = "#d8dee9", night3 = "#4c566a",
  },
  font = { weight = "regular" },
  background = { gradient = { "#2e3440", "#3b4252" }, angle = 135, noise = 0.02 },
  card = { style = "none" },
  auth = {
    style = "underline", anchor = "bottom", offset = { 0, -96 }, width = 280, avatar = false, name = false,
    placeholder = "password", focus = "frost", font = { size = 14 },
  },
  widgets = {
    { "clock", anchor = "left", offset = { 100, -92 },
      opts = { size = 148, weight = "thin", color = "snow", tracking = -2, shadow = 0, numeric = false } },
    { "date", anchor = "left", offset = { 104, 22 },
      opts = { format = "EEEE d MMMM", size = 16, weight = "regular", color = "frost2", case = "upper", tracking = 4 } },
    { "weather", anchor = "left", offset = { 104, 54 }, opts = { style = "line", size = 14, color = "night3" } },
    { "system", anchor = "bottom-left", offset = { 100, -40 },
      opts = { style = "bars", width = 220, color = "frost", color2 = "frost2", size = 12 } },
    { "battery", anchor = "top-right", offset = { -40, 36 }, opts = { style = "compact", size = 13, color = "snow" } },
    { "sun", anchor = "bottom-right", offset = { -40, -40 }, opts = { width = 180, color = "frost2" } },
  },
}
