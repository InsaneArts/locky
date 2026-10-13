-- Broadsheet: the lock screen as a newspaper's front page. The masthead and dateline, a quote set as the lead
-- headline, the weather, the time, the Mac's numbers as a market table, and the almanac at the foot.
local top = 262
return {
  name = "Broadsheet",
  description = "A newspaper's front page: masthead, a headline quote, weather, the time, and the Mac's markets.",
  palette = {
    bg = "#f3eee3", fg = "#16130f", muted = "#5d564b", accent = "#9b2318", surface = "#e9e2d3", border = "#16130f40",
    success = "#2f6b3a", warning = "#9b6a18", danger = "#9b2318",
  },
  font = { family = "Baskerville" },
  background = { gradient = { "#f5f0e6", "#ebe4d6" }, angle = 180, noise = 0.07 },
  card = { style = "none" },
  auth = {
    style = "underline", anchor = "bottom", offset = { 0, -70 }, width = 300, avatar = false, name = false,
    placeholder = "subscriber password", focus = "fg", font = { family = "Baskerville", size = 15 },
  },
  widgets = {
    { "broadsheet.masthead", anchor = "top", offset = { 0, 28 } },
    { "quote", anchor = "top", offset = { 0, 196 },
      opts = { font = "Bodoni 72", size = 38, max_width = 1200, quote_marks = false, color = "fg", every = 60 } },

    { "broadsheet.section", anchor = "top-left", offset = { 60, top + 90 }, opts = { text = "WEATHER" } },
    { "weather", anchor = "top-left", offset = { 60, top + 130 }, opts = { style = "detail", size = 15, multicolor = false, color = "fg" } },
    { "broadsheet.rule", anchor = "top-left", offset = { 450, top + 90 }, size = { 1, 330 } },

    { "broadsheet.section", anchor = "top", offset = { 0, top + 90 }, opts = { text = "THE HOUR" } },
    { "clock", anchor = "top", offset = { 0, top + 120 },
      opts = { size = 110, font = "Bodoni 72", weight = "bold", tracking = 0, shadow = 0, numeric = false } },
    { "fuzzy", anchor = "top", offset = { 0, top + 270 }, opts = { size = 22, font = "Baskerville", weight = "regular", case = "title", prefix = "It Is ", color = "muted" } },
    { "date", anchor = "top", offset = { 0, top + 312 }, opts = { format = "EEEE d MMMM", size = 15, font = "Baskerville", shadow = 0, color = "fg" } },
    { "broadsheet.rule", anchor = "top-right", offset = { -450, top + 90 }, size = { 1, 330 } },

    { "broadsheet.section", anchor = "top-right", offset = { -60, top + 90 }, opts = { text = "MARKETS" } },
    { "broadsheet.markets", anchor = "top-right", offset = { -60, top + 130 } },

    { "broadsheet.almanac", anchor = "bottom", offset = { 0, -150 } },
  },
}
