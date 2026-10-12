-- Poster: the time as a poster in the International Typographic Style. Two numerals cropped by the screen's
-- edges, the red minutes overprinting the black hours, and small type in ruled blocks on a 12-column grid.
--
--   poster.numerals  the hours (ink, flush left, cropped at the top) and the minutes (red, flush right,
--                    cropped at the bottom), the red overprinting the black.
--                    opts: font ("HelveticaNeue-CondensedBlack" or "HelveticaNeue-CondensedBold"), size (855,
--                    0.95 of the screen's height), margin (72), crop_top (0.12), crop_bottom (0.10), hours and
--                    minutes (colors), overprint (true: the minutes multiply over the hours), part ("all",
--                    "hours", or "minutes": see below)
--   poster.info      ruled blocks of small type. opts: blocks (any of "date", "week", "user", "host",
--                    "agents", in order), size (14), rows (most agents listed, 4), every (seconds between
--                    herdr checks, 5)
--   poster.weekday   the weekday, turned to run up the edge, in tracked capitals. opts: size, tracking, length
--   poster.seconds   a red square stepping across the 12 columns, one column every 5 seconds, on a ruler that
--                    runs off the right edge. opts: size, tick, bleed (1200; 0 ends the ruler at the margin)
local ui = locky.ui
local herdr = require("locky.herdr")

-- The grid, in points on the 1440 x 900 layout: 12 columns between 72-point margins, with 24-point gutters.
local GRID = { width = 1440, height = 900, margin = 72, columns = 12, gutter = 24 }
GRID.column = (GRID.width - 2 * GRID.margin - (GRID.columns - 1) * GRID.gutter) / GRID.columns -- 86
GRID.pitch = GRID.column + GRID.gutter -- 110
GRID.span = GRID.width - 2 * GRID.margin -- 1296

-------------------------------------------------------------------------------
-- The numerals
-------------------------------------------------------------------------------

-- Metrics of the condensed faces, in ems, measured with Core Text: ascent and descent, the digits' advance (they
-- are tabular), their height, and each digit's side bearings, so the ink (not the glyph's box) meets the
-- margins. `weight` must match the face: Locky applies a weight to every font, and the default (regular)
-- would swap the condensed face for the family's regular one.
local FACES = {
  ["HelveticaNeue-CondensedBlack"] = {
    weight = "black", ascent = 0.972, descent = 0.227, advance = 0.520, top = 0.708,
    lsb = { [0] = 0.019, 0.049, 0.019, 0.019, 0.016, 0.019, 0.019, 0.025, 0.019, 0.019 },
    rsb = { [0] = 0.019, 0.151, 0.035, 0.035, 0.016, 0.037, 0.019, 0.033, 0.019, 0.019 },
  },
  ["HelveticaNeue-CondensedBold"] = {
    weight = "bold", ascent = 0.961, descent = 0.221, advance = 0.480, top = 0.708,
    lsb = { [0] = 0.018, 0.041, 0.018, 0.020, 0.014, 0.018, 0.014, 0.022, 0.014, 0.014 },
    rsb = { [0] = 0.018, 0.154, 0.026, 0.020, 0.014, 0.026, 0.014, 0.022, 0.014, 0.014 },
  },
}

