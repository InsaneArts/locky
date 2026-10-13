-- Gruvbox's widgets: the parts of a conky sidebar.
--   gruvbox.panel     a darker band behind the sidebar; give it a size, such as { 380, 900 }
--   gruvbox.heading   a section title and a rule after it, conky style. opts.text, opts.width (default 300)
local ui = locky.ui

locky.widget.define("gruvbox.panel", {
  description = "A darker band behind the sidebar",
  opts = { color = "panel" },
  render = function(self)
    return ui.rect({ fill = true, color = self.opts.color })
  end,
})

locky.widget.define("gruvbox.heading", {
  description = "A section title with a rule",
  opts = { text = "SYSTEM", width = 300, size = 12 },
  render = function(self)
    local o = self.opts
    return ui.hstack {
      spacing = 10, width = o.width,
      ui.text(o.text, { size = o.size, weight = "bold", color = o.color or "accent", tracking = 2 }),
      ui.rect({ height = 1, fill = "width", color = "border" }),
    }
  end,
})
