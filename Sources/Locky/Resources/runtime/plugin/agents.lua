-- agents: coding agents from herdr (https://herdr.dev): who needs you, who is working.
--   opts.style     "list" (default), "summary" (one line of counts), "dots" (one dot per agent), "board" (a
--                  departures-style table)
--   opts.rows      most agents listed (default 4)
--   opts.title     header text (default "Agents"); false hides the header
--   opts.offline   text when herdr is not running; false hides the widget then
--   opts.every     seconds between checks (default 3)
local ui = locky.ui

local herdr = require("locky.herdr")
local colors, words = herdr.colors, herdr.words

locky.widget.define("agents", {
  description = "herdr coding agents: blocked, done, and working",
  card = true,
  opts = { style = "list", rows = 4, title = "Agents", offline = "herdr is not running", every = 3, size = 13 },
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
        padding = { 0, 0, 10, 0 },
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
              ui.text(a.workspace .. " · " .. a.kind, { size = o.size - 1, color = "muted", lines = 1 }),
            },
          },
        }
      end),
    }
  end,
})
