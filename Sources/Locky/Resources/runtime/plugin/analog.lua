-- analog: an analog clock drawn with shapes.
--   opts.style     "minimal" (default), "railway" (Swiss station clock, red second disc), or "braun"
--   opts.size      diameter in points (default 260)
--   opts.seconds   show the second hand (default true)
--   opts.face, opts.hands, opts.ticks, opts.second  colors (palette roles or hex)
local ui = locky.ui

local styles = {
  minimal = { face = "surface", hands = "fg", ticks = "muted", second = "accent", numerals = false },
  railway = { face = "#fafaf8", hands = "#111111", ticks = "#111111", second = "#e2001a", numerals = false },
  braun = { face = "#0e0e0e", hands = "#f2f2f0", ticks = "#f2f2f0", second = "#f2c200", numerals = true },
}

local function hand(length, width, angle, color, tail)
  tail = tail or 0
  return ui.capsule({
    width = width, height = length + tail, color = color,
    offset = { 0, -(length - tail) / 2 }, rotation = angle,
  })
end

locky.widget.define("analog", {
  description = "An analog clock",
  opts = { style = "minimal", size = 260, seconds = true },
  choices = { style = { "minimal", "railway", "braun" } },
  init = function(self)
    self:every(self.opts.seconds and 1 or 60, function(self) self:set({ t = os.time() }) end, { align = true })
  end,
  render = function(self)
    local o = self.opts
    local look = locky.tbl.extend("force", styles[o.style] or styles.minimal, {
      face = o.face, hands = o.hands, ticks = o.ticks, second = o.second,
    })
    local now = os.date("*t", self.state.t or os.time())
    local r = o.size / 2
    local children = { ui.circle({ width = o.size, height = o.size, color = look.face, shadow = o.style == "railway" and 20 or nil }) }
    for i = 0, 59 do
      local hour = i % 5 == 0
      if hour or o.style ~= "braun" then
        local length = hour and r * (o.style == "railway" and 0.24 or o.style == "braun" and 0.07 or 0.12) or r * 0.055
        local width = hour and r * (o.style == "railway" and 0.07 or 0.025) or r * 0.02
        children[#children + 1] = ui.rect({
          width = width, height = length, color = look.ticks, opacity = hour and 1 or 0.6,
          offset = { 0, -(r * 0.94 - length / 2) }, rotation = i * 6,
        })
      end
    end
    if look.numerals then
      for h = 1, 12 do
        local angle = math.rad(h * 30)
        children[#children + 1] = ui.text(h, {
          size = o.size * 0.075, weight = "medium", font = "Helvetica Neue", color = look.hands,
          offset = { math.sin(angle) * r * 0.7, -math.cos(angle) * r * 0.7 },
        })
      end
    end
    local minutes = now.min + now.sec / 60
    local hours = (now.hour % 12) + minutes / 60
    children[#children + 1] = hand(r * 0.58, r * 0.085, hours * 30, look.hands, r * 0.18)
    children[#children + 1] = hand(r * 0.86, r * 0.06, minutes * 6, look.hands, r * 0.18)
    if o.seconds then
      local angle = now.sec * 6
      children[#children + 1] = hand(r * 0.6, r * 0.02, angle, look.second, r * 0.28)
      if o.style == "railway" then
        local a = math.rad(angle)
        children[#children + 1] = ui.circle({ width = r * 0.21, height = r * 0.21, color = look.second, offset = { math.sin(a) * r * 0.6, -math.cos(a) * r * 0.6 } })
      end
    end
    children[#children + 1] = ui.circle({ width = r * 0.06, height = r * 0.06, color = o.seconds and look.second or look.hands })
    return ui.zstack(children)
  end,
})
