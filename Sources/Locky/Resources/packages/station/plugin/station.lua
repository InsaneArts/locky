-- Station: a Swiss railway clock (after Hans Hilfiker's 1944 design), with a platform sign, the date, and
-- the next "departure" from herdr.
--
--   station.clock      the clock. opts: size (outer diameter, 560), seconds (true), step (seconds between
--                      second-hand updates, 0.2), sweep (seconds per turn of the second hand, 58.5),
--                      case, dial, ink, second (palette roles or hex), shadow (true: the case and the hands
--                      cast soft shadows), part ("all"; or "dial", "hands", "seconds": see below)
--   station.date       the date, uppercase and tracked. opts: format ("EEEE d MMMM"), size, weight, tracking
--   station.plate      the computer's name on a black sign. opts: text (default: the computer's name), size,
--                      max_width
--   station.departure  the herdr agent that needs you most, one line; hidden when none does or herdr is off.
--                      opts: label ("Next"), size, every (seconds between checks, 5), max_width
local ui = locky.ui
local herdr = require("locky.herdr")

-------------------------------------------------------------------------------
-- The clock
-------------------------------------------------------------------------------

-- The dial, as fractions of the dial's radius, from the railway's own 105-unit drawing (radius 52.5).
local U = 1 / 52.5
local DIAL = {
  mark_end = 48.5 * U,                            -- where every bar ends, near the rim
  hour = { length = 12 * U, width = 3.5 * U },    -- 12 thick bars
  minute = { length = 3.5 * U, width = 1.4 * U }, -- 48 thin ones
  -- Hands: how far the tail reaches behind the center, how far the tip reaches, and the widths there.
  hour_hand = { tail = 12 * U, tip = 32 * U, tail_width = 6.4 * U, tip_width = 5.2 * U },
  minute_hand = { tail = 12 * U, tip = 46 * U, tail_width = 5.2 * U, tip_width = 3.6 * U },
  second_hand = { tail = 16.5 * U, disc = 31.2 * U, disc_size = 10.5 * U, width = 1.5 * U, hub = 2.6 * U },
}

-- A hand that narrows from tail to tip, pointing at 12. There is no polygon view, so the trapezoid is two
-- rectangles as wide as the tip, each tilted by the taper angle so that one long edge lies on a side of the
-- trapezoid; between them they cover it exactly (the ends are off by less than a quarter point). Locky
-- offsets a view before it rotates it around its own center, so each offset is the target center turned
-- back by the tilt. The returned group turns around the dial's center by `angle`.
local function tapered(r, spec, color, angle)
  local tail, tip = spec.tail * r, spec.tip * r
  local half_tail, half_tip = spec.tail_width * r / 2, spec.tip_width * r / 2
  local tilt = math.atan(half_tail - half_tip, tail + tip)
  local length = math.sqrt((half_tail - half_tip) ^ 2 + (tail + tip) ^ 2)
  local width = 2 * half_tip
  local c, s = math.cos(tilt), math.sin(tilt)
  -- Center of the left rectangle: the middle of the left edge, moved half a width inwards.
  local cx = -(half_tail + half_tip) / 2 + width / 2 * c
  local cy = (tail - tip) / 2 + width / 2 * s
  local ox, oy = cx * c + cy * s, -cx * s + cy * c
  local degrees = math.deg(tilt)
  return ui.zstack {
    rotation = angle,
    ui.rect({ width = width, height = length, color = color, offset = { ox, oy }, rotation = degrees }),
    ui.rect({ width = width, height = length, color = color, offset = { -ox, oy }, rotation = -degrees }),
  }
end

local function second_hand(r, color, angle)
  local h = DIAL.second_hand
  local tail, disc, size, width, hub = h.tail * r, h.disc * r, h.disc_size * r, h.width * r, h.hub * r
  return ui.zstack {
    rotation = angle,
    ui.rect({ width = width, height = tail + disc, color = color, offset = { 0, (tail - disc) / 2 } }),
    ui.circle({ width = size, height = size, color = color, offset = { 0, -disc } }),
    ui.circle({ width = hub, height = hub, color = color }),
  }
end

