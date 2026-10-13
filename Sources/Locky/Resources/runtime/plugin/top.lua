-- top: the programs using the most CPU (or memory), from `ps`, like conky's top lines.
--   opts.rows    how many (default 5); opts.sort "cpu" (default) or "memory"
--   opts.every   seconds between readings (default 3); opts.size, opts.color, opts.width
local ui = locky.ui

locky.widget.define("top", {
  description = "The programs using the most CPU or memory",
  opts = { rows = 5, sort = "cpu", every = 3, size = 12, width = 260 },
  choices = { sort = { "cpu", "memory" } },
  init = function(self)
    self:every(self.opts.every, function(self)
      self:system({ "ps", "-Ao", "pcpu=,pmem=,comm=", self.opts.sort == "memory" and "-m" or "-r" }, function(self, result)
        local list = {}
        for cpu, mem, command in result.stdout:gmatch("%s*([%d.]+)%s+([%d.]+)%s+([^\n]+)") do
          if #list >= self.opts.rows then
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
