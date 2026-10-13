-- nerdclock: the time for people who read hex: a binary clock, the time as a hex color, Unix time, or Swatch .beat.
--   opts.style     "binary" (default: a column of lit dots for each digit of HH MM SS), "hex" (#HHMMSS and its
--                  color), "unix" (seconds since 1970), or "beat" (Swatch Internet Time)
--   opts.seconds   false leaves the seconds out of "binary" and ticks once a minute
--   opts.size, opts.color (lit dots), opts.off (unlit dots, default "surface")
--   Families: circular, rectangular, small, medium. Each style keeps its look: lit dots, the color, or the number.
local ui = locky.ui
local time = require("locky.time")

-- The binary clock: a pair of 4-dot columns for each of hours, minutes, and (with seconds) seconds.
-- labels puts each pair's decimal digits below it.
local function dots(t, seconds, dot, lit, off, labels)
  local groups = {}
  for _, value in ipairs({ t.hour, t.min, seconds and t.sec or nil }) do
    local text = ("%02d"):format(value)
    local columns = {}
    for i = 1, 2 do
      local bits = time.bits(tonumber(text:sub(i, i)), 4)
      local column = {}
      for b = 1, 4 do
        column[b] = ui.dot({ size = dot, color = bits[b] and lit or off })
      end
      columns[i] = ui.vstack { spacing = dot * 0.35, column }
    end
    groups[#groups + 1] = ui.vstack {
      spacing = 6,
      ui.hstack { spacing = dot * 0.35, columns },
      labels and ui.text(text, ui.font("caption", { weight = "semibold", color = "muted", mono = true })),
    }
  end
  return ui.hstack { spacing = dot * 0.9, align = "top", groups }
end

local function family(f, o, now)
  local t = os.date("*t", now)
  local lock = f == "circular" or f == "rectangular"
  if o.style ~= "hex" and o.style ~= "unix" and o.style ~= "beat" then
    local lit, off = lock and "fg" or (o.color or "accent"), lock and "#ffffff33" or "#ffffff1f"
    local clock = ("%02d:%02d:%02d"):format(t.hour, t.min, t.sec)
    if f == "circular" then
      return dots(t, false, 8, lit, off)
    elseif f == "rectangular" then
      return ui.hstack {
        spacing = 0, fill = "both",
        ui.vstack {
          spacing = 0, align = "leading",
          ui.text("Binary", ui.font("headline")),
          ui.text(clock, ui.font("subheadline", { weight = "medium", color = "muted", mono = true })),
        },
        ui.spacer(),
        dots(t, true, 10, lit, off),
      }
    elseif f == "small" then
      return ui.vstack {
        spacing = 0, align = "leading", fill = "both",
        ui.text("Binary", ui.font("headline")),
        ui.spacer(),
        ui.hstack { dots(t, true, 15, lit, off, true), fill = "width" },
      }
    end
    return ui.hstack {
      spacing = 0, fill = "both",
      ui.vstack {
        spacing = 0, align = "leading", fill = "height",
        ui.text("Binary", ui.font("headline")),
        ui.spacer(),
        ui.text(clock, ui.font("title", { weight = "semibold", mono = true })),
        ui.text("Hours, minutes, seconds", ui.font("footnote", { color = "muted" })),
      },
      ui.spacer(),
      dots(t, true, 18, lit, off, true),
    }
  end
  local hex = ("#%02d%02d%02d"):format(t.hour, t.min, t.sec)
  local beat = time.beat(now)
  local label, value, note = table.unpack(({
    hex = { "Hex Time", hex, "The time as a color" },
    unix = { "Unix Time", tostring(now), "Seconds since 1970" },
    beat = { "Internet Time", beat, "Swatch .beats" },
  })[o.style])
  local day = tonumber(beat:sub(2)) / 1000
  local function visual(size)
    if o.style == "hex" then
      return ui.circle({ width = size, height = size, color = hex, stroke = "border", stroke_width = 1 })
    elseif o.style == "beat" then
      return ui.gauge(day, { style = "capacity", size = size, color = lock and "fg" or (o.color or "accent") })
    end
  end
  if f == "circular" then
    if o.style == "unix" then
      return ui.vstack {
        spacing = -2,
        ui.text(value:sub(1, 5), { size = 15, weight = "semibold", mono = true }),
        ui.text(value:sub(6), { size = 15, weight = "semibold", mono = true }),
      }
    end
    return ui.zstack {
      visual(64),
      o.style == "beat" and ui.text(value, { size = 15, weight = "semibold", mono = true }),
    }
  end
  local sizes = { unix = { 22, 20, 48 }, hex = { 22, 28, 40 }, beat = { 22, 44, 64 } }
  local size = sizes[o.style]
  if f == "rectangular" then
    return ui.vstack {
      spacing = 0, align = "leading", fill = "both",
      ui.text(label, ui.font("headline")),
      ui.text(value, { size = size[1], weight = "semibold", mono = true, lines = 1 }),
      ui.text(note, ui.font("subheadline", { color = "muted", lines = 1 })),
    }
  elseif f == "small" then
    return ui.vstack {
      spacing = 0, align = "leading", fill = "both",
      ui.text(label, ui.font("headline")),
      ui.spacer(),
      o.style == "hex" and ui.hstack { visual(44), padding = { 0, 0, 8, 0 } },
      ui.text(value, { size = size[2], weight = "semibold", mono = true, lines = 1 }),
      ui.text(note, ui.font("footnote", { color = "muted", lines = 1 })),
    }
  end
  return ui.hstack {
    spacing = 16, fill = "both",
    ui.vstack {
      spacing = 0, align = "leading", fill = "height",
      ui.text(label, ui.font("headline")),
      ui.spacer(),
      ui.text(value, { size = size[3], weight = "semibold", mono = true, lines = 1 }),
      ui.text(note, ui.font("subheadline", { color = "muted", lines = 1 })),
    },
    ui.spacer(),
    visual(100),
  }
