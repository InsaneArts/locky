-- Kanagawa: ukiyo-e. A stylized Great Wave scrolling under a calm ink sky, a thin fuji-white clock, and a
-- small red hanko seal. Built from rebelot/kanagawa.nvim's colors. The negative space up top is the point.
return {
  name = "Kanagawa",
  description = "A woodblock Great Wave under an ink sky: a thin clock, a red seal, and a lot of calm space.",
  author = "Locky",
  palette = {
    bg = "#1f1f28", fg = "#dcd7ba", muted = "#727169", surface = "#223249", accent = "#7e9cd8", border = "#54546d",
    success = "#98bb6c", warning = "#e6c384", danger = "#c34043",
    seal = "#c34043", foam = "#eef0e6", crystal = "#7fb4ca", indigo1 = "#172431", indigo2 = "#213d57", indigo3 = "#2c5070",
  },
  font = { design = "serif", weight = "regular" },
  background = { shader = "kanagawa", colors = { "bg", "indigo1", "indigo2", "indigo3", "foam" }, params = { 316, 0.85 }, resolution = 0.6, fps = 24 },
  card = { style = "solid", radius = 8, fill = "seal", border = "none" },
  auth = {
    style = "minimal", anchor = "bottom", offset = { 0, -72 }, width = 280, avatar = false, name = false,
    placeholder = "password", focus = "crystal", font = { size = 14 },
  },
  widgets = {
    -- In the deep water under the front wave: its crest rides 552 ± 25 points down, plus foam.
    { "clock", anchor = "left", offset = { 112, 214 },
      opts = { size = 132, weight = "thin", color = "foam", tracking = -2, shadow = 0, numeric = false } },
    { "date", anchor = "left", offset = { 118, 300 },
      opts = { format = "EEEE · d MMMM", size = 16, weight = "regular", color = "crystal", case = "upper", tracking = 3 } },
    { "moon", anchor = "top-right", offset = { -96, 96 }, size = { 124, 124 }, card = true, align = "center",
      opts = { style = "symbol", size = 60, color = "foam" } },
  },
}
