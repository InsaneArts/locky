-- quote: a short quote that changes every half hour: from a built-in list of thinkers and programmers, or from
-- `fortune` when it is installed and opts.source is "fortune".
--   Families: medium, large (the quote in the system font, the author under it).
--   opts.source     "builtin" (default) or "fortune"
--   opts.quotes     your own list of { "text", "author" }, used instead of the built-in one
--   opts.every      minutes between quotes (default 30); opts.author false hides the author
--   opts.size, opts.color, opts.font, opts.italic, opts.max_width (default 560), opts.text_align (default "center")
local ui = locky.ui

local builtin = {
  { "The impediment to action advances action. What stands in the way becomes the way.", "Marcus Aurelius" },
  { "Waste no more time arguing what a good man should be. Be one.", "Marcus Aurelius" },
  { "We suffer more often in imagination than in reality.", "Seneca" },
  { "It is not that we have a short time to live, but that we waste a lot of it.", "Seneca" },
  { "Begin at once to live.", "Seneca" },
  { "First say to yourself what you would be; and then do what you have to do.", "Epictetus" },
  { "The journey of a thousand miles begins with one step.", "Lao Tzu" },
  { "Knowing others is intelligence; knowing yourself is true wisdom.", "Lao Tzu" },
  { "Our life is frittered away by detail. Simplify, simplify.", "Henry David Thoreau" },
  { "Nothing can bring you peace but yourself.", "Ralph Waldo Emerson" },
  { "Well done is better than well said.", "Benjamin Franklin" },
  { "Lost time is never found again.", "Benjamin Franklin" },
  { "Brevity is the soul of wit.", "William Shakespeare" },
  { "We know what we are, but know not what we may be.", "William Shakespeare" },
  { "Not all those who wander are lost.", "J. R. R. Tolkien" },
  { "Time you enjoy wasting is not wasted time.", "Marthe Troly-Curtin" },
  { "Rest is not idleness.", "John Lubbock" },
  { "Stay hungry. Stay foolish.", "The Whole Earth Catalog" },
  { "Perfection is achieved not when there is nothing more to add, but when there is nothing left to take away.", "Antoine de Saint-Exupéry" },
  { "Any sufficiently advanced technology is indistinguishable from magic.", "Arthur C. Clarke" },
  { "The best way to predict the future is to invent it.", "Alan Kay" },
  { "Programs must be written for people to read, and only incidentally for machines to execute.", "Abelson & Sussman" },
  { "Simplicity is prerequisite for reliability.", "Edsger W. Dijkstra" },
  { "Controlling complexity is the essence of computer programming.", "Brian Kernighan" },
  { "UNIX is simple. It just takes a genius to understand its simplicity.", "Dennis Ritchie" },
  { "Those who do not understand Unix are condemned to reinvent it, poorly.", "Henry Spencer" },
  { "When in doubt, use brute force.", "Ken Thompson" },
  { "Talk is cheap. Show me the code.", "Linus Torvalds" },
  { "Make it work, make it right, make it fast.", "Kent Beck" },
  { "There are only two hard things in computer science: cache invalidation and naming things.", "Phil Karlton" },
}

-- Apple's layouts: the quote as big as its length allows, the author at the bottom.
local function family(s, o, f)
  local n = #s.text
  local text = (o.quote_marks == false) and s.text or ("“" .. s.text .. "”")
  local author = o.author ~= false and s.author and ui.text("— " .. s.author, ui.font(f == "large" and "subheadline" or "footnote", { weight = "medium", color = "muted", lines = 1 }))
  if f == "medium" then
    local style = n <= 40 and "title2" or n <= 110 and "title3" or n <= 150 and "body" or "callout"
    return ui.vstack {
      spacing = 6, align = "leading", fill = "both",
      ui.text(text, ui.font(style, { weight = "medium", lines = n <= 150 and 4 or 5, line_spacing = 2, text_align = "leading" })),
      ui.spacer(),
      author,
    }
  end
  -- The large card centers the quote between the mark and the author.
  local style = n <= 40 and "large_title" or n <= 80 and "title" or n <= 160 and "title2" or n <= 260 and "title3" or "body"
  return ui.vstack {
    spacing = 10, align = "leading", fill = "both",
    ui.symbol("quote.opening", { size = 28, weight = "semibold", color = "accent" }),
    ui.spacer(),
    ui.text(s.text, ui.font(style, { weight = "medium", lines = 9, line_spacing = 3, text_align = "leading" })),
    ui.spacer(),
    author,
  }
end

locky.widget.define("quote", {
  description = "A short quote that changes every half hour",
  opts = { source = "builtin", every = 30, author = true, size = 18, max_width = 560, text_align = "center" },
  choices = { source = { "builtin", "fortune" } },
  families = { "medium", "large" },
  init = function(self)
    self:every(self.opts.every * 60, function(self)
      local o = self.opts
      if o.source == "fortune" then
        self:system({ "fortune", "-s" }, function(self, result)
          if result.code == 0 then
            local text = result.stdout:gsub("%s+$", ""):gsub("\t", "  ")
            self:set({ text = text, author = false })
          end
        end)
        return
      end
      local list = o.quotes or builtin
      local pick = list[math.floor(os.time() / (o.every * 60)) % #list + 1]
      self:set({ text = pick[1], author = pick[2] })
    end, { align = true })
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.text then
      return nil
    end
    if self.family then
      return family(s, o, self.family)
    end
    local align = o.text_align == "leading" and "leading" or o.text_align == "trailing" and "trailing" or "center"
    return ui.vstack {
      spacing = o.size * 0.6, align = align,
      ui.text((o.quote_marks == false) and s.text or ("“" .. s.text .. "”"), {
        size = o.size, font = o.font, italic = o.italic, color = o.color, max_width = o.max_width, text_align = o.text_align,
        line_spacing = o.size * 0.25,
      }),
      o.author ~= false and s.author and ui.text("— " .. s.author, { size = o.size * 0.7, color = "muted", font = o.font, tracking = 0.5 }),
    }
  end,
})
