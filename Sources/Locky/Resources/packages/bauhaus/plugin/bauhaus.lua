-- Bauhaus's widget:
--   bauhaus.title   the poster's type: a vertical word set in Futura, opts.text (default "LOCKY"), opts.size
local ui = locky.ui

locky.widget.define("bauhaus.title", {
  description = "A word set vertically, poster style",
  opts = { text = "LOCKY", size = 34 },
  render = function(self)
    local o = self.opts
    local letters = {}
    for ch in o.text:gmatch(utf8.charpattern) do
      letters[#letters + 1] = ui.text(ch, { size = o.size, font = "Futura", weight = "bold", color = o.color or "fg" })
    end
    return ui.vstack { spacing = -o.size * 0.15, letters }
  end,
})
