-- Cyberdeck HUD chrome: L-shaped corner brackets and a bracketed section label, drawn with plain shapes.
local ui = locky.ui

locky.widget.define("cyberdeck.corner", {
  description = "HUD corner bracket",
  opts = { corner = "tl", color = "cyan", len = 46, thick = 2 },
  render = function(self)
    local o = self.opts
    local align = ({ tl = "top-leading", tr = "top-trailing", bl = "bottom-leading", br = "bottom-trailing" })[o.corner] or "top-leading"
    return ui.zstack {
      width = o.len, height = o.len, align = align,
      ui.rect { width = o.len, height = o.thick, color = o.color },
      ui.rect { width = o.thick, height = o.len, color = o.color },
    }
  end,
})

-- A bracketed, uppercase section tag: [ SYS ]
locky.widget.define("cyberdeck.tag", {
  description = "HUD section tag",
  opts = { text = "SYS", color = "cyan", size = 12 },
  render = function(self)
    local o = self.opts
    return ui.text("[ " .. tostring(o.text) .. " ]", { size = o.size, color = o.color, case = "upper", tracking = 3, mono = true, weight = "semibold" })
  end,
})
