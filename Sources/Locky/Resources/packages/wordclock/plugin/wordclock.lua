-- Word Clock: the time spelled out on an 11 x 10 letter grid, after the QLOCKTWO. English only.
--
--   wordclock.grid   the letter grid, its lit phrase, and the four corner dots for the minutes in between
--   wordclock.date   a small tracked line for the date
local ui = locky.ui
local words = require("wordclock.words")

locky.widget.define("wordclock.grid", {
  description = "The time in words on a letter grid",
  opts = {
    cell = 62,              -- one letter's square, in points
    size = 38,              -- letter size
    font = "Avenir Next", weight = "semibold",
    lit = "accent",         -- lit letters and dots
    unlit = "fg",           -- unlit letters and dots, at `dim`
    dim = 0.1,
    glow = { 6, 22 },       -- the inner and outer glow radii; false for none
    glow_opacity = { 0.55, 0.4 },
    dot = 7,                -- corner dot diameter
    dot_inset = 22,         -- from the grid's corner to a dot's center
  },
  init = function(self)
    -- Redraw on each new minute. A tick that fires a moment early still shows the new minute.
    self:every(60, function(self)
      self:set({ tick = os.time() + 20 })
    end, { align = true, now = false })
  end,
  render = function(self)
    local o = self.opts
    local now = os.date("*t", math.max(os.time(), self.state.tick or 0))
    local lit, dots = words.at(now.hour, now.min)

    local cell, glow = o.cell, o.glow
    local letter = { font = o.font, weight = o.weight, size = o.size, width = cell, height = cell }
    local dim_letter = locky.tbl.extend("force", letter, { color = o.unlit })
    local lit_letter = locky.tbl.extend("force", letter, { color = o.lit })
    local blank = ui.rect({ width = cell, height = cell })
    local all, on = {}, {}
    for r, line in ipairs(words.grid) do
      local a, b = {}, {}
      for c = 1, #line do
        local ch = line:sub(c, c)
        a[c] = ui.text(ch, dim_letter)
        b[c] = lit[r .. ":" .. c] and ui.text(ch, lit_letter) or blank
      end
      all[r] = ui.hstack { spacing = 0, a }
      on[r] = ui.hstack { spacing = 0, b }
    end

    -- The lit phrase three times: a wide soft glow, a close glow, and the crisp letters on top.
    local function layer(props)
      return ui.vstack(locky.tbl.extend("force", { spacing = 0, color = o.lit }, props, on))
    end

    -- Dots clockwise from the top-left corner, lit for the minutes after the five.
    local w, h = cell * #words.grid[1], cell * #words.grid
    local dx, dy = w / 2 + o.dot_inset, h / 2 + o.dot_inset
    local corners = { { -dx, -dy }, { dx, -dy }, { dx, dy }, { -dx, dy } }
    local dot_views = {}
    for i, p in ipairs(corners) do
      local on_dot = i <= dots
      dot_views[i] = ui.dot({
        size = o.dot, offset = p, color = on_dot and o.lit or o.unlit, opacity = on_dot and 1 or o.dim,
        glow = on_dot and glow and glow[1] or nil,
      })
    end

    return ui.zstack {
      width = w + 2 * (o.dot_inset + o.dot), height = h + 2 * (o.dot_inset + o.dot),
      ui.vstack { spacing = 0, color = o.unlit, opacity = o.dim, all },
      glow and layer({ glow = glow[2], opacity = o.glow_opacity[2] }),
      glow and layer({ glow = glow[1], opacity = o.glow_opacity[1] }),
      layer({}),
      dot_views,
    }
  end,
})

locky.widget.define("wordclock.date", {
  description = "The date in a small tracked line",
  opts = { format = "EEEE d MMMM", size = 13, tracking = 4.5, font = "Avenir Next", weight = "semibold", color = "muted" },
  render = function(self)
    local o = self.opts
    return ui.time(o.format, {
      font = o.font, weight = o.weight, size = o.size, tracking = o.tracking, case = "upper", color = o.color,
    })
  end,
})
