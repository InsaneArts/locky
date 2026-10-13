-- E-Ink: the lock screen as an e-paper dashboard, after TRMNL and the Kindle dashboards power users build. Black ink on
-- warm white, every panel boxed: the time, the forecast, the month, a quote, the year's progress, and the moon.
return {
  name = "E-Ink",
  description = "An e-paper dashboard: boxed panels of time, forecast, calendar, quote, progress, and the moon.",
  palette = {
    bg = "#f2f1ec", fg = "#111111", muted = "#555555", accent = "#111111", surface = "#dddcd6", border = "#111111",
    success = "#111111", warning = "#111111", danger = "#111111", paper = "#f2f1ec", ink = "#111111",
  },
  font = { family = "Helvetica Neue" },
  background = { gradient = { "#f4f3ee", "#efeee8" }, angle = 180, noise = 0.05 },
  card = { style = "outline", radius = 6, border = "border" },
  auth = {
    style = "box", anchor = "bottom-right", offset = { -60, -74 }, width = 340, avatar = false, name = false, hint = false,
    placeholder = "password", focus = "fg", font = { family = "Helvetica Neue", size = 14 },
  },
  widgets = {
    { "eink.header", anchor = "top", offset = { 0, 24 } },
    -- A grid: 40-point margins, 20-point gutters, three rows.
    { "eink.time", anchor = "top-left", offset = { 40, 92 }, size = { 640, 300 }, align = "leading", card = true },
    { "weather", anchor = "top-left", offset = { 700, 92 }, size = { 700, 300 }, card = true,
      opts = { style = "forecast", size = 30, multicolor = false, color = "fg" } },
    { "calendar", anchor = "top-left", offset = { 40, 412 }, size = { 400, 300 }, card = true, opts = { size = 15, title = true, today_color = "fg" } },
    { "quote", anchor = "top-left", offset = { 460, 412 }, size = { 520, 300 }, align = "leading", card = true,
      opts = { size = 22, max_width = 470, text_align = "leading", color = "fg" } },
    { "progress", anchor = "top-left", offset = { 1000, 412 }, size = { 400, 300 }, card = true,
      opts = { style = "bars", width = 340, size = 14, color = "fg", track = "surface" } },
    { "moon", anchor = "top-left", offset = { 40, 732 }, size = { 400, 128 }, card = true, opts = { style = "row", size = 72, color = "fg" } },
    { "battery", anchor = "top-left", offset = { 460, 732 }, size = { 520, 128 }, card = true, opts = { style = "row", size = 18, color = "fg" } },
  },
}
