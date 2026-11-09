-- OP-1's own parts: the little OLED display and the row of encoder-colour dots.
--   op1.screen   a black OLED panel with green mono readout. opts.w, opts.h, opts.color
--   op1.dots     the four encoder colours (blue, green, white, orange), like the OP-1's knobs
local ui = locky.ui

locky.widget.define("op1.screen", {
  description = "The OP-1 OLED display",
  opts = { w = 324, h = 288, color = "#00ff66" },
  render = function(self)
    local o = self.opts
    return ui.vstack {
      width = o.w, height = o.h, background = "#0b0d0b", radius = 6,
      border = "#ff6600", border_width = 2, align = "leading", spacing = 8,
      padding = { 22, 24, 22, 24 },
      ui.text("2 · SCREEN", { size = 11, design = "monospaced", weight = "bold", color = o.color, tracking = 3 }),
      ui.spacer(),
      ui.time("EEEE", { size = 22, design = "monospaced", weight = "bold", color = o.color, case = "upper", tracking = 2 }),
      ui.time("d MMMM", { size = 15, design = "monospaced", color = o.color, tracking = 1 }),
      ui.time("HH:mm", { size = 48, design = "monospaced", weight = "bold", color = o.color, mono = true }),
      ui.spacer(),
      ui.text("REC · PLAY · STOP", { size = 10, design = "monospaced", color = o.color, tracking = 2, opacity = 0.8 }),
    }
  end,
})

locky.widget.define("op1.dots", {
  description = "The four encoder colours",
  render = function(self)
    local function knob(c, ring)
      return ui.circle({ width = 16, height = 16, color = c, stroke = ring, stroke_width = ring and 1 or 0 })
    end
    return ui.hstack {
      spacing = 11,
      knob("#2b7fff"),
      knob("#00d957"),
      knob("#ffffff", "#c9c9c9"),
      knob("#ff6600"),
    }
  end,
})
