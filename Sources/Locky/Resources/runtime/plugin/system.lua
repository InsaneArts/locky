-- system: CPU and memory.
--   opts.style   "rings" (default), "bars", "chart" (CPU over the last minutes), or "text"
--   opts.every   seconds between readings (default 2)
local ui = locky.ui

locky.widget.define("system", {
  description = "CPU and memory use",
  card = true,
  opts = { style = "rings", every = 2, size = 13, history = 60 },
  init = function(self)
    self.state.history = {}
    self:every(self.opts.every, function(self)
      local cpu, memory = locky.sys.cpu(), locky.sys.memory()
      local history = self.state.history
      history[#history + 1] = cpu.usage
      if #history > self.opts.history then
        table.remove(history, 1)
      end
      self:set({ cpu = cpu.usage, memory = memory.percent })
    end)
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.cpu then
      return nil
    end
    local cpu, mem = math.floor(s.cpu + 0.5), math.floor((s.memory or 0) + 0.5)
    if o.style == "text" then
      return ui.text(("CPU %d%%  ·  MEM %d%%"):format(cpu, mem), { size = o.size, mono = true })
    end
    if o.style == "chart" then
      return ui.vstack {
        spacing = 8, align = "leading",
        ui.hstack {
          ui.text("CPU " .. cpu .. "%", { size = o.size, weight = "semibold", mono = true }),
          ui.spacer(),
          ui.text("Memory " .. mem .. "%", { size = o.size, color = "muted", mono = true }),
        },
        ui.chart(s.history, { max = 100, slots = o.history, height = o.height or 52, width = o.width or 240, color = o.color or "accent", style = "area" }),
      }
    end
    if o.style == "bars" then
      local function bar(label, value, color)
        return ui.vstack {
          spacing = 4, align = "leading",
          ui.hstack { ui.text(label, { size = o.size - 1, color = "muted", case = "upper", tracking = 1 }), ui.spacer(), ui.text(value .. "%", { size = o.size - 1, mono = true }) },
          ui.progress(value / 100, { color = color, width = o.width or 200, size = 5 }),
        }
      end
      return ui.vstack { spacing = 10, bar("CPU", cpu, o.color or "accent"), bar("Memory", mem, o.color2 or "success") }
    end
    local function ring(label, value, color)
      return ui.vstack {
        spacing = 6,
        ui.zstack {
          ui.ring(value / 100, { size = o.ring or 52, stroke_width = 5, color = color }),
          ui.text(value, { size = o.size, weight = "semibold", mono = true }),
        },
        ui.text(label, { size = o.size - 2, color = "muted", case = "upper", tracking = 1 }),
      }
    end
    return ui.hstack { spacing = 18, ring("CPU", cpu, o.color or "accent"), ring("MEM", mem, o.color2 or "success") }
  end,
})
