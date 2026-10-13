-- Receipt: the lock screen as a thermal till receipt on a dark counter. Every line is a reading of the Mac, and the
-- total due is one password.
return {
  name = "Receipt",
  description = "A thermal till receipt: uptime, battery, CPU, weather, and the moon, itemized. Total due: one password.",
  palette = {
    bg = "#1c1a18", fg = "#f2efe8", muted = "#a39e94", accent = "#e8e2d4", surface = "#2a2724", border = "#4a4540",
    paper = "#fbf9f3", ink = "#2a2826",
  },
  font = { family = "Menlo" },
  background = { gradient = { "#26231f", "#151311" }, angle = 160, noise = 0.06 },
  card = { style = "none" },
  auth = {
    style = "box", anchor = "bottom", offset = { 0, -44 }, width = 300, avatar = false, name = false,
    placeholder = "SWIPE PASSWORD", focus = "accent", font = { family = "Menlo", size = 14 },
  },
  widgets = {
    { "receipt.slip", anchor = "center", offset = { 0, -50 } },
    { "clock", anchor = "top-left", offset = { 48, 40 },
      opts = { size = 40, font = "Menlo", weight = "regular", color = "muted", tracking = 0, shadow = 0, numeric = false } },
  },
}
