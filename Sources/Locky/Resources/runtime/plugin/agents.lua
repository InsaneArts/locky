-- agents: coding agents from herdr (https://herdr.dev): which agent needs you, and what is working.
--   opts.style     "list" (default: blocked, then done, then working, with how long each has been so; idle ones
--                  as a count), "summary" (one line of counts), "dots" (one dot per agent), "board" (a
--                  departures-style table)
--   opts.rows      most agents listed (default 4)
--   opts.title     header text (default "Agents"); false hides the header
--   opts.offline   text when herdr is not running; false hides the widget then
--   Families: circular (how many need you), rectangular, inline, small, medium, large (lists like Apple's
--   Reminders). Changes show at once: Locky follows herdr's events.
local ui = locky.ui

local herdr = require("locky.herdr")
local colors, words = herdr.colors, herdr.words

-- `props` with `extra` over it.
local function with(props, extra)
  return locky.tbl.extend("force", props, extra)
end

-- How long `a` has had its status, such as "12m", or nil when that began before Locky connected.
local function age(data, a)
  local seconds = herdr.elapsed(data, a)
  return seconds and herdr.duration(seconds)
end

-- The agents that are not idle, at most `n` of them, and how many more there are.
local function active(data, n)
  local list = {}
  for _, a in ipairs(data.agents) do
    if a.status ~= "idle" and #list < n then
      list[#list + 1] = a
    end
  end
  return list, #data.agents - data.counts.idle - #list
end

-- "2 need you · 3 working", "6 idle", or nil when there is nothing.
local function summary(data)
  local c, parts = data.counts, {}
  if data.need > 0 then
    parts[#parts + 1] = data.need .. " need you"
  end
  if c.working > 0 then
    parts[#parts + 1] = c.working .. " working"
  end
  if #parts == 0 and c.idle > 0 then
    parts[1] = c.idle .. " idle"
  end
  return #parts > 0 and table.concat(parts, " · ") or nil
end

-- "+ 2 more · 6 idle": what the rows leave out.
local function rest(data, more)
  local parts = {}
  if more > 0 then
    parts[#parts + 1] = more .. " more"
  end
  if data.counts.idle > 0 then
    parts[#parts + 1] = data.counts.idle .. " idle"
  end
  return #parts > 0 and "+ " .. table.concat(parts, " · ") or nil
end

-- The line under a title: the status in its color when the agent needs you, then the workspace and the time.
-- In privacy mode the workspace is empty.
local function detail(data, a, font)
  local parts = {}
  if a.workspace ~= "" then
    parts[#parts + 1] = a.workspace
  end
  parts[#parts + 1] = age(data, a)
  return ui.hstack {
    spacing = 0,
    ui.text(words[a.status] or a.status, with(font, { color = a.status == "blocked" and "warning" or "muted", weight = a.status == "blocked" and "semibold" or nil })),
    #parts > 0 and ui.text(" · " .. table.concat(parts, " · "), with(font, { color = "muted" })),
  }
end

local function dot(a, size)
  return ui.dot({ size = size, color = colors[a.status] or "muted", glow = a.status == "blocked" })
end

-- Apple's layouts for each family. data is false when herdr is not running.
local function family(f, data, o)
  local tint = o.color or "accent"
  local c = data and data.counts
  local total = data and #data.agents or 0
  -- The count that leads, its name, and its color: who needs you, else who works, else who idles.
  local count, label, tone = 0, "Agents", tint
  if data and data.need > 0 then
    count, label, tone = data.need, "Need You", c.blocked > 0 and "warning" or "success"
  elseif data and c.working > 0 then
    count, label = c.working, "Working"
  elseif data and total > 0 then
    count, label, tone = c.idle, "Idle", "muted"
  end
  local empty = not data and (o.offline or "Herdr isn't running") or total == 0 and "No agents running" or nil
  local line = empty or summary(data) or "Nothing needs you"
  if f == "inline" then
    return ui.hstack { spacing = 4, ui.symbol("terminal", ui.font("subheadline")), ui.text(line, ui.font("subheadline", { lines = 1 })) }
  elseif f == "circular" then
    if empty or (data.need == 0 and c.working == 0) then
      return ui.symbol(empty and "terminal" or "checkmark", { size = 26, weight = "medium", opacity = empty and 0.6 or 1 })
    end
    return ui.vstack {
      spacing = 0,
      ui.symbol(data.need > 0 and "hand.raised.fill" or "terminal.fill", { size = 14, weight = "medium" }),
      ui.text(count, { size = 24, weight = "semibold", mono = true }),
    }
  elseif f == "rectangular" then
    local first = not empty and active(data, 1)[1]
    return ui.vstack {
      spacing = 1, align = "leading", fill = "both",
      ui.hstack { spacing = 5, ui.symbol("terminal.fill", ui.font("headline")), ui.text("Agents", ui.font("headline")) },
      ui.text(empty or (data.need > 0 or c.working > 0) and line or "Nothing needs you", ui.font("subheadline", { color = empty and "muted" or nil, lines = empty and 2 or 1 })),
      first and ui.text(first.title .. (age(data, first) and " · " .. age(data, first) or ""), ui.font("subheadline", { color = "muted", lines = 1 })),
      not empty and not first and c.idle > 0 and ui.text(c.idle .. " idle", ui.font("subheadline", { color = "muted", lines = 1 })),
    }
  end
  -- Reminders' list icon: a symbol on a tinted circle.
  local icon = ui.zstack {
    ui.circle({ color = tint, width = 28, height = 28 }),
    ui.symbol("terminal.fill", { size = 13, weight = "semibold", color = "#ffffff" }),
  }
  local small = f == "small"
  local list, more = {}, 0
  if not empty then
    -- Rows that fit: three small ones, two with their detail beside the count, five in a large widget.
    list, more = active(data, f == "large" and 5 or f == "medium" and 2 or 3)
  end
  local function row(a, i)
    if small then
      return ui.hstack {
        spacing = 7, id = a.id,
        dot(a, 7),
        ui.text(a.title, ui.font("footnote", { weight = "medium", lines = 1 })),
        ui.spacer(),
        age(data, a) and ui.text(age(data, a), ui.font("footnote", { color = "muted", mono = true })),
      }
    end
    return ui.vstack {
      spacing = 0, align = "leading", fill = "width", id = a.id,
      i > 1 and ui.divider(),
      ui.hstack {
        spacing = 10, padding = { f == "large" and 6 or 3, 0 },
        dot(a, 9),
        ui.vstack {
          spacing = 0, align = "leading",
          ui.text(a.title, ui.font("subheadline", { weight = "semibold", lines = 1 })),
          detail(data, a, ui.font("footnote", { lines = 1 })),
        },
        ui.spacer(),
      },
    }
  end
  -- A small widget has room for three rows, or fewer and the count of the rest.
  local footer = not empty and not (small and #list == 3) and rest(data, more) or nil
  local rows = empty and ui.vstack {
    spacing = 0, fill = "both",
    ui.text(empty, ui.font(small and "footnote" or "subheadline", { weight = "medium", color = "muted", text_align = "center", lines = 2 })),
  } or ui.vstack {
    spacing = small and 5 or 0, align = "leading", fill = "width", animate = "smooth",
    ui.each(list, row),
    #list == 0 and ui.text("Nothing needs you", ui.font(small and "footnote" or "subheadline", { weight = "medium", color = "muted" })),
    footer and ui.text(footer, ui.font("footnote", { weight = "medium", color = "muted", padding = { small and 0 or 4, 0, 0, small and 14 or 19 } })),
  }
  local number = ui.text(empty and "" or count, ui.font(small and "title" or "large_title", { weight = "bold", mono = true, numeric = true }))
  local name = ui.text(empty and "Agents" or label, ui.font(small and "subheadline" or "headline", { weight = "semibold", color = tone, lines = 1 }))
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
    ui.hstack { padding = { 0, 0, 10, 0 }, name },
    rows,
    ui.spacer(),
  }
end

locky.widget.define("agents", {
  description = "herdr coding agents: who needs you, and what is working",
  card = true,
  families = { "circular", "rectangular", "inline", "small", "medium", "large" },
  opts = { style = "list", rows = 4, title = "Agents", offline = "Herdr isn't running", size = 13 },
  choices = { style = { "list", "summary", "dots", "board" } },
  init = function(self)
    herdr.watch(self, function(self, data)
      self:set({ data = data })
    end)
    -- The times move on between changes.
    self:every(20, function(self)
      self:refresh()
    end, { now = false })
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
    local none = #data.agents == 0 and "No agents running" or nil

    if o.style == "summary" then
      return ui.hstack {
        spacing = 8,
        ui.dot({ size = 8, color = c.blocked > 0 and "warning" or c.done > 0 and "success" or c.working > 0 and "accent" or "muted", glow = c.blocked > 0 }),
        ui.text(none or summary(data), { size = o.size, weight = "medium" }),
      }
    end

    if o.style == "dots" then
      return ui.hstack {
        spacing = 6, animate = "smooth",
        ui.each(data.agents, function(a)
          return ui.dot({ id = a.id, size = o.dot or 10, color = colors[a.status] or "muted", glow = a.status == "blocked", opacity = a.status == "idle" and 0.35 or 1 })
        end),
      }
    end

    if o.style == "board" then
      local rows = {}
      for i = 1, math.min(o.rows, #data.agents) do
        rows[i] = data.agents[i]
      end
      local cell = { size = o.size, mono = true, case = "upper", lines = 1, text_align = "leading" }
      -- In privacy mode every title is its kind: the title column goes.
      local titled = false
      for _, a in ipairs(rows) do
        titled = titled or a.title ~= a.kind
      end
      return ui.vstack {
        align = "leading", spacing = 6,
        o.title and ui.text(o.title, { size = o.size, weight = "bold", color = "accent", case = "upper", tracking = 2 }),
        ui.each(rows, function(a)
          return ui.hstack {
            spacing = 14, id = a.id,
            ui.text(a.kind, with(cell, { width = 70, color = "muted" })),
            titled and ui.text(a.title ~= a.kind and a.title or "", with(cell, { width = 230 })),
            ui.text(words[a.status] or a.status, with(cell, { width = 100, color = colors[a.status] or "muted" })),
            ui.text(age(data, a) or "", with(cell, { width = 40, color = "muted", text_align = "trailing" })),
          }
        end),
        none and ui.text(none, with(cell, { color = "muted" })),
      }
    end

    local list, more = active(data, o.rows)
    local footer = rest(data, more)
    return ui.vstack {
      align = "leading", spacing = 0,
      o.title and ui.hstack {
        padding = { 0, 0, 8, 0 }, spacing = 16,
        ui.text(o.title, { size = o.size + 2, weight = "bold" }),
        ui.spacer(),
        need > 0 and ui.text(need .. " need you", { size = o.size, weight = "semibold", color = c.blocked > 0 and "warning" or "success" }),
      },
      (none or #list == 0) and ui.text(none or "Nothing needs you", { size = o.size, color = "muted", padding = { 2, 0 } }),
      ui.vstack {
        align = "leading", spacing = 0, animate = "smooth",
        ui.each(list, function(a, i)
          return ui.vstack {
            spacing = 0, align = "leading", id = a.id,
            i > 1 and ui.divider(),
            ui.hstack {
              spacing = 10, padding = { 6, 0 },
              dot(a, 9),
              ui.vstack {
                align = "leading", spacing = 1,
                ui.text(a.title, { size = o.size, weight = "semibold", lines = 1, max_width = o.max_width or 300 }),
                detail(data, a, { size = o.size - 1, lines = 1 }),
              },
            },
          }
        end),
      },
      footer and ui.text(footer, { size = o.size - 1, weight = "medium", color = "muted", padding = { 6, 0, 0, 19 } }),
    }
  end,
})
