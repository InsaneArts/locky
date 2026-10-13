-- Matrix: digital rain behind a glowing green clock, the messages that woke Neo typed in the corner, and the
-- processes running on the Mac.
return {
  name = "Matrix",
  description = "Digital rain, a glowing green clock, \"Wake up, Neo…\" typed in the corner, and the top processes.",
  palette = {
    bg = "#000a03", fg = "#7dff9b", muted = "#2f9e4f", accent = "#00ff41", surface = "#000f06dd", border = "#00ff4144",
    rain = "#00d636", head = "#d8ffe0",
  },
  font = { design = "monospaced" },
  background = { shader = "matrix", colors = { "bg", "rain", "head" }, params = { 1, 0.75 }, resolution = 0.5, fps = 15 },
  card = { style = "solid", radius = 4, fill = "surface", border = "border" },
  auth = {
    style = "underline", anchor = "center", offset = { 0, 150 }, width = 300, avatar = false, name = false,
    placeholder = "enter the password", focus = "accent", glow = 4, font = { design = "monospaced", size = 15 },
  },
  widgets = {
    { "matrix.whisper", anchor = "top-left", offset = { 56, 48 } },
    { "clock", anchor = "center", offset = { 0, -50 },
      opts = { size = 150, weight = "light", design = "monospaced", color = "accent", tracking = 0, shadow = 0, glow = 18, numeric = false } },
    { "date", anchor = "center", offset = { 0, 60 },
      opts = { format = "yyyy.MM.dd  EEE", case = "upper", size = 18, weight = "regular", design = "monospaced", color = "muted", shadow = 0 } },
    { "top", anchor = "bottom-left", offset = { 40, -40 }, card = true, opts = { rows = 5, size = 12, color = "fg", every = 5 } },
    { "system", anchor = "bottom-right", offset = { -40, -40 }, card = true, opts = { style = "chart" } },
    { "network", anchor = "top-right", offset = { -48, 48 }, opts = { style = "line", size = 13, color = "muted" } },
  },
}
