-- nerdclock: the time for people who read hex: a binary clock, the time as a hex color, Unix time, or Swatch .beat.
--   opts.style     "binary" (default: a column of lit dots for each digit of HH MM SS), "hex" (#HHMMSS and its
--                  color), "unix" (seconds since 1970), or "beat" (Swatch Internet Time)
--   opts.seconds   false leaves the seconds out of "binary" and ticks once a minute
--   opts.size, opts.color (lit dots), opts.off (unlit dots, default "surface")
local ui = locky.ui
local time = require("locky.time")

locky.widget.define("nerdclock", {
  description = "A binary clock, hex time, Unix time, or .beat",
  opts = { style = "binary", seconds = true, size = 14 },
  choices = { style = { "binary", "hex", "unix", "beat" } },
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
