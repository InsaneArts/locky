-- The Blueprint theme's widgets: a clock drawn as a technical drawing, an engineering title block, and the sheet's
-- general notes. All in DIN, the lettering of German technical drawings.
local ui = locky.ui
local din, condensed = "DIN Alternate", "DIN Condensed"

-- Props and a list of children as the one table a stack takes.
local function with(props, children)
  for _, child in ipairs(children) do
    props[#props + 1] = child
  end
  return props
end

-- A center line: long dash, gap, short dash, gap, made of short lines because a line view has no dash pattern.
local function chain(length, rotation)
  local parts = {}
  for _ = 1, math.floor(length / 30) do
    parts[#parts + 1] = ui.line({ width = 18, stroke_width = 1 })
    parts[#parts + 1] = ui.line({ width = 3, stroke_width = 1 })
  end
  return ui.hstack(with({ spacing = 4.5, rotation = rotation, opacity = 0.75 }, parts))
end

-- A hand drawn as an outline, pivoting at the center.
local function hand(length, width, angle)
  return ui.capsule({ width = width, height = length + width, color = "bg", stroke = "fg", stroke_width = 1.5,
                      offset = { 0, -(length - width) / 2 }, rotation = angle })
end

-- A tick on the dial: `length` long, its outer end at radius `r`. Rotation turns the offset with it.
local function tick(r, length, angle, weight)
  return ui.rect({ width = weight, height = length, color = "fg", offset = { 0, -(r - length / 2) }, rotation = angle })
end

local function arrow(x, y, left)
  local points = left and { { 0, 0.5 }, { 1, 0 }, { 1, 1 } } or { { 1, 0.5 }, { 0, 0 }, { 0, 1 } }
  return ui.polygon({ points = points, width = 12, height = 6, color = "fg", offset = { x + (left and 6 or -6), y } })
end

local function label(text, x, y, size)
  return ui.text(text, { font = din, size = size or 13, offset = { x, y }, tracking = 1 })
end

locky.widget.define("blueprint.clock", {
  description = "A clock drawn as a technical drawing, with a diameter and the minute hand's angle dimensioned",
  opts = { size = 360 },
  init = function(self)
    self:every(60, function(self) self:set({ t = os.time() }) end, { align = true })
  end,
  render = function(self)
    local s = self.opts.size
    local r = s / 2
    local now = os.date("*t", self.state.t or os.time())
    local minute = now.min * 6
    local hour = (now.hour % 12) * 30 + now.min * 0.5
    local children = {
      ui.circle({ width = s, height = s, stroke = "fg", stroke_width = 2.5 }),
      ui.circle({ width = s * 0.86, height = s * 0.86, stroke = "fg", stroke_width = 1, dash = { 8, 5 }, opacity = 0.6 }),
      chain(s * 1.25, 0),
      chain(s * 1.25, 90),
      ui.circle({ width = 14, height = 14, stroke = "fg", stroke_width = 1.5 }),
    }
    for i = 0, 59 do
      local five = i % 5 == 0
      children[#children + 1] = tick(r - 4, five and r * 0.12 or r * 0.04, i * 6, five and 2 or 1)
    end
    -- The angle of the minute hand from twelve, dimensioned with an arc.
    if minute > 0 then
      local a = math.rad(minute / 2)
      children[#children + 1] = ui.ring(minute / 360, { size = s * 0.42, stroke_width = 1, stroke = "#00000000", style = "butt", color = "accent" })
      children[#children + 1] = ui.text(("%d°"):format(minute), {
        font = din, size = 13, color = "accent", offset = { math.sin(a) * s * 0.3, -math.cos(a) * s * 0.3 },
      })
    end
    children[#children + 1] = hand(r * 0.5, 12, hour)
    children[#children + 1] = hand(r * 0.78, 8, minute)
    -- The diameter, dimensioned below the dial.
    local y = r + 34
    children[#children + 1] = ui.rect({ width = 1, height = 48, color = "fg", offset = { -r, r + 14 }, opacity = 0.75 })
    children[#children + 1] = ui.rect({ width = 1, height = 48, color = "fg", offset = { r, r + 14 }, opacity = 0.75 })
    children[#children + 1] = ui.line({ width = s, stroke_width = 1, offset = { 0, y } })
    children[#children + 1] = arrow(-r, y, true)
    children[#children + 1] = arrow(r, y, false)
    children[#children + 1] = ui.text(("Ø %d"):format(s), {
      font = din, size = 13, offset = { 0, y }, background = "bg", padding = { 0, 6 },
    })
    -- Quadrant angles at the ends of the center lines.
    children[#children + 1] = label("0°", 0, -s * 0.66, 12)
    children[#children + 1] = label("90°", s * 0.66, -12, 12)
    children[#children + 1] = label("180°", 0, s * 0.66 + 8, 12)
    children[#children + 1] = label("270°", -s * 0.68, -12, 12)
    -- The detail bubble.
    children[#children + 1] = ui.zstack {
      offset = { -r * 0.98, -r * 0.98 },
      ui.circle({ width = 40, height = 40, stroke = "fg", stroke_width = 1.5, color = "bg" }),
      ui.text("A", { font = condensed, size = 22 }),
    }
    return ui.zstack(with({ width = s * 1.5, height = s * 1.5 + 40 }, children))
  end,
})

-- One box of the title block: a small label over a value.
local function box(caption, value, width, height)
  if type(value) == "string" then
    value = ui.text(value, { font = condensed, size = height > 50 and 30 or 18, lines = 1 })
  end
  return ui.zstack {
    width = width, height = height, text_align = "leading", border = "fg", border_width = 1,
    ui.vstack {
      align = "leading", spacing = 2, padding = { 5, 8 },
      ui.text(caption, { font = din, size = 9, tracking = 1.2, opacity = 0.7 }),
      value,
    },
  }
end

locky.widget.define("blueprint.titleblock", {
  description = "An engineering drawing's title block: the drawing, who drew it, the date and time, and the sheet",
  opts = { title = "LOCK SCREEN", width = 460 },
  init = function(self)
    self:every(3600, function(self) self:set({ t = os.time() }) end, { align = true })
  end,
  render = function(self)
    local w = self.opts.width
    local now = self.state.t or os.time()
    local t = os.date("*t", now)
    local days = os.date("*t", os.time({ year = t.year, month = 12, day = 31 })).yday
    local user = locky.sys.user()
    local host = locky.sys.hostname()
    local third = w / 3
    return ui.vstack {
      spacing = -1, border = "fg", border_width = 2,
      box("TITLE", self.opts.title:upper(), w, 62),
      ui.hstack {
        spacing = -1,
        box("DRAWN BY", (user.full_name ~= "" and user.full_name or user.name):upper(), w / 2 + 0.5, 46),
        box("PROJECT", host.name:upper(), w / 2 + 0.5, 46),
      },
      ui.hstack {
        spacing = -1,
        box("DATE", ui.time("yyyy-MM-dd", { font = condensed, size = 18 }), third + 1, 46),
        box("TIME", ui.time("HH:mm:ss", { font = condensed, size = 18, mono = true }), third + 1, 46),
        box("SHEET", ("%d OF %d"):format(t.yday, days), third, 46),
      },
      ui.hstack {
        spacing = -1,
        box("SCALE", "1 : 1", third + 1, 46),
        box("UNITS", "POINTS", third + 1, 46),
        box("REV", locky.sys.os().version, third, 46),
      },
    }
  end,
})

local notes = {
  "ALL TIMES ARE LOCAL.",
  "DO NOT SCALE THE DRAWING.",
  "ENTER THE PASSWORD TO UNLOCK.",
  "BREAK ALL SHARP EDGES. TAKE A BREAK TOO.",
}

locky.widget.define("blueprint.notes", {
  description = "The sheet's general notes",
  opts = { notes = notes, width = 360 },
  render = function(self)
    local lines = { ui.text("GENERAL NOTES", { font = condensed, size = 20, tracking = 1.5 }) }
    for i, note in ipairs(self.opts.notes) do
      lines[#lines + 1] = ui.hstack {
        spacing = 8, align = "top",
        ui.text(("%d."):format(i), { font = din, size = 12, width = 18, text_align = "leading" }),
        ui.text(note, { font = din, size = 12, tracking = 0.6, max_width = self.opts.width }),
      }
    end
    return ui.vstack(with({ align = "leading", spacing = 6 }, lines))
  end,
})
