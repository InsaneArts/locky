-- text: your own words, in the theme's font and text color.
--   opts.text       the words
--   opts.size       "small" (17), "medium" (24, default), "large" (40), or "huge" (72); or a size in points
--   opts.weight     a font weight (default "regular")
--   opts.alignment  "leading", "center" (default), or "trailing": lines up text on several lines
--   opts.color      a palette role or a color (default "fg")
local ui = locky.ui

local sizes = { small = 17, medium = 24, large = 40, huge = 72 }

locky.widget.define("text", {
  description = "Your own words",
  opts = { text = "Your words", size = "medium", weight = "regular", alignment = "center", color = "fg" },
  choices = { size = { "small", "medium", "large", "huge" }, alignment = { "leading", "center", "trailing" } },
  render = function(self)
    local o = self.opts
    local size = sizes[o.size] or (type(o.size) == "number" and o.size) or sizes.medium
    -- Long words wrap at about 24 em, so a sentence keeps the shape of a line of text.
    return ui.text(o.text, { size = size, weight = o.weight, color = o.color, text_align = o.alignment, max_width = size * 24 })
  end,
})
