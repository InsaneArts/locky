-- Station: a homage to the Swiss railway clock, Hans Hilfiker's 1944 design for the federal railways.
return {
  name = "Station",
  description = "A Swiss railway clock on a warm gray wall. The second hand sweeps, waits at 12, and the minute jumps.",
  palette = {
    bg = "#E9E7E2", fg = "#111111", muted = "#6B6965", accent = "#E2001A", surface = "#FAFAF8",
    border = "#11111133", danger = "#E2001A",
    -- The clock's case, the platform sign, and the wall's light (the background shader).
    case = "#2B2B2B", plate = "#111111", plate_text = "#FFFFFF", wall_light = "#F1EFEA", wall_shade = "#DCDAD4",
  },
  font = { family = "Helvetica Neue" },
  background = {
    shader = "station", colors = { "bg", "wall_light", "wall_shade" }, params = { 0.012, 0.56 },
    resolution = 0.5, fps = 1,
  },
  card = { style = "none" },
  auth = {
    style = "underline", anchor = "bottom", offset = { 0, -52 }, width = 260, avatar = false, name = false,
    placeholder = "", font = { family = "Helvetica Neue" },
  },
  widgets = {
    { "station.plate", anchor = "top-left", offset = { 40, 40 } },
    -- One clock in three layers at the same spot: the dial never redraws, the hour and minute hands redraw
    -- once a minute, and only the second hand redraws five times a second.
    { "station.clock", anchor = "center", offset = { 0, -54 }, opts = { part = "dial" } },
    { "station.clock", anchor = "center", offset = { 0, -54 }, opts = { part = "hands" } },
    { "station.clock", anchor = "center", offset = { 0, -54 }, opts = { part = "seconds" } },
    { "station.date", anchor = "center", offset = { 0, 258 } },
    { "station.departure", anchor = "center", offset = { 0, 296 } },
  },
}
