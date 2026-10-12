-- greeting: "Good evening, Alex."
--   opts.name     the name to use (default: the user's first name, none in privacy mode); false leaves it out
--   opts.size, opts.weight, opts.font, opts.design, opts.color
local ui = locky.ui

local function part_of_day(hour)
  if hour < 5 then return "Good night" end
  if hour < 12 then return "Good morning" end
  if hour < 18 then return "Good afternoon" end
  return "Good evening"
end

locky.widget.define("greeting", {
  description = "A greeting with your name",
  opts = { size = 22, weight = "medium" },
  init = function(self)
    self:every(60, function(self) self:set({ hour = os.date("*t").hour }) end, { align = true })
  end,
  render = function(self)
    local o = self.opts
    local name = o.name
    if name == nil and not locky.config.privacy then
      name = (locky.sys.user().full_name:match("^(%S+)")) or locky.sys.user().name
    end
    local text = part_of_day(self.state.hour or os.date("*t").hour) .. (name and (", " .. name) or "") .. (o.period == false and "" or ".")
    return ui.text(text, { size = o.size, weight = o.weight, font = o.font, design = o.design, color = o.color, italic = o.italic, case = o.case, tracking = o.tracking })
  end,
})