end

locky.widget.define("nerdclock", {
  description = "A binary clock, hex time, Unix time, or .beat",
  opts = { style = "binary", seconds = true, size = 14 },
  choices = { style = { "binary", "hex", "unix", "beat" } },
  families = { "circular", "rectangular", "small", "medium" },
  init = function(self)
    local o = self.opts
    local every = (o.style == "binary" and o.seconds == false) and 60 or (o.style == "beat" and 86.4 / 4 or 1)
    self:every(every, function(self)
      self:set({ now = os.time() })
    end, { align = every >= 1 })
  end,
  render = function(self)
    local o, now = self.opts, self.state.now
    if not now then
      return nil
    end
    if self.family == "circular" or self.family == "rectangular" or self.family == "small" or self.family == "medium" then
      return family(self.family, o, now)
    end
    local s = o.size
    local t = os.date("*t", now)
    if o.style == "unix" then
      return ui.text(tostring(now), { size = s * 2, weight = "medium", mono = true, color = o.color })
    elseif o.style == "beat" then
      return ui.text(time.beat(now), { size = s * 2, weight = "medium", mono = true, color = o.color })
    elseif o.style == "hex" then
      local hex = ("#%02d%02d%02d"):format(t.hour, t.min, t.sec)
      return ui.hstack {
        spacing = s,
        ui.circle({ width = s * 2.4, height = s * 2.4, color = hex, stroke = "border", stroke_width = 1 }),
        ui.text(hex, { size = s * 2, weight = "medium", mono = true, color = o.color }),
      }
    end
    local digits = ("%02d%02d"):format(t.hour, t.min) .. (o.seconds == false and "" or ("%02d"):format(t.sec))
    local columns = {}
    for i = 1, #digits do
      local bits = time.bits(tonumber(digits:sub(i, i)), 4)
      local dots = {}
      for b = 1, 4 do
        dots[b] = ui.dot({ size = s, color = bits[b] and (o.color or "accent") or (o.off or "surface") })
      end
      columns[#columns + 1] = ui.vstack { spacing = s * 0.45, dots }
      if i % 2 == 0 and i < #digits then
        columns[#columns + 1] = ui.spacer()
      end
    end
    return ui.hstack { spacing = s * 0.45, width = (#digits + 1) * s * 1.6, columns }
  end,
})
