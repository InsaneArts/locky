-- Classic: a 1-bit desktop from the mid-1980s. A gray dither pattern, a menu bar, an About window, the alarm clock desk
-- accessory, icons down the right, and a dialog that asks for your password.
return {
  name = "Classic",
  description = "A 1-bit desktop from the 1980s: menu bar, About window, the alarm clock, and a password dialog.",
  palette = {
    bg = "#ffffff", fg = "#000000", muted = "#000000", accent = "#000000", surface = "#ffffff", border = "#000000",
    success = "#000000", warning = "#000000", danger = "#000000", paper = "#ffffff", ink = "#000000",
  },
  font = { family = "Geneva" },
  background = { shader = "classic", colors = { "paper", "ink" }, params = { 2 }, resolution = 1, fps = 1 },
  card = { style = "none" },
  auth = {
    style = "box", anchor = "center", offset = { 0, 90 }, width = 300, avatar = false, name = false, hint = false,
    placeholder = "", focus = "ink", font = { family = "Geneva", size = 14 },
  },
  widgets = {
    { "classic.menubar", anchor = "top" },
    { "classic.about", anchor = "top-left", offset = { 60, 80 } },
    { "classic.clock", anchor = "top-left", offset = { 520, 120 } },
    { "classic.icons", anchor = "top-right", offset = { -40, 70 } },
    { "classic.dialog", anchor = "center", offset = { 0, 62 }, size = { 460, 170 } },
  },
}
