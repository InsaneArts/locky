-- Neo-brutalism's building block: a bright filled panel with a thick near-black border, a hard offset drop
-- shadow faked by a solid black rect behind it, and a small mono label in its corner.
--   opts.w, opts.h   the block size        opts.fill    the panel colour
--   opts.label       the corner tag        opts.label_color   its colour (black on bright, white on blue)
local ui = locky.ui

locky.widget.define("brutal.block", {
  description = "A brutalist block: thick border, hard shadow, corner label",
  opts = { w = 300, h = 200, fill = "#ffffff", label = nil, label_color = "#1c1b18" },
  render = function(self)
    local o = self.opts
    return ui.zstack {
      width = o.w, height = o.h, align = "top-leading",
      ui.rect({ width = o.w, height = o.h, color = "#1c1b18", radius = 2, offset = { 9, 9 } }),
      ui.rect({ width = o.w, height = o.h, color = o.fill, radius = 2, stroke = "#1c1b18", stroke_width = 4 }),
      o.label and ui.text(o.label, {
        size = 13, design = "monospaced", weight = "bold", color = o.label_color,
        case = "upper", tracking = 1, offset = { 16, 13 },
      }),
    }
  end,
})
