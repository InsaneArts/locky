-- Synthwave: a neon sunset over a perspective grid, and a chrome clock in the sky.
return {
  name = "Synthwave",
  description = "A neon sunset over a scrolling perspective grid, with a chrome clock.",
  author = "Locky",
  palette = {
    bg = "#0d0221", fg = "#f7f1ff", muted = "#f7f1ffa0", accent = "#ff2a6d", accent2 = "#05d9e8",
    surface = "#0d0221cc", border = "#05d9e8", danger = "#ff3864",
    -- The scene: the sky's middle, the sun's top, the mountains, and the grid's magenta.
    sky = "#2a0845", sun = "#ff9e00", mountain = "#3d0a52", magenta = "#ff2bd6",
    -- The clock's chrome, top to bottom.
    chrome1 = "#ffffff", chrome2 = "#8be9fd", chrome3 = "#ff79c6",
  },
  font = { family = "Futura", weight = "medium" },
  background = {
    shader = "synthwave", colors = { "bg", "sky", "accent", "sun", "mountain", "magenta", "accent2" },
    params = { 560, 175, 0.45 }, resolution = 0.75, fps = 30,
  },
  overlay = { shader = "synthwave-overlay", params = { 3, 0.18 }, resolution = 1, fps = 1 },
  card = { style = "solid", radius = 12, fill = "surface", border = "border" },
  auth = { style = "box", anchor = "bottom", offset = { 0, -64 }, width = 280, avatar = false, name = false, placeholder = "PASSWORD" },
  widgets = {
    { "synthwave.clock", anchor = "top", offset = { 0, 40 } },
    { "synthwave.date", anchor = "top", offset = { 0, 270 } },
    { "synthwave.battery", anchor = "top-right", offset = { -36, 30 } },
    { "synthwave.agents", anchor = "top-left", offset = { 36, 30 } },
  },
}