-- part: "all" draws both numbers in one widget, centered on a 1440 x 1100 frame. The theme instead places
-- two widgets, "hours" anchored at the top left and "minutes" at the bottom right, each a 1440 x 900 frame,
-- so the crops stay exact on any screen. The red still overprints the black: a blend mode mixes a view with
-- everything drawn below it, other widgets included.
locky.widget.define("poster.numerals", {
  description = "The hours and minutes, cropped by the screen's edges, the red overprinting the black",
  opts = {
    font = "HelveticaNeue-CondensedBlack", size = 855, margin = GRID.margin, crop_top = 0.12, crop_bottom = 0.10,
    hours = "fg", minutes = "accent", overprint = true, part = "all",
  },
  init = function(self)
    local hour24 = locky.date.locale().hour24
    self:every(60, function(self)
      local t = os.date("*t")
      local hh = ("%02d"):format(hour24 and t.hour or (t.hour + 11) % 12 + 1)
      local mm = ("%02d"):format(t.min)
      if hh ~= self.state.hh or mm ~= self.state.mm then
        self:set({ hh = hh, mm = mm })
      end
    end, { align = true })
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.hh then
      return nil
    end
    local part = o.part or "all"
    local face = FACES[o.font] or FACES["HelveticaNeue-CondensedBlack"]
    local size, W, H = o.size, GRID.width, GRID.height
    local height = face.top * size -- the digits' height
    local width = 2 * face.advance * size -- two tabular digits
    -- SwiftUI's box for one line of text is ascent + descent tall, so the baseline sits this far below
    -- its center.
    local baseline = (face.ascent - face.descent) / 2 * size
    -- Children sit at the frame's center (the layout's center) and move by offset.
    local function place(left, base)
      return { left + width / 2 - W / 2, base - baseline - H / 2 }
    end
    local text = { font = o.font, weight = face.weight, size = size, lines = 1 }
    local hours = part ~= "minutes" and ui.text(s.hh, locky.tbl.extend("force", text, {
      color = o.hours,
      offset = place(o.margin - face.lsb[tonumber(s.hh:sub(1, 1))] * size, (1 - o.crop_top) * height),
    }))
    local minutes = part ~= "hours" and ui.text(s.mm, locky.tbl.extend("force", text, {
      color = o.minutes, blend = o.overprint and "multiply" or nil,
      offset = place(W - o.margin + face.rsb[tonumber(s.mm:sub(2, 2))] * size - width, H + o.crop_bottom * height),
    }))
    -- One widget gets 100 points more above and below, so a taller screen still shows the glyphs to its edges.
    return ui.zstack { width = W, height = part == "all" and H + 200 or H, hours, minutes }
  end,
})

-------------------------------------------------------------------------------
-- The info blocks
-------------------------------------------------------------------------------

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

-- One ruled block: a 1-point rule across the block, then the label in the first column and the lines of
-- the value from the second column on, flush left, ragged right.
local function block(o, label, lines)
  local value_width = o.width - GRID.column - GRID.gutter
  return ui.vstack {
    align = "leading", spacing = 0,
    ui.rect({ width = o.width, height = 1, color = "fg" }),
    ui.hstack {
      align = "top", spacing = GRID.gutter, padding = { 7, 0, 15, 0 },
      -- The label is smaller: move it down so the two baselines meet.
      ui.text(label, {
        size = o.size - 3, weight = "medium", color = "muted", width = GRID.column, text_align = "leading",
        lines = 1, offset = { 0, 3 * 0.95 },
      }),
      ui.vstack { align = "leading", spacing = 4, width = value_width, text_align = "leading", lines },
    },
  }
end

local function line(o, text, props)
  return ui.text(text, locky.tbl.extend("force", { size = o.size, color = "fg", lines = 1 }, props or {}))
end

