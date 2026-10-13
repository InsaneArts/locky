-- uptime: how long the Mac has been on, such as "3d 4h".
--   Families: inline ("Up 3d 4h"), circular.
--   opts.label (default "Up"; false hides it), opts.size
local ui = locky.ui

locky.widget.define("uptime", {
  description = "How long the Mac has been on",
  opts = { label = "Up", size = 13 },
  families = { "inline", "circular" },
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
    if self.family == "inline" then
      return ui.hstack {
        spacing = 4,
        ui.symbol("power", ui.font("subheadline", { weight = "semibold" })),
        ui.text((o.label and (o.label .. " ") or "") .. text, ui.font("subheadline", { mono = true, lines = 1 })),
      }
    elseif self.family then
      return ui.vstack {
        spacing = 2,
        ui.symbol("power", { size = 17, weight = "semibold" }),
        ui.text(text, { size = #text > 6 and 13 or 15, weight = "semibold", mono = true }),
      }
    end
    return ui.hstack {
      spacing = 6,
      o.label and ui.text(o.label, { size = o.size, color = "muted" }),
      ui.text(text, { size = o.size, weight = "medium", mono = true, color = o.color }),
    }
  end,
})
