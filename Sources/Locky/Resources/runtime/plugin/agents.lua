-- agents: coding agents from herdr (https://herdr.dev): who needs you, who is working.
--   opts.style     "list" (default), "summary" (one line of counts), "dots" (one dot per agent), "board" (a
--                  departures-style table)
--   opts.rows      most agents listed (default 4)
--   opts.title     header text (default "Agents"); false hides the header
--   opts.offline   text when herdr is not running; false hides the widget then
--   opts.every     seconds between checks (default 3)
--   Families: circular (how many need you), rectangular, inline, small, medium, large (lists like Apple's
--   Reminders).
local ui = locky.ui

local herdr = require("locky.herdr")
local colors, words = herdr.colors, herdr.words

-- "workspace · Kind". In privacy mode the workspace is empty and the title is the kind: the status then.
local function detail(a)
  local parts = {}
  if a.workspace ~= "" then
    parts[#parts + 1] = a.workspace
  end
  if a.kind ~= a.title then
    parts[#parts + 1] = a.kind
  end
  return #parts > 0 and table.concat(parts, " · ") or words[a.status]
end

-- Apple's layouts for each family. data is false when herdr is not running.
local function family(f, data, o)
  local tint = o.color or "accent"
  local c = data and data.counts
  local total = data and #data.agents or 0
  -- The count that leads, and its name: who needs you, else who works, else everyone.
  local count, label = 0, "Agents"
  if data and data.need > 0 then
    count, label = data.need, "Need You"
  elseif data and c.working > 0 then
    count, label = c.working, "Working"
  elseif data then
    count = total
  end
  local empty = not data and (o.offline or "herdr is not running") or total == 0 and "No agents running" or nil
  local parts = {}
  if data and data.need > 0 then
    parts[#parts + 1] = data.need .. " need you"
  end
  if data and c.working > 0 then
    parts[#parts + 1] = c.working .. " working"
  end
  local summary = empty or (#parts > 0 and table.concat(parts, " · ") or "Nothing needs you")
  if f == "inline" then
    return ui.hstack { spacing = 4, ui.symbol("terminal", ui.font("subheadline")), ui.text(summary, ui.font("subheadline", { lines = 1 })) }
  elseif f == "circular" then
    if empty or count == 0 then
      return ui.symbol(empty and "terminal" or "checkmark", { size = 26, weight = "medium", opacity = empty and 0.6 or 1 })
    end
    return ui.vstack {
      spacing = 0,
      ui.symbol(data.need > 0 and "hand.raised.fill" or "terminal.fill", { size = 14, weight = "medium" }),
      ui.text(count, { size = 24, weight = "semibold", mono = true }),
    }
  elseif f == "rectangular" then
    return ui.vstack {
      spacing = 1, align = "leading", fill = "both",
      ui.hstack { spacing = 5, ui.symbol("terminal.fill", ui.font("headline")), ui.text("Agents", ui.font("headline")) },
      empty and ui.text(empty, ui.font("subheadline", { color = "muted", lines = 2 })),
      not empty and ui.text(data.need > 0 and (data.need .. " need you") or "Nothing needs you", ui.font("subheadline", { lines = 1 })),
      not empty and ui.text(c.working > 0 and (c.working .. " working") or (total .. " idle"), ui.font("subheadline", { color = "muted", lines = 1 })),
    }
  end
  -- Reminders' list icon: a symbol on a tinted circle.
  local icon = ui.zstack {
    ui.circle({ color = tint, width = 28, height = 28 }),
    ui.symbol("terminal.fill", { size = 13, weight = "semibold", color = "#ffffff" }),
  }
  local small = f == "small"
  local list = {}
  for i = 1, math.min(f == "large" and 5 or 3, total) do
    list[i] = data.agents[i]
  end
  local more = total - #list
  local function row(a, i)
    local dot = ui.dot({ size = small and 7 or 9, color = colors[a.status] or "muted", glow = a.status == "blocked", opacity = a.status == "idle" and 0.5 or 1 })
    if small then
      return ui.hstack { spacing = 7, dot, ui.text(a.title, ui.font("footnote", { weight = "medium", lines = 1 })), ui.spacer() }
    end
    return ui.vstack {
      spacing = 0, align = "leading", fill = "width",
      i > 1 and ui.divider(),
      ui.hstack {
        spacing = 10, padding = { f == "large" and 6 or 3, 0 },
        dot,
        ui.vstack {
          spacing = 0, align = "leading",
          ui.text(a.title, ui.font("subheadline", { weight = "semibold", lines = 1 })),
          ui.text(detail(a), ui.font("footnote", { color = "muted", lines = 1 })),
        },
        ui.spacer(),
      },
    }
  end
  local rows = empty and ui.vstack {
    spacing = 0, fill = "both",
    ui.text(empty, ui.font(small and "footnote" or "subheadline", { weight = "medium", color = "muted", text_align = "center", lines = 2 })),
  } or ui.vstack {
    spacing = small and 5 or 0, align = "leading", fill = "width",
    ui.each(list, row),
    more > 0 and f == "large" and ui.text(more .. " more", ui.font("footnote", { weight = "medium", color = "muted", padding = { 4, 0, 0, 19 } })),
  }
  local number = ui.text(empty and "" or count, ui.font(small and "title" or "large_title", { weight = "bold", mono = true }))
  local name = ui.text(label, ui.font(small and "subheadline" or "headline", { weight = "semibold", color = tint, lines = 1 }))
  if small or empty then
    return ui.vstack {
      spacing = 0, align = "leading", fill = "both",
      ui.hstack { align = "top", icon, ui.spacer(), number },
      name,
      ui.spacer(),
      rows,
      ui.spacer(),
    }
  elseif f == "medium" then
    return ui.hstack {
      spacing = 14, fill = "both", align = "top",
      ui.vstack { spacing = 0, align = "leading", width = 96, fill = "height", icon, ui.spacer(), number, name },
      rows,
    }
  end
  return ui.vstack {
    spacing = 0, align = "leading", fill = "both",
    ui.hstack { align = "top", icon, ui.spacer(), number },
    name,
    ui.text(empty and "" or summary, ui.font("footnote", { weight = "medium", color = "muted", padding = { 0, 0, 10, 0 } })),
    empty and ui.spacer(),
    rows,
    ui.spacer(),
  }
end

locky.widget.define("agents", {
  description = "herdr coding agents: blocked, done, and working",
  card = true,
  families = { "circular", "rectangular", "inline", "small", "medium", "large" },
  opts = { style = "list", rows = 4, title = "Agents", offline = "herdr is not running", every = 3, size = 13 },
  choices = { style = { "list", "summary", "dots", "board" } },
  init = function(self)
    herdr.watch(self, self.opts.every, function(self, data)
      self:set({ data = data })
    end)
  end,
  render = function(self)
    local o, data = self.opts, self.state.data
    if data == nil then
      return nil
    end
    if self.family then
      return family(self.family, data, o)
    end
    if data == false then
      return o.offline and ui.text(o.offline, { size = o.size, color = "muted" }) or nil
    end
    local c, need = data.counts, data.need
    local summary = ("%d need you · %d working"):format(need, c.working)

    if o.style == "summary" then
      return ui.hstack {
        spacing = 8,
        ui.dot({ size = 8, color = c.blocked > 0 and "warning" or need > 0 and "success" or "muted", glow = c.blocked > 0 }),
        ui.text(summary, { size = o.size, weight = "medium" }),
      }
    end

    if o.style == "dots" then
      return ui.hstack {
        spacing = 6,
        ui.each(data.agents, function(a)
          return ui.dot({ size = o.dot or 10, color = colors[a.status] or "muted", glow = a.status == "blocked", opacity = a.status == "idle" and 0.35 or 1 })
        end),
      }
    end

    local rows = {}
    for i = 1, math.min(o.rows, #data.agents) do
      local a = data.agents[i]
      if o.style ~= "board" and (a.status == "working" or a.status == "idle") and i > need then
        break
      end
      rows[#rows + 1] = a
    end

    if o.style == "board" then
      return ui.vstack {
        align = "leading", spacing = 6,
        o.title and ui.text(o.title, { size = o.size, weight = "bold", color = "accent", case = "upper", tracking = 2 }),
        ui.each(rows, function(a)
          return ui.hstack {
            spacing = 14,
            ui.text(a.kind, { size = o.size, mono = true, case = "upper", width = 70, lines = 1, color = "muted", text_align = "leading" }),
            ui.text(a.title, { size = o.size, mono = true, case = "upper", width = 230, lines = 1, text_align = "leading" }),
            ui.text(words[a.status] or a.status, { size = o.size, mono = true, case = "upper", color = colors[a.status] or "muted", lines = 1 }),
          }
        end),
        #rows == 0 and ui.text("No departures", { size = o.size, mono = true, case = "upper", color = "muted" }),
      }
    end

    return ui.vstack {
      align = "leading", spacing = 0,
      o.title and ui.hstack {
        padding = { 0, 0, 10, 0 }, spacing = 16,
        ui.text(o.title, { size = o.size + 2, weight = "bold" }),
        ui.spacer(),
        ui.text(summary, { size = o.size, weight = "medium", color = "muted" }),
      },
      #rows == 0 and ui.text("Nothing needs you", { size = o.size, color = "muted" }),
      ui.each(rows, function(a, i)
        return ui.vstack {
          spacing = 0, align = "leading",
          i > 1 and ui.divider(),
          ui.hstack {
            spacing = 10, padding = { 6, 0 },
            ui.dot({ size = 9, color = colors[a.status] or "muted", glow = a.status == "blocked" }),
            ui.vstack {
              align = "leading", spacing = 1,
              ui.text(a.title, { size = o.size, weight = "semibold", lines = 1, max_width = o.max_width or 300 }),
              ui.text(detail(a), { size = o.size - 1, color = "muted", lines = 1 }),
            },
          },
        }
      end),
    }
  end,
})
