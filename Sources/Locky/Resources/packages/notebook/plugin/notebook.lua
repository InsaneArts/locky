-- The Notebook theme's widgets: a to-do list written by hand, a sticky note that says you will be back, and the
-- weather as a doodle.
local ui = locky.ui
local weather = require("locky.weather")
local hand, marker = "Bradley Hand", "Marker Felt"

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Items from a todo.txt ("x " marks one done, "(A) " gives a priority) or from Markdown task lines ("- [ ] ...").
-- Open items come first, by priority; done ones last.
local function parse(text, markdown)
  local items = {}
  for line in text:gmatch("[^\r\n]+") do
    local mark, task = line:match("^%s*[-*+]%s+%[(.)%]%s+(.+)$")
    local done
    if mark then
      done = mark ~= " "
    elseif not markdown then
      done, task = line:match("^x%s") ~= nil, line:gsub("^x%s+", "")
    end
    if task then
      task = task:gsub("^%d%d%d%d%-%d%d%-%d%d%s+", ""):gsub("^%d%d%d%d%-%d%d%-%d%d%s+", "")
      local priority = task:match("^%((%u)%)%s")
      task = trim(task:gsub("^%(%u%)%s+", ""))
      if task ~= "" and not task:match("^#") then
        items[#items + 1] = { text = task, done = done, priority = priority or "~", order = #items }
      end
    end
  end
  table.sort(items, function(a, b)
    if a.done ~= b.done then return not a.done end
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.order < b.order
  end)
  return items
end

local starter = {
  { text = "make a todo.txt in your home folder" },
  { text = "one task on each line" },
  { text = "start a line with x when it is done", done = true },
}

locky.widget.define("notebook.todo", {
  description = "Your to-do list from todo.txt or a Markdown file, written by hand",
  opts = { path = "~/todo.txt", rows = 7, title = "To do", size = 24, color = "ink", width = 420 },
  init = function(self)
    self:every(60, function(self)
      local text = locky.fs.read(locky.fs.expand(self.opts.path))
      self:set({ items = text and parse(text, self.opts.path:match("%.md$") ~= nil) or starter, mine = text ~= nil })
    end)
  end,
  render = function(self)
    local o = self.opts
    local items = self.state.items or {}
    local rows = {
      ui.vstack {
        align = "leading", spacing = 0,
        ui.text(o.title, { font = marker, size = o.size * 1.3, color = o.color }),
        ui.capsule({ width = 110, height = 3, color = "pen", rotation = -1.5, opacity = 0.85 }),
      },
    }
    -- Privacy mode shows how many, not what: unless the list is the starter one.
    if locky.config.privacy == true and self.state.mine then
      local open = 0
      for _, item in ipairs(items) do
        if not item.done then open = open + 1 end
      end
      rows[#rows + 1] = ui.text(("%d %s left"):format(open, open == 1 and "thing" or "things"), { font = hand, size = o.size, color = o.color })
    else
      for i, item in ipairs(items) do
        if i > o.rows then
          rows[#rows + 1] = ui.text(("+ %d more"):format(#items - o.rows), { font = hand, size = o.size * 0.8, color = "muted" })
          break
        end
        rows[#rows + 1] = ui.hstack {
          spacing = 12,
          ui.zstack {
            ui.rect({ width = o.size * 0.7, height = o.size * 0.7, stroke = o.color, stroke_width = 1.6, radius = 2, rotation = (i % 3 - 1) * 3 }),
            item.done and ui.symbol("checkmark", { size = o.size * 0.8, weight = "bold", color = "pen", offset = { 3, -4 } }) or nil,
          },
          ui.text(item.text, { font = hand, size = o.size, color = item.done and "muted" or o.color, lines = 1, max_width = o.width }),
        }
      end
    end
    rows.align, rows.spacing = "leading", o.size * 0.45
    return ui.vstack(rows)
  end,
})

locky.widget.define("notebook.sticky", {
  description = "A sticky note: back soon, and since when",
  opts = { text = "Back soon!", size = 30, color = "#3a2f00", paper = "#ffe873", rotation = -4 },
  init = function(self)
    self.state.since = os.time()
  end,
  render = function(self)
    local o = self.opts
    local hour24 = locky.date.locale().hour24
    local since = locky.date.format(hour24 and "HH:mm" or "h:mm a", self.state.since)
    return ui.vstack {
      spacing = 10, width = o.size * 7, height = o.size * 6, background = o.paper, shadow = 10,
      shadow_color = "#00000040", rotation = o.rotation,
      ui.text(o.text, { font = marker, size = o.size, color = o.color }),
      ui.text("out since " .. since, { font = hand, size = o.size * 0.7, color = o.color }),
    }
  end,
})

locky.widget.define("notebook.weather", {
  description = "The weather, written in the margin",
  opts = { size = 24, color = "ink" },
  init = function(self)
    weather.watch(self, self.opts, function(self, data)
      self:set({ data = data })
    end)
  end,
  render = function(self)
    local w, o = self.state.data, self.opts
    if not w then
      return nil
    end
    return ui.hstack {
      spacing = 10, rotation = -2,
      ui.symbol(w.symbol, { size = o.size * 1.3, color = o.color, weight = "light" }),
      ui.text(("%d° and %s"):format(w.temp, w.condition:lower()), { font = hand, size = o.size, color = o.color }),
    }
  end,
})
