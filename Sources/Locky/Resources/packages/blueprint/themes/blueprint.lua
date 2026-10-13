-- Blueprint: the lock screen as an engineering drawing in Prussian blue. A clock drawn with center lines and
-- dimensions, the title block in the corner, general notes, and the sky as a detail.
return {
  name = "Blueprint",
  description = "An engineering drawing: a dimensioned clock, a title block, general notes, and the sun and moon.",
  palette = {
    bg = "#123d78", fg = "#e9f1ff", muted = "#a9c2ea", accent = "#ffd166", surface = "#123d78", border = "#e9f1ffaa",
    paper = "#123d78", lines = "#dce8ff",
  },
  font = { family = "DIN Alternate" },
  background = { shader = "blueprint", colors = { "paper", "lines" }, params = { 40 }, resolution = 1, fps = 0 },
  card = { style = "outline", radius = 0, border = "border" },
  auth = {
    style = "box", anchor = "bottom", offset = { 0, -96 }, width = 280, avatar = false, name = false,
    placeholder = "PASSWORD", focus = "accent", font = { family = "DIN Alternate", size = 14 },
  },
  widgets = {
    { "blueprint.clock", anchor = "center", offset = { -40, -40 } },
    { "blueprint.titleblock", anchor = "bottom-right", offset = { -64, -64 } },
    { "blueprint.notes", anchor = "top-left", offset = { 76, 72 } },
    { "sun", anchor = "top-right", offset = { -76, 72 }, card = true, opts = { width = 260 } },
    { "moon", anchor = "right", offset = { -76, -60 }, card = true, opts = { style = "row" } },
    { "weather", anchor = "bottom-left", offset = { 76, -72 }, opts = { style = "line", size = 16 } },
  },
}
