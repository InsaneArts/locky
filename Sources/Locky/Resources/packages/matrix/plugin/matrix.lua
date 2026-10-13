-- The Matrix theme's widget: the messages that find Neo, typed out one letter at a time.
--   opts.name   the name in the messages (default: your first name; "Neo" in privacy mode)
--   opts.hold   seconds each message stays (default 6); opts.rest seconds of quiet after the last (default 60)
--   opts.size, opts.color
local ui = locky.ui

local lines = {
  "Wake up, %s…",
  "The Matrix has you…",
  "Follow the white rabbit.",
  "Knock, knock, %s.",
}

locky.widget.define("matrix.whisper", {
  description = "\"Wake up, Neo…\", typed out one letter at a time",
  opts = { size = 20, color = "fg", hold = 6, rest = 60 },
  init = function(self)
    local name = self.opts.name
    if name == nil then
      name = locky.config.privacy == true and "Neo" or (locky.sys.user().full_name:match("^(%S+)") or "Neo")
    end
    local line, shown, blinks = 1, 0, 0
    local function step(self)
      local text = lines[line]:format(name)
      if shown < utf8.len(text) then
        shown = shown + 1
        self:set({ text = text:sub(1, (utf8.offset(text, shown + 1) or #text + 1) - 1), cursor = true })
        self:after(shown == 1 and 0.6 or 0.06 + math.random() * 0.08, step)
      elseif blinks < self.opts.hold * 2 then
        blinks = blinks + 1
        self:set({ text = text, cursor = blinks % 2 == 0 })
        self:after(0.5, step)
      else
        -- After the last line, a rest with a steady cursor before the messages start over.
        line, shown, blinks = line % #lines + 1, 0, 0
        self:set({ text = "", cursor = true })
        self:after(line == 1 and self.opts.rest or 1.2, step)
      end
    end
    self.state.text, self.state.cursor, self.state.width = "", true, 0
    for _, l in ipairs(lines) do
      self.state.width = math.max(self.state.width, utf8.len(l:format(name)) + 1)
    end
    self:after(1, step)
  end,
  render = function(self)
    local o = self.opts
    -- Padded to the longest line, so the width never changes and typing does not lay the screen out again.
    local text = self.state.text .. (self.state.cursor and "█" or " ")
    text = text .. (" "):rep(math.max(self.state.width - utf8.len(text), 0))
    -- Leading: centered text would center only the letters, as trailing spaces hang outside the line.
    return ui.text(text, { size = o.size, design = "monospaced", color = o.color, glow = 6, text_align = "leading" })
  end,
})
