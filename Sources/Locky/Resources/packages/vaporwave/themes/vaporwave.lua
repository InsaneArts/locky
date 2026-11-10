-- Vaporwave: a faded pastel dream. A banded sun on the horizon, a cyan floor grid, VHS scanlines, a chrome
-- serif clock, and mixed English/Japanese labels. Softer than the shipped Synthwave neon.
return {
  name = "Vaporwave",
  description = "A pastel CRT dream: a banded sun, a cyan grid, VHS scanlines, and a chrome serif clock.",
  author = "Locky",
  palette = {
    bg = "#2a1a4a", fg = "#fdeff9", muted = "#c3a9e0", accent = "#ffc3ee", surface = "#3a2a5ecc", border = "#6b4fa0",
    success = "#5fe9d8", warning = "#eda381", danger = "#ed4bbc",
    cyan = "#5fe9d8", rose = "#ed4bbc", peach = "#eda381", sunpink = "#ffc3ee",
    skytop = "#2a1a4a", skylow = "#c56ec5", floor = "#201845", gridc = "#5fe9d8",
  },
  font = { design = "serif", weight = "medium" },
  background = { shader = "vaporwave", colors = { "skytop", "skylow", "floor", "sunpink", "gridc" }, params = { 582, 0.2 }, resolution = 0.6, fps = 24 },
  card = { style = "glass", radius = 14 },
  auth = {
    style = "minimal", anchor = "bottom", offset = { 0, -58 }, width = 280, avatar = false, name = false,
    placeholder = "password", focus = "cyan", font = { size = 14 },
  },
  widgets = {
    { "clock", anchor = "center", offset = { 0, -44 },
      opts = { size = 150, weight = "semibold", color = "fg", tracking = 2, shadow = 0, numeric = false, skew = 8, glow = 16 } },
    -- Both lines sit on the bright sun, so they take the darkest violet.
    { "text", anchor = "center", offset = { 0, 58 }, opts = { text = "現在  ・  N O W", size = 16, color = "skytop", tracking = 4, font = "Menlo" } },
    { "date", anchor = "center", offset = { 0, 92 }, opts = { format = "EEEE d MMMM", size = 15, color = "skytop", case = "upper", tracking = 3 } },
    { "weather", anchor = "top-right", offset = { -60, 56 }, size = { 260, 92 }, card = true, align = "center", opts = { style = "line", size = 15, place = false } },
    { "worldclock", anchor = "top-left", offset = { 60, 56 }, size = { 230, 92 }, card = true, align = "leading",
      opts = { style = "rows", size = 13, zones = { { "Tokyo", "Asia/Tokyo" }, { "LA", "America/Los_Angeles" } } } },
    { "quote", anchor = "bottom", offset = { 0, -128 }, opts = { size = 15, max_width = 620, text_align = "center", color = "fg" } },
  },
}
