-- The Sakura theme's widget: this month's traditional Japanese name, set vertically like a hanging scroll.
local ui = locky.ui

-- The old lunar month names, by the month of the year, with their readings and meanings.
local months = {
  { "睦月", "Mutsuki", "month of affection" }, { "如月", "Kisaragi", "month of layered clothes" },
  { "弥生", "Yayoi", "month of new life" }, { "卯月", "Uzuki", "month of the deutzia" },
  { "皐月", "Satsuki", "month of rice planting" }, { "水無月", "Minazuki", "month of water" },
  { "文月", "Fumizuki", "month of letters" }, { "葉月", "Hazuki", "month of leaves" },
  { "長月", "Nagatsuki", "month of long nights" }, { "神無月", "Kannazuki", "month of the gods' absence" },
  { "霜月", "Shimotsuki", "month of frost" }, { "師走", "Shiwasu", "month of running priests" },
}

-- sakura.month: the month's old name in vertical characters, its reading beside it, and what it means below.
--   opts.size (the characters, default 54), opts.font, opts.color, opts.reading (false hides the reading and meaning)
locky.widget.define("sakura.month", {
  description = "This month's traditional Japanese name, set vertically",
  opts = { size = 54, font = "Hiragino Mincho ProN", color = "fg", reading = true },
  init = function(self)
    self:every(3600, function(self)
      local month = os.date("*t").month
      if month ~= self.state.month then
        self:set({ month = month })
      end
    end, { align = true })
  end,
  render = function(self)
    local o, m = self.opts, months[self.state.month or os.date("*t").month]
    local chars = {}
    for _, code in utf8.codes(m[1]) do
      chars[#chars + 1] = ui.text(utf8.char(code), { size = o.size, font = o.font, color = o.color, glow = 10 })
    end
    local column = ui.vstack(chars)
    column.spacing = o.size * 0.08
    if not o.reading then
      return column
    end
    return ui.vstack {
      spacing = 14,
      column,
      ui.text(m[2], { size = o.size * 0.24, font = o.font, color = "muted", tracking = 2 }),
      ui.text(m[3], { size = o.size * 0.2, font = o.font, italic = true, color = "muted", max_width = 150, text_align = "center" }),
    }
  end,
})
