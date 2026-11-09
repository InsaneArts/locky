-- Rosé Pine: dusky "soho" minimalism. Heavy negative space, a refined serif clock slightly left of
-- centre, the date whispering beneath it, one small rose weather card, and an iris quote near the base.
-- Gold is spent once — on the auth focus — so a single warm point draws the eye to the password field.
return {
  name = "Rosé Pine",
  description = "Dusky soho minimalism: a serif clock, heavy negative space, one rose weather card, an iris quote.",
  author = "Locky",
  palette = {
    bg = "#191724", fg = "#e0def4", muted = "#6e6a86", subtle = "#908caa",
    surface = "#1f1d2ecc", surface2 = "#26233a", border = "#26233a",
    accent = "#c4a7e7", success = "#9ccfd8", warning = "#f6c177", danger = "#eb6f92",
    rose = "#ebbcba", gold = "#f6c177", pine = "#31748f", foam = "#9ccfd8", iris = "#c4a7e7", love = "#eb6f92",
  },
  font = { design = "serif", weight = "regular" },
  background = { gradient = { "#232136", "#191724" }, angle = 180, noise = 0.025 },
  card = { style = "solid", radius = 16, fill = "surface", border = "border" },
  auth = {
    style = "underline", anchor = "bottom", offset = { 0, -96 }, width = 280, avatar = false, name = false,
    placeholder = "password", focus = "gold", font = { size = 14 }, hint_align = "center",
  },
  widgets = {
    -- A serif clock, mid-weight, drawn a touch left of centre.
    { "clock", anchor = "center", offset = { -56, -96 },
      opts = { size = 150, weight = "regular", design = "serif", color = "fg", tracking = -1, shadow = 0, numeric = false } },
    -- The date, whispered in muted small caps directly beneath the clock.
    { "date", anchor = "center", offset = { -52, 6 },
      opts = { format = "EEEE d MMMM", size = 16, weight = "regular", color = "muted", case = "upper", tracking = 5 } },
    -- One small weather card, rose accented, tucked into the upper right of the empty field.
    { "weather", anchor = "top-right", offset = { -96, 92 }, card = true,
      opts = { style = "line", size = 15, color = "rose", multicolor = false, place = false } },
    -- An iris quote resting near the bottom, a single soft line, no author.
    { "quote", anchor = "bottom", offset = { 0, -188 },
      opts = { author = false, color = "iris", size = 17, italic = true, max_width = 640, text_align = "center",
        quotes = {
          { "Not all those who wander are lost." },
          { "Rest is not idleness." },
          { "Begin at once to live." },
          { "Simplify, simplify." },
          { "Stay a while in the quiet." },
        } } },
  },
}
