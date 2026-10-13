-- fuzzy: the time in words, to the nearest five minutes ("ten past four", "quarter to nine"), like a word clock.
-- English only.
--   opts.case   "lower" (default), "upper", or "title"; opts.prefix (default "it's ") goes before it
--   opts.size, opts.weight, opts.color, opts.font
local ui = locky.ui
local time = require("locky.time")

locky.widget.define("fuzzy", {
  description = "The time in words: ten past four",
  opts = { case = "lower", prefix = "it's ", size = 40, weight = "light" },
  choices = { case = { "lower", "upper", "title" } },
  init = function(self)
    self:every(60, function(self)
      local t = os.date("*t")
      self:set({ words = time.fuzzy(t.hour, t.min) })
    end, { align = true })
  end,
  render = function(self)
    local o, words = self.opts, self.state.words
    if not words then
      return nil
    end
    local text = (o.prefix or "") .. words
    if o.case == "title" then
      text = text:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)
    end
    return ui.text(text, {
      size = o.size, weight = o.weight, font = o.font, color = o.color, case = o.case ~= "title" and o.case or nil,
      text_align = o.text_align or "center", max_width = o.max_width,
    })
  end,
})
