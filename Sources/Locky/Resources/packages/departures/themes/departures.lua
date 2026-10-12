-- Departures: a flip clock over a split-flap board of herdr agents, on a dark terminal wall.
return {
  name = "Departures",
  description = "A flip clock and a split-flap departures board of your herdr agents.",
  palette = {
    bg = "#0B0B0B", fg = "#F2F2F2", muted = "#9A9A9A", accent = "#FFC20E", surface = "#161616", border = "#2A2A2A",
    warning = "#FFB000", success = "#4CD964", danger = "#FF453A",
    -- The theme's own roles: the flip clock's digits, the board's flaps, and idle agents.
    digit = "#D6D6D6", flap = "#1C1C1C", idle = "#5E5E5E",
  },
  font = { design = "default" },
  background = { color = "bg" },
  card = { style = "none" },
  auth = {
    style = "box", anchor = "bottom", offset = { 0, -66 }, width = 280, avatar = false, name = false,
    placeholder = "Password", font = { family = "Helvetica Neue", weight = "medium" },
  },
  widgets = {
    { "departures.clock", anchor = "top", offset = { 0, 90 } },
    { "departures.board", anchor = "top", offset = { 0, 492 } },
    { "departures.footer", anchor = "bottom", offset = { 0, -22 } },
  },
}
