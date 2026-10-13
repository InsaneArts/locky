-- fuzzy: the time in words, to the nearest five minutes ("ten past four", "quarter to nine"), like a word clock.
-- English only.
--   opts.case   "lower" (default), "upper", or "title"; opts.prefix (default "it's ") goes before it
--   opts.size, opts.weight, opts.color, opts.font
--   Families: inline, rectangular, small, medium: "It's" in gray, the words big below it, in sentence case.
local ui = locky.ui
local time = require("locky.time")

local function capital(text)
  return (text:gsub("^%l", string.upper))
end

local function family(f, prefix, words)
  prefix = capital((prefix or ""):gsub("%s+$", ""))
  if prefix == "" then
    words = capital(words)
  end
  if f == "inline" then
    return ui.text(prefix == "" and words or (prefix .. " " .. words), ui.font("subheadline", { weight = "semibold", lines = 1 }))
  end
  -- Words wrap at the family's width, on the leading edge.
  local look = ({
    rectangular = { prefix = ui.font("headline", { color = "muted" }), words = ui.font("title3", { weight = "semibold", lines = 2, max_width = 172 }) },
    small = { prefix = ui.font("headline", { color = "muted" }), words = { size = 28, weight = "semibold", lines = 3, max_width = 138 } },
    medium = { prefix = ui.font("headline", { color = "muted" }), words = { size = 44, weight = "semibold", lines = 2, max_width = 332 } },
  })[f]
  look.words.text_align = "leading"
  return ui.vstack {
    spacing = 0, align = "leading", fill = "both",
    prefix ~= "" and ui.text(prefix, look.prefix),
    f ~= "rectangular" and ui.spacer(),
    ui.text(words, look.words),
    f == "rectangular" and ui.spacer(),
  }
end

locky.widget.define("fuzzy", {
  description = "The time in words: ten past four",
  opts = { case = "lower", prefix = "it's ", size = 40, weight = "light" },
  choices = { case = { "lower", "upper", "title" } },
  families = { "inline", "rectangular", "small", "medium" },
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
    if self.family == "inline" or self.family == "rectangular" or self.family == "small" or self.family == "medium" then
      return family(self.family, o.prefix, words)
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
