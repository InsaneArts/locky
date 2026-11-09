-- TUI's box frame: a btop-style rounded panel with a "┤ title ├" tab sitting on its top border.
-- Place it at a box's rectangle, then place the real widget on top, inset to clear the title.
--   opts.w, opts.h   the box size   opts.title   the tab text   opts.color   the tab colour
local ui = locky.ui

locky.widget.define("tui.box", {
  description = "A btop-style bordered box with a title tab",
  opts = { w = 400, h = 200, title = "box", color = "accent" },
  render = function(self)
    local o = self.opts
    return ui.zstack {
      width = o.w, height = o.h, align = "top-leading",
      ui.rect({ width = o.w, height = o.h, color = "surface", radius = 9, stroke = "border", stroke_width = 1.5 }),
      ui.text("┤ " .. o.title .. " ├", {
        size = 13, design = "monospaced", weight = "bold", color = o.color,
        background = "surface", padding = { 1, 7, 1, 7 }, offset = { 18, -9 },
      }),
    }
  end,
})