local renderers = {
  date = function(self, o, s)
    local hour24 = s.hour24
    return block(o, "Date", {
      ui.hstack {
        spacing = 6,
        line(o, s.weekday, { weight = "medium" }),
        line(o, s.date),
        not hour24 and line(o, os.date("*t").hour < 12 and "AM" or "PM", { color = "muted" }),
      },
    })
  end,
  week = function(self, o, s)
    return block(o, "Week", { line(o, s.week) })
  end,
  user = function(self, o, s)
    return block(o, "User", { line(o, s.user) })
  end,
  host = function(self, o, s)
    return block(o, "Host", { line(o, s.host) })
  end,
  agents = function(self, o, s)
    local agents = s.agents
    if not agents or #agents == 0 then
      return nil
    end
    -- Three columns inside the value column: the number, the agent, and the title, flush left.
    local number, kind = 20, 70
    local rows = {}
    for i = 1, math.min(#agents, o.rows) do
      local a = agents[i]
      rows[i] = ui.hstack {
        spacing = 0,
        -- Blocked agents get a red number: they are waiting for you.
        line(o, tostring(i), { weight = "bold", color = a.status == "blocked" and "accent" or "fg", width = number, text_align = "leading" }),
        line(o, a.kind, { weight = "medium", width = kind, text_align = "leading" }),
        -- In privacy mode the title is the kind, which the column before already shows.
        line(o, a.title ~= a.kind and a.title or "", { max_width = o.width - GRID.pitch - number - kind }),
      }
    end
    if #agents > o.rows then
      rows[#rows + 1] = line(o, ("+%d more"):format(#agents - o.rows), { color = "muted", padding = { 0, number, 0, 0 } })
    end
    return block(o, "Agents", rows)
  end,
}

locky.widget.define("poster.info", {
  description = "Small type in ruled blocks: the date, the week, you, this Mac, and the herdr agents that need you",
  opts = { blocks = { "date", "week", "user", "host", "agents" }, width = 4 * GRID.column + 3 * GRID.gutter, size = 14, rows = 4, every = 5 },
  init = function(self)
    local o = self.opts
    local user = locky.sys.user()
    self.state.user = user.full_name ~= "" and user.full_name or user.name
    self.state.host = locky.sys.hostname().name
    self.state.hour24 = locky.date.locale().hour24
    -- Checked once a minute; redrawn only when the day (or, in 12-hour locales, AM/PM) changes.
    self:every(60, function(self)
      local key = os.date("%Y-%m-%d") .. (self.state.hour24 and "" or (os.date("*t").hour < 12 and "am" or "pm"))
      if key ~= self.state.day then
        self:set({ day = key, weekday = locky.date.format("EEEE"), date = locky.date.format("d MMMM"), week = locky.date.format("w") })
      end
    end, { align = true })
    if contains(o.blocks, "agents") then
      herdr.watch(self, o.every, function(self, data)
        local list, keys = {}, {}
        for _, a in ipairs(data and data.agents or {}) do
          if a.status == "blocked" or a.status == "done" then
            list[#list + 1] = a
            keys[#keys + 1] = a.status .. "\0" .. a.kind .. "\0" .. a.title
          end
        end
        local key = table.concat(keys, "\n")
        if key ~= self.state.agents_key then
          self:set({ agents = list, agents_key = key })
        end
      end)
    end
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.day then
      return nil
    end
    local blocks = {}
    for _, name in ipairs(o.blocks) do
      local render = renderers[name]
      blocks[#blocks + 1] = render and render(self, o, s) or nil
    end
    return ui.vstack { align = "leading", spacing = 0, width = o.width, text_align = "leading", blocks }
  end,
})

-------------------------------------------------------------------------------
-- The weekday, up the edge
-------------------------------------------------------------------------------

locky.widget.define("poster.weekday", {
  description = "The weekday in tracked capitals, running up the edge",
  opts = { size = 11, weight = "medium", tracking = 3.5, color = "fg", length = 240 },
  init = function(self)
    self:every(60, function(self)
      local day = locky.date.format("EEEE")
      if day ~= self.state.day then
        self:set({ day = day })
      end
    end, { align = true })
  end,
  render = function(self)
    local o, day = self.opts, self.state.day
    if not day then
      return nil
    end
    local thickness = math.ceil(o.size * 1.4)
    -- Laid out along a line `length` long, flush left, then turned so it reads upwards from the bottom.
    return ui.zstack {
      width = thickness, height = o.length,
      ui.hstack {
        width = o.length, height = thickness, rotation = -90, text_align = "leading",
        ui.text(day, { size = o.size, weight = o.weight, case = "upper", tracking = o.tracking, color = o.color, lines = 1 }),
      },
    }
  end,
})

-------------------------------------------------------------------------------
-- The seconds
-------------------------------------------------------------------------------

locky.widget.define("poster.seconds", {
  description = "A red square stepping across the 12 columns, one column every 5 seconds",
  -- bleed: how far the rule runs on past the 12th column, off the screen's right edge on any width (0 stops
  -- it at the right margin).
  opts = { size = 12, tick = 7, bleed = 1200, color = "accent", ink = "fg", keyline = "bg" },
  init = function(self)
    self:every(5, function(self)
      local column = os.date("*t").sec // 5
      if column ~= self.state.column then
        self:set({ column = column })
      end
    end, { align = true })
  end,
  render = function(self)
    local o, column = self.opts, self.state.column
    if not column then
      return nil
    end
    local total = GRID.span + (o.bleed or 0)
    -- Children sit at the frame's center; this puts one with its left edge `x` points into the frame.
    local function at(x, width, y)
      return { x + width / 2 - total / 2, y or 0 }
    end
    local children = {
      -- A 1-point rule with a short tick at the start of each column, like a ruler.
      ui.rect({ width = total, height = 1, color = o.ink, offset = at(0, total, o.size / 2 - 0.5) }),
    }
    for i = 0, GRID.columns - 1 do
      children[#children + 1] = ui.rect({ width = 1, height = o.tick, color = o.ink, offset = at(i * GRID.pitch, 1, (o.size - o.tick) / 2) })
    end
    -- The square stands on the rule, knocked out of whatever it crosses by a paper-colored rim, as a
    -- printer would.
    local x = column * GRID.pitch
    children[#children + 1] = ui.rect({ width = o.size + 4, height = o.size + 4, color = o.keyline, offset = at(x - 2, o.size + 4) })
    children[#children + 1] = ui.rect({ width = o.size, height = o.size, color = o.color, offset = at(x, o.size) })
    return ui.zstack { width = total, height = o.size + 4, children }
  end,
})
