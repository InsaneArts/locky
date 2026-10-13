-- greeting: "Good evening, Alex."
--   Families: inline (the greeting with the part of the day's symbol), rectangular (today's date over it).
--   opts.name     the name to use (default: the user's first name, none in privacy mode); false leaves it out
--   opts.size, opts.weight, opts.font, opts.design, opts.color
local ui = locky.ui

local function part_of_day(hour)
  if hour < 5 then return "Good night" end
  if hour < 12 then return "Good morning" end
  if hour < 18 then return "Good afternoon" end
  return "Good evening"
end

local function symbol(hour)
  if hour < 5 then return "moon.stars.fill" end
  if hour < 12 then return "sunrise.fill" end
  if hour < 18 then return "sun.max.fill" end
  return "sunset.fill"
end

locky.widget.define("greeting", {
  description = "A greeting with your name",
  opts = { size = 22, weight = "medium" },
  families = { "inline", "rectangular" },
  init = function(self)
    self:every(60, function(self) self:set({ hour = os.date("*t").hour }) end, { align = true })
  end,
  render = function(self)
    local o = self.opts
    local name = o.name
    if name == nil and locky.config.privacy ~= true then
      name = (locky.sys.user().full_name:match("^(%S+)")) or locky.sys.user().name
    end
    local hour = self.state.hour or os.date("*t").hour
    if self.family == "inline" then
      return ui.hstack {
        spacing = 4,
        ui.symbol(symbol(hour), ui.font("subheadline")),
        ui.text(part_of_day(hour) .. (name and (", " .. name) or ""), ui.font("subheadline", { lines = 1 })),
      }
    elseif self.family then
      return ui.vstack {
        spacing = 1, align = "leading", fill = "both",
        ui.hstack { spacing = 5, ui.symbol(symbol(hour), ui.font("headline")), ui.time("skeleton:EEEEdMMM", ui.font("headline", { lines = 1 })) },
        ui.text(part_of_day(hour) .. (name and "," or ""), ui.font("title2", { weight = "semibold", lines = 1 })),
        name and ui.text(name, ui.font("title2", { weight = "semibold", color = "muted", lines = 1 })),
      }
    end
    local text = part_of_day(hour) .. (name and (", " .. name) or "") .. (o.period == false and "" or ".")
    return ui.text(text, { size = o.size, weight = o.weight, font = o.font, design = o.design, color = o.color, italic = o.italic, case = o.case, tracking = o.tracking })
  end,
})
