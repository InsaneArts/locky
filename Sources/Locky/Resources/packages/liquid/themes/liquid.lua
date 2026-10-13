-- Liquid: paint folding into paint like silk, under a lock screen laid out like a phone's: the date over a big clock,
-- and a row of glass widgets. After the fluid wallpapers that sit near the top of Wallpaper Engine's charts.
return {
  name = "Liquid",
  description = "Color folding into color like silk, a big clock, and a row of glass widgets.",
  palette = {
    bg = "#140a2e", fg = "#ffffff", muted = "#ffffffb3", accent = "#00f5d4", surface = "#ffffff1f", border = "#ffffff33",
    -- The paints, deepest to brightest, and the sheen on the folds.
    deep = "#12052e", violet = "#6a2bd9", blue = "#00b8c4", pink = "#ff3cac", sheen = "#ffe8f6",
  },
  font = { design = "rounded", weight = "semibold" },
  background = {
    -- params: how fast it flows, how large the folds are, how much sheen.
    shader = "liquid", colors = { "deep", "violet", "blue", "pink", "sheen" }, params = { 1, 1, 1 }, resolution = 0.5, fps = 20,
  },
  card = { style = "glass", radius = 26 },
  auth = { style = "pill", anchor = "bottom", offset = { 0, -60 }, width = 260, avatar = true, name = true },
  widgets = {
    { "date", anchor = "top", offset = { 0, 70 },
      opts = { format = "EEEE d MMMM", size = 24, weight = "semibold", color = "muted", shadow = 0 } },
    { "clock", anchor = "top", offset = { 0, 92 },
      opts = { format = "HH:mm", size = 190, weight = "bold", design = "rounded", tracking = -4, shadow = 10, color = "fg", numeric = false } },
    { "weather", anchor = "top", offset = { -244, 350 }, card = true, size = { 224, 196 }, opts = { style = "hero", size = 15 } },
    { "progress", anchor = "top", offset = { 0, 350 }, card = true, size = { 224, 196 }, opts = { style = "rings", size = 11, show = { "day", "week", "year" } } },
    { "calendar", anchor = "top", offset = { 244, 350 }, card = true, size = { 224, 196 }, opts = { size = 9 } },
  },
}
