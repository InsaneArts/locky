-- keyboard: the selected keyboard layout, so you know what you are about to type in.
--   Families: inline (the symbol and the name), circular (the symbol and the code).
--   opts.style   "name" (default, such as "U.S."), or "code" (such as "EN")
local ui = locky.ui

locky.widget.define("keyboard", {
  description = "The keyboard layout",
  opts = { style = "name", size = 12 },
  choices = { style = { "name", "code" } },
  families = { "inline", "circular" },
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
    local code = (s.language ~= "" and s.language or s.name):sub(1, 2):upper()
    local label = o.style == "code" and code or s.name
    if self.family == "inline" then
      return ui.hstack { spacing = 4, ui.symbol("keyboard", ui.font("subheadline")), ui.text(s.name, ui.font("subheadline", { lines = 1 })) }
    elseif self.family then
      return ui.vstack {
        spacing = 1,
        ui.symbol("keyboard", { size = 16, weight = "medium" }),
        ui.text(code, { size = 20, weight = "semibold" }),
      }
    end
    return ui.hstack {
      spacing = 6,
      ui.symbol("keyboard", { size = o.size, color = "muted" }),
      ui.text(label, { size = o.size, weight = "medium", mono = o.style == "code", color = o.color }),
    }
  end,
})