-- The case, the dial, and the 60 bars: built once, then handed back unchanged on every redraw, so
-- SwiftUI skips them and only the hands are drawn again.
local function face(o, r)
  local size = o.size
  local children = {
    -- A soft shadow on the wall, below the case.
    o.shadow and ui.circle({ width = size, height = size, color = "#000000", opacity = 0.2, offset = { 0, size * 0.022 }, blur = size * 0.032 }),
    ui.circle({ width = size, height = size, color = o.case }),
    -- Light from above on the case: lighter at the top, darker at the bottom.
    ui.circle({ width = size, height = size, color = { "#ffffff24", "#ffffff00", "#00000040", angle = 180 } }),
    -- The seam where the dial meets the case.
    ui.circle({ width = 2 * r + size * 0.006, height = 2 * r + size * 0.006, color = "#00000066" }),
    ui.circle({ width = 2 * r, height = 2 * r, color = o.dial }),
    -- The dial sits a little behind the case's rim: a faint shade along its edge.
    ui.circle({ width = 2 * r, height = 2 * r, stroke = "#0000001c", stroke_width = r * 0.03, blur = r * 0.012 }),
  }
  for i = 0, 59 do
    local mark = i % 5 == 0 and DIAL.hour or DIAL.minute
    local length, width = mark.length * r, mark.width * r
    children[#children + 1] = ui.rect({
      width = width, height = length, color = o.ink,
      offset = { 0, -(DIAL.mark_end * r - length / 2) }, rotation = i * 6,
    })
  end
  return ui.zstack(children)
end

-- A hand's shadow on the dial, lit from above: the hand again in black, blurred, a little lower on the
-- screen whatever its angle (the outer group moves it after the hand has turned).
local function shadow(r, hand)
  return ui.zstack { offset = { 0, r * 0.014 }, blur = r * 0.009, opacity = 0.3, hand }
end

local function hour_and_minute(o, r, minute)
  -- The hour hand moves with each jump of the minute hand: half a degree a minute.
  local hour_angle, minute_angle = (minute % 720) * 0.5, (minute % 60) * 6
  return {
    o.shadow and shadow(r, tapered(r, DIAL.hour_hand, "#000000", hour_angle)),
    tapered(r, DIAL.hour_hand, o.ink, hour_angle),
    o.shadow and shadow(r, tapered(r, DIAL.minute_hand, "#000000", minute_angle)),
    tapered(r, DIAL.minute_hand, o.ink, minute_angle),
  }
end

local function seconds(o, r, angle)
  return {
    o.shadow and shadow(r, second_hand(r, "#000000", angle)),
    second_hand(r, o.second, angle),
  }
end

