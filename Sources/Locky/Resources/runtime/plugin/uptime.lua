-- uptime: how long the Mac has been on, such as "3d 4h".
--   opts.label (default "Up"; false hides it), opts.size
local ui = locky.ui

locky.widget.define("uptime", {
  description = "How long the Mac has been on",
  opts = { label = "Up", size = 13 },
  init = function(self)
    self:every(60, function(self) self:set({ seconds = locky.sys.uptime() }) end)
  end,
  render = function(self)
    local o, s = self.opts, self.state.seconds
    if not s then
      return nil
    end
    local d, h, m = s // 86400, s % 86400 // 3600, s % 3600 // 60
    local text = d > 0 and ("%dd %dh"):format(d, h) or ("%dh %02dm"):format(h, m)
    return ui.hstack {
      spacing = 6,
      o.label and ui.text(o.label, { size = o.size, color = "muted" }),
      ui.text(text, { size = o.size, weight = "medium", mono = true, color = o.color }),
    }
  end,
})
