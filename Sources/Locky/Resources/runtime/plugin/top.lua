-- top: the programs using the most CPU (or memory), from `ps`, like conky's top lines.
--   opts.rows    how many (default 5); opts.sort "cpu" (default) or "memory"
--   opts.every   seconds between readings (default 3); opts.size, opts.color, opts.width
--   Families: rectangular, inline, small, medium, large (rows like Apple's Stocks; their own number of rows).
local ui = locky.ui

-- Rows each family shows.
local family_rows = { inline = 1, rectangular = 2, small = 4, medium = 4, large = 6 }

local function percent(n)
  return ("%.1f%%"):format(n)
end

-- Apple's layouts for each family.
local function family(f, list, o)
  local memory = o.sort == "memory"
  local title = memory and "Memory" or "CPU"
  local function value(p)
    return memory and p.mem or p.cpu
  end
  if f == "inline" then
    local p = list[1]
    return ui.hstack {
      spacing = 4,
      ui.symbol(memory and "memorychip" or "cpu", ui.font("subheadline")),
      ui.text(p and (p.name .. " " .. percent(value(p))) or "No processes", ui.font("subheadline", { mono = true, lines = 1 })),
    }
  elseif f == "rectangular" then
    return ui.vstack {
      spacing = 1, align = "leading", fill = "both",
      ui.hstack { spacing = 5, ui.symbol(memory and "memorychip" or "cpu", ui.font("headline")), ui.text("Top " .. title, ui.font("headline")) },
      ui.each({ list[1], list[2] }, function(p)
        return ui.hstack {
          spacing = 6,
          ui.text(p.name, ui.font("subheadline", { lines = 1 })),
          ui.spacer(),
          ui.text(percent(value(p)), ui.font("subheadline", { mono = true })),
        }
      end),
    }
  end
  local small = f == "small"
  local header = ui.hstack {
    spacing = 5, padding = { 0, 0, f == "large" and 6 or 4, 0 },
    ui.symbol(memory and "memorychip" or "cpu", { size = 13, weight = "semibold", color = o.color or "accent" }),
    ui.text(small and title or ("Top Processes by " .. title), ui.font("subheadline", { weight = "semibold", lines = 1 })),
  }
  local rows = {}
  for i = 1, math.min(family_rows[f], #list) do
    rows[i] = list[i]
  end
  return ui.vstack {
    spacing = 0, align = "leading", fill = "both",
    header,
    ui.each(rows, function(p, i)
      local name = ui.text(p.name, ui.font(small and "footnote" or "subheadline", { weight = small and "medium" or "semibold", lines = 1 }))
      local hot = p.cpu >= 50 and not memory
      return ui.vstack {
        spacing = 0, fill = "width",
        i > 1 and ui.divider(),
        ui.hstack {
          spacing = 8, padding = { f == "large" and 6 or 4, 0 },
          f == "large" and ui.vstack {
            spacing = 1, align = "leading",
            name,
            ui.text(memory and ("CPU " .. percent(p.cpu)) or ("Memory " .. percent(p.mem)), ui.font("footnote", { color = "muted", lines = 1 })),
          } or name,
          ui.spacer(),
          ui.text(percent(value(p)), ui.font(small and "footnote" or "subheadline", { weight = "medium", mono = true, color = hot and "warning" or nil })),
        },
      }
    end),
    ui.spacer(),
  }
end

locky.widget.define("top", {
  description = "The programs using the most CPU or memory",
  families = { "rectangular", "inline", "small", "medium", "large" },
  opts = { rows = 5, sort = "cpu", every = 3, size = 12, width = 260 },
  choices = { sort = { "cpu", "memory" } },
  init = function(self)
    self:every(self.opts.every, function(self)
      self:system({ "ps", "-Ao", "pcpu=,pmem=,comm=", self.opts.sort == "memory" and "-m" or "-r" }, function(self, result)
        local list = {}
        for cpu, mem, command in result.stdout:gmatch("%s*([%d.]+)%s+([%d.]+)%s+([^\n]+)") do
          if #list >= (family_rows[self.family] or self.opts.rows) then
            break
          end
          local name = command:match("([^/]+)$") or command
          list[#list + 1] = { name = name, cpu = tonumber(cpu), mem = tonumber(mem) }
        end
        self:set({ list = list })
      end)
    end)
  end,
  render = function(self)
    local o, list = self.opts, self.state.list
    if not list then
      return nil
    end
    if self.family then
      if not family_rows[self.family] then
        return nil
      end
      return family(self.family, list, o)
    end
    local s = o.size
    local rows = {
      ui.hstack {
        width = o.width,
        ui.text("PROCESS", { size = s * 0.8, color = "muted", tracking = 1 }),
        ui.spacer(),
        ui.text("CPU", { size = s * 0.8, color = "muted", tracking = 1, width = s * 4, text_align = "trailing" }),
        ui.text("MEM", { size = s * 0.8, color = "muted", tracking = 1, width = s * 4, text_align = "trailing" }),
      },
    }
    for _, p in ipairs(list) do
      rows[#rows + 1] = ui.hstack {
        width = o.width,
        ui.text(p.name, { size = s, lines = 1, color = o.color }),
        ui.spacer(),
        ui.text(("%.1f"):format(p.cpu), { size = s, mono = true, width = s * 4, text_align = "trailing", color = p.cpu >= 50 and "warning" or o.color }),
        ui.text(("%.1f"):format(p.mem), { size = s, mono = true, width = s * 4, text_align = "trailing", color = "muted" }),
      }
    end
    return ui.vstack { spacing = s * 0.35, align = "leading", rows }
  end,
})
