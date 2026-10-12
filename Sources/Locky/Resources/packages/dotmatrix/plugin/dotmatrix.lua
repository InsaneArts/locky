-- Dot Matrix widgets: a 5x7 dot-matrix clock, a word in small dot letters, mono labels, and herdr agents
-- as square dots. Colors are palette roles: fg (lit dots), dim (unlit dots), signal (the colon's red dot),
-- muted (labels).
local ui = locky.ui
local font = require("dotmatrix.font")
local herdr = require("locky.herdr")

-- One glyph as rows of dot cells, each cell `pitch` square with a dot of `size` in its middle. Unlit cells
-- get a dot in `unlit`, or stay empty when `unlit` is nil.
local function glyph_view(char, pitch, size, lit, unlit)
  local glyph = font.glyph(char)
  local rows = { spacing = 0 }
  for r = 1, font.height do
    local cells = { spacing = 0 }
    for c = 1, font.width do
      local on = font.lit(glyph, r, c)
      if on or unlit then
        cells[c] = ui.dot({ size = size, width = pitch, height = pitch, color = on and lit or unlit })
      else
        cells[c] = ui.rect({ width = pitch, height = pitch })
      end
    end
    rows[r] = ui.hstack(cells)
  end
  return ui.vstack(rows)
end

-- The clock is 25 dot columns (four 5-column glyphs, the colon's column, and a blank column between each)
-- by 7 rows. The colon's lit dots are in rows 3 and 5; the red one, in row 5, is dotmatrix.pulse.
local COLUMNS, ROWS = 25, font.height

-- dotmatrix.clock: HH:MM in 5x7 glyphs. Unlit dots fill each glyph's cell, as on a character display.
-- It changes once a minute; place dotmatrix.pulse with the same anchor and offset for the red dot.
--   opts.pitch    distance between dot centers (default 24: every other dot of the background grid)
--   opts.dot      dot diameter as a fraction of the pitch (default 0.8)
--   opts.hour24   true or false overrides the system's 12/24-hour setting
locky.widget.define("dotmatrix.clock", {
  description = "HH:MM in 5x7 dot glyphs",
  opts = { pitch = 24, dot = 0.8 },
  init = function(self)
    local o = self.opts
    local hour24 = o.hour24
    if hour24 == nil then
      hour24 = locky.date.locale().hour24
    end
    local pitch, size = o.pitch, o.pitch * o.dot
    self.glyphs = {}
    self.glyph = function(char)
      self.glyphs[char] = self.glyphs[char] or glyph_view(char, pitch, size, "fg", "dim")
      return self.glyphs[char]
    end
    self.gap = ui.rect({ width = pitch, height = pitch * ROWS })
    local unlit = ui.dot({ size = size, width = pitch, height = pitch, color = "dim" })
    local lit = ui.dot({ size = size, width = pitch, height = pitch, color = "fg" })
    self.colon = ui.vstack { spacing = 0, unlit, unlit, lit, unlit, unlit, unlit, unlit }
    -- Checked each second, so the time is right within a second after the Mac wakes; drawn only when it
    -- changes.
    self:every(1, function(self)
      local t = os.date("*t")
      local hour = hour24 and t.hour or (t.hour + 11) % 12 + 1
      local digits = (hour24 and "%02d%02d" or "%2d%02d"):format(hour, t.min)
      if digits ~= self.state.digits then
        self:set({ digits = digits })
      end
    end, { align = true })
  end,
  render = function(self)
    local digits = self.state.digits
    if not digits then
      return nil
    end
    local glyph, gap = self.glyph, self.gap
    return ui.hstack {
      spacing = 0,
      glyph(digits:sub(1, 1)), gap, glyph(digits:sub(2, 2)), gap,
      self.colon,
      gap, glyph(digits:sub(3, 3)), gap, glyph(digits:sub(4, 4)),
    }
  end,
})

-- dotmatrix.pulse: the colon's red dot. It lights at each new second and dims half a second later. It is a
-- widget of its own, the clock's size and mostly empty, because any change inside a widget lays out all of
-- it again: inside the clock, this dot would cost about 10% of a core. Give it the clock's anchor, offset,
-- and pitch.
--   opts.pitch, opts.dot   the clock's (defaults 24 and 0.8)
locky.widget.define("dotmatrix.pulse", {
  description = "The red dot in dotmatrix.clock's colon, pulsing once a second",
  opts = { pitch = 24, dot = 0.8 },
  init = function(self)
    local o = self.opts
    local function frame(dot)
      return ui.zstack { width = o.pitch * COLUMNS, height = o.pitch * ROWS, dot }
    end
    -- The center column, one row below the middle.
    local at = { 0, o.pitch }
    self.views = {
      [true] = frame(ui.dot({ size = o.pitch * o.dot, color = "signal", glow = 9, offset = at })),
      [false] = frame(ui.dot({ size = o.pitch * o.dot, color = "signal", opacity = 0.3, offset = at })),
    }
    -- On the wall clock's half seconds: the first tick in a new second lights the dot, the next dims it.
    self:every(0.5, function(self)
      local now = os.time()
      self:set({ on = now ~= self.second })
      self.second = now
    end, { align = true })
  end,
  render = function(self)
    return self.views[self.state.on == true]
  end,
})

-- dotmatrix.word: a short word in small dot-matrix letters (A-Z, 0-9, "-", ".", space).
--   opts.text, opts.pitch (default 4), opts.dot (fraction of the pitch, default 0.75), opts.color
locky.widget.define("dotmatrix.word", {
  description = "A short word in small dot-matrix letters",
  opts = { text = "LOCKED", pitch = 4, dot = 0.75, color = "muted" },
  render = function(self)
    local o = self.opts
    local letters = { spacing = o.pitch }
    for i = 1, #o.text do
      letters[i] = glyph_view(o.text:sub(i, i), o.pitch, o.pitch * o.dot, o.color, nil)
    end
    return ui.hstack(letters)
  end,
})

-- dotmatrix.info: the date at the left, battery at the right, and uptime between them (at the right on a
-- Mac without a battery). Mono caps in the muted color; the battery turns danger at or below opts.low.
--   opts.width (default 596: the clock's dots, edge to edge), opts.size, opts.tracking, opts.format (a date
--   template, such as "EEE d MMM")
locky.widget.define("dotmatrix.info", {
  description = "Date, uptime, and battery in small mono caps",
  opts = { width = 596, size = 12, tracking = 1.5, format = "EEE d MMM", low = 20 },
  init = function(self)
    self:every(30, function(self)
      local o, s = self.opts, self.state
      local date = locky.date.format(o.format)
      local up = locky.sys.uptime()
      local days, hours = up // 86400, up % 86400 // 3600
      local uptime = days > 0 and ("UP %dD %02dH"):format(days, hours) or ("UP %dH %02dM"):format(hours, up % 3600 // 60)
      local b = locky.sys.battery()
      local battery, low = false, false
      if b.present and b.percent then
        battery = (b.charging and "CHG %d%%" or "BAT %d%%"):format(b.percent)
        low = not b.charging and b.percent <= o.low
      end
      if date ~= s.date or uptime ~= s.uptime or battery ~= s.battery or low ~= s.low then
        self:set({ date = date, uptime = uptime, battery = battery, low = low })
      end
    end, { align = true })
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.date then
      return nil
    end
    -- Three fixed columns, so the outer labels sit on the clock's edges and uptime on its center.
    local function label(text, align, color)
      return ui.text(text, {
        size = o.size, case = "upper", tracking = o.tracking, color = color or "muted", lines = 1,
        width = o.width / 3, text_align = align,
      })
    end
    return ui.hstack {
      spacing = 0,
      label(s.date, "leading"),
      label(s.battery and s.uptime or "", "center"),
      label(s.battery or s.uptime, "trailing", s.battery and s.low and "danger" or nil),
    }
  end,
})

-- dotmatrix.agents: one square dot per herdr agent, most urgent first: blocked in signal (red), done in
-- fg (white), working in muted (gray), idle as an outline. Hidden when herdr is off or has no agents.
--   opts.size, opts.gap, opts.max (most squares), opts.label (false hides it), opts.every (seconds)
local colors = { blocked = "signal", done = "fg", working = "muted" }

locky.widget.define("dotmatrix.agents", {
  description = "herdr agents as square dots: blocked red, done white, working gray",
  opts = { size = 9, gap = 5, max = 30, label = "AGENTS", every = 3 },
  init = function(self)
    herdr.watch(self, self.opts.every, function(self, data)
      local key = ""
      for _, a in ipairs(data and data.agents or {}) do
        key = key .. a.status:sub(1, 2)
      end
      if key ~= self.state.key then
        self:set({ key = key, agents = data and data.agents or false })
      end
    end)
  end,
  render = function(self)
    local o, agents = self.opts, self.state.agents
    if not agents or #agents == 0 then
      return nil
    end
    local squares = { spacing = o.gap }
    for i = 1, math.min(#agents, o.max) do
      local color = colors[agents[i].status]
      squares[i] = ui.rect({
        width = o.size, height = o.size, radius = 1,
        color = color, stroke = not color and "muted" or nil, stroke_width = 1,
      })
    end
    return ui.hstack {
      spacing = 12,
      o.label and ui.text(o.label, { size = 11, case = "upper", tracking = 1.5, color = "muted" }),
      ui.hstack(squares),
    }
  end,
})
