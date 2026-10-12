-- keyboard: the selected keyboard layout, so you know what you are about to type in.
--   opts.style   "name" (default, such as "U.S."), or "code" (such as "EN")
local ui = locky.ui

locky.widget.define("keyboard", {
  description = "The keyboard layout",
  opts = { style = "name", size = 12 },
  init = function(self)
    self:every(1, function(self)
      local k = locky.sys.keyboard()
      if k.id ~= self.state.id then
        self:set({ id = k.id, name = k.name, language = k.language })
      end
    end)
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.name then
      return nil
    end
    local label = o.style == "code" and (s.language ~= "" and s.language or s.name):sub(1, 2):upper() or s.name
    return ui.hstack {
      spacing = 6,
      ui.symbol("keyboard", { size = o.size, color = "muted" }),
      ui.text(label, { size = o.size, weight = "medium", mono = o.style == "code", color = o.color }),
    }
  end,
})
