-- away: when the screen locked, how long ago, and wrong passwords since, like hyprlock's $FAIL and $ATTEMPTS.
--   opts.style   "line" (default) or "stack"; opts.size, opts.color
local ui = locky.ui

local function span(seconds)
  local m = seconds // 60
  if m < 1 then
    return "just now"
  elseif m < 60 then
    return m .. " min ago"
  end
  return ("%d h %02d min ago"):format(m // 60, m % 60)
end

locky.widget.define("away", {
  description = "When the screen locked, and wrong passwords since",
  opts = { style = "line", size = 13 },
  choices = { style = { "line", "stack" } },
  init = function(self)
    self.state.since, self.state.failed = os.time(), 0
    self:on("auth_failed", function(self)
      self:set({ failed = self.state.failed + 1 })
    end)
    self:every(60, function(self)
      self:set({ now = os.time() })
    end, { align = true })
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.now then
      return nil
    end
    local locked = ("Locked at %s · %s"):format(locky.date.format("time", s.since), span(s.now - s.since))
    local failed = s.failed > 0 and ui.hstack {
      spacing = 5,
      ui.symbol("exclamationmark.triangle.fill", { size = o.size, color = "danger" }),
      ui.text(("%d wrong password%s"):format(s.failed, s.failed == 1 and "" or "s"), { size = o.size, color = "danger" }),
    }
    if o.style == "stack" then
      return ui.vstack { spacing = 4, align = "leading", ui.text(locked, { size = o.size, color = o.color or "muted" }), failed }
    end
    return ui.hstack { spacing = 12, ui.text(locked, { size = o.size, color = o.color or "muted" }), failed }
  end,
})