-- part: "all" draws the whole clock. A theme can instead place three widgets at the same spot, "dial",
-- "hands", and "seconds": then the dial never redraws, the hour and minute hands redraw once a minute,
-- and only the small second hand redraws several times a second.
locky.widget.define("station.clock", {
  description = "A Swiss railway clock: the second hand sweeps in 58.5 s, waits at 12, and the minute hand jumps",
  opts = {
    size = 560, seconds = true, step = 0.2, sweep = 58.5, shadow = true, part = "all",
    case = "case", dial = "surface", ink = "fg", second = "accent",
  },
  init = function(self)
    local o = self.opts
    local part = o.part or "all"
    if part == "dial" or (part == "seconds" and not o.seconds) then
      self:set({ ready = true })
      return
    end
    local step = math.max(o.step or 0.2, 0.05)
    local sweep = math.max(math.min(o.sweep or 58.5, 60), 1)
    local sweeping = o.seconds and part ~= "hands"
    -- Lua has whole seconds only. The timer fires on wall-clock multiples of `step`, so counting its calls
    -- since the second last changed gives the fraction.
    local second, calls = nil, 0
    local function tick(self)
      local now = os.time()
      if now ~= second then
        second, calls = now, 0
      else
        calls = calls + 1
      end
      local t = os.date("*t", now)
      local minute = part ~= "seconds" and t.hour * 60 + t.min or 0
      local angle = 0
      if sweeping then
        -- Round the minute in 58.5 s, then wait at 12 for the next minute.
        angle = math.min((t.sec + math.min(calls * step, 1 - step)) / sweep, 1) * 360
        angle = math.floor(angle * 100 + 0.5) / 100
      end
      local s = self.state
      if s.minute ~= minute or s.angle ~= angle then
        self:set({ ready = true, minute = minute, angle = angle })
      end
    end
    -- The minute hand jumps at the full minute, so a clock without a second hand ticks once a minute.
    self:every(sweeping and step or 60, tick, { align = true })
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.ready then
      return nil
    end
    local part = o.part or "all"
    local r = o.size / 2 * 0.94
    local children = {}
    if part == "all" or part == "dial" then
      self._face = self._face or face(o, r)
      children[1] = self._face
    end
    if part == "all" or part == "hands" then
      children[#children + 1] = hour_and_minute(o, r, s.minute)
    end
    if (part == "all" or part == "seconds") and o.seconds then
      children[#children + 1] = seconds(o, r, s.angle)
    end
    -- Every part has the same frame, so parts placed at the same spot line up.
    return ui.zstack { padding = o.size * 0.08, width = o.size, height = o.size, children }
  end,
})

-------------------------------------------------------------------------------
-- The date
-------------------------------------------------------------------------------

locky.widget.define("station.date", {
  description = "The date in uppercase, tracked Helvetica",
  opts = { format = "EEEE d MMMM", size = 17, weight = "medium", tracking = 3.4, color = "fg" },
  render = function(self)
    local o = self.opts
    return ui.time(o.format, {
      size = o.size, weight = o.weight, font = o.font or "Helvetica Neue", case = "upper", tracking = o.tracking,
      color = o.color, numeric = false,
      -- Tracking also follows the last letter; move back by half of it so the line sits centered.
      offset = { o.tracking / 2, 0 },
    })
  end,
})

-------------------------------------------------------------------------------
-- The platform sign
-------------------------------------------------------------------------------

locky.widget.define("station.plate", {
  description = "The computer's name on a black platform sign",
  opts = { size = 19, color = "plate", text_color = "plate_text", max_width = 340 },
  init = function(self)
    local name = self.opts.text or locky.sys.hostname().name
    self:set({ name = name })
  end,
  render = function(self)
    local o, name = self.opts, self.state.name
    if not name or name == "" then
      return nil
    end
    return ui.hstack {
      background = o.color, radius = 7, padding = 4, shadow = 10, shadow_color = "#0000002e",
      ui.hstack {
        padding = { 8, 16 }, border = "#ffffff4d", border_width = 1, radius = 4,
        ui.text(name, { font = "Helvetica Neue", weight = "bold", size = o.size, color = o.text_color, lines = 1, max_width = o.max_width }),
      },
    }
  end,
})

-------------------------------------------------------------------------------
-- The next departure
-------------------------------------------------------------------------------

locky.widget.define("station.departure", {
  description = "The herdr agent that needs you most, as a departure line",
  opts = { label = "Next", size = 15, every = 5, max_width = 560 },
  init = function(self)
    herdr.watch(self, self.opts.every, function(self, data)
      local agent = data and data.need > 0 and data.agents[1] or nil
      local key = agent and table.concat({ agent.kind, agent.title, agent.status, data.need }, "\0") or false
      if key ~= self.state.key then
        self:set({ key = key, agent = agent, more = agent and data.need - 1 or 0 })
      end
    end)
  end,
  render = function(self)
    local o, a = self.opts, self.state.agent
    if not a then
      return nil
    end
    local status = (herdr.words[a.status] or a.status):lower()
    local dot = ui.text("·", { size = o.size, color = "muted" })
    return ui.hstack {
      spacing = 8,
      ui.text(o.label, {
        size = o.size - 4, weight = "bold", case = "upper", tracking = 1.2, color = "surface",
        background = "accent", radius = 3, padding = { 3, 7 },
      }),
      ui.text(a.kind, { size = o.size, weight = "bold", color = "fg", lines = 1 }),
      dot,
      ui.text(a.title, { size = o.size, color = "fg", lines = 1, max_width = o.max_width }),
      dot,
      ui.text(status, { size = o.size, weight = "medium", color = a.status == "blocked" and "accent" or "muted", lines = 1 }),
      self.state.more > 0 and ui.text("+" .. self.state.more, { size = o.size - 2, weight = "medium", color = "muted" }),
    }
  end,
})
