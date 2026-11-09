-- Primary Flight Display chrome: an artificial horizon (sky over earth, pitch ladder, boresight) and a
-- vertical "tape" gauge, drawn with plain shapes. For the Glass Cockpit theme.
local ui = locky.ui

locky.widget.define("pfd.horizon", {
  description = "Artificial horizon",
  opts = { sky = "#1e6fa8", earth = "#6b4a2b", line = "#ffffff", bug = "#ff36c8", w = 600, h = 380 },
  render = function(self)
    local o = self.opts
    local w, h = o.w, o.h
    local function pitch(dy, len)
      return ui.rect { width = len, height = 2, color = o.line, opacity = 0.85, offset = { 0, dy } }
    end
    return ui.zstack {
      width = w, height = h, clip = true, radius = 10, border = o.bug, border_width = 2,
      ui.rect { width = w, height = h / 2, color = o.sky, offset = { 0, -h / 4 } },
      ui.rect { width = w, height = h / 2, color = o.earth, offset = { 0, h / 4 } },
      ui.rect { width = w, height = 2.5, color = o.line },                          -- horizon
      pitch(-80, 150), pitch(-45, 90), pitch(45, 90), pitch(80, 150),               -- pitch ladder
      ui.polygon { points = { { 0.5, 0.42 }, { 0.44, 0.52 }, { 0.56, 0.52 } }, color = o.bug, width = 60, height = 60 }, -- sky pointer
      ui.hstack {                                                                    -- boresight
        spacing = 12,
        ui.rect { width = 44, height = 4, color = "#ffb000" },
        ui.dot { size = 9, color = "#ffb000" },
        ui.rect { width = 44, height = 4, color = "#ffb000" },
      },
    }
  end,
})

-- A vertical tape: a labeled scale with a value box, like an airspeed/altitude strip.
locky.widget.define("pfd.tape", {
  description = "PFD vertical tape",
  opts = { label = "SPD", source = "cpu", color = "#35e06a", w = 92, h = 300 },
  init = function(self)
    self:every(2, function(self)
      local src, v = self.opts.source, 0
      if src == "cpu" then v = locky.sys.cpu().usage
      elseif src == "memory" then v = locky.sys.memory().percent
      elseif src == "battery" then v = (locky.sys.battery() or {}).percent or 0 end
      self:set({ value = v })
    end)
  end,
  render = function(self)
    local o = self.opts
    o = { label = o.label, color = o.color, w = o.w, h = o.h, value = self.state.value or 0 }
    local ticks = {}
    for i = 0, 8 do ticks[#ticks + 1] = ui.rect { width = (i % 2 == 0) and 18 or 10, height = 2, color = "#8fa3b0", opacity = 0.6 } end
    return ui.vstack {
      spacing = 6, align = "center", width = o.w, height = o.h,
      ui.text(o.label, { size = 12, color = "#8fa3b0", case = "upper", tracking = 2, mono = true }),
      ui.zstack {
        width = o.w, height = o.h - 44, border = "#2a3a44", border_width = 1, radius = 4, background = "#0a1016",
        ui.vstack { spacing = 20, align = "trailing", width = o.w - 16, ui.each(ticks, function(t) return t end) },
        ui.text(tostring(math.floor(o.value + 0.5)), { size = 22, weight = "bold", mono = true, color = o.color,
          background = "#0a1016", padding = { 3, 8 }, radius = 3, border = o.color, border_width = 1 }),
      },
    }
  end,
})
