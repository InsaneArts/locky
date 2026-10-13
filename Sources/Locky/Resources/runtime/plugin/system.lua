-- system: CPU and memory.
--   Families: circular (CPU on a ring), rectangular (CPU over the last minutes), inline, small (CPU and memory
--   rings), medium (CPU over the last minutes, and memory).
--   opts.style   "rings" (default), "bars", "chart" (CPU over the last minutes), or "text"
--   opts.every   seconds between readings (default 2)
local ui = locky.ui

-- A ring with a symbol in it, the percent, and a label: Apple's Batteries widget.
local function meter(icon, label, value, color)
  return ui.vstack {
    spacing = 8,
    ui.zstack {
      ui.gauge(value / 100, { style = "capacity", size = 58, color = color }),
      ui.symbol(icon, { size = 20, weight = "medium" }),
    },
    ui.vstack {
      spacing = 0,
      ui.text(value .. "%", ui.font("title3", { weight = "semibold", mono = true })),
      ui.text(label, ui.font("caption", { weight = "medium", color = "muted" })),
    },
  }
end

-- Apple's layouts for each family.
local function family(f, cpu, mem, history, o)
  if f == "large" then
    return nil
  end
  -- The chart's top: the busiest moment and a little room, so a quiet minute still shows its shape.
  local top = 25
  for _, v in ipairs(history) do
    top = math.max(top, math.min(v * 1.5, 100))
  end
  if f == "inline" then
    return ui.hstack {
      spacing = 4,
      ui.symbol("cpu", ui.font("subheadline")),
      ui.text(("CPU %d%%  Memory %d%%"):format(cpu, mem), ui.font("subheadline", { mono = true, lines = 1 })),
    }
  elseif f == "circular" then
    return ui.zstack {
      ui.gauge(cpu / 100, { style = "capacity", size = 64 }),
      ui.vstack {
        spacing = 0,
        ui.symbol("cpu", { size = 15, weight = "medium" }),
        ui.text(cpu, { size = 17, weight = "semibold", mono = true }),
      },
    }
  elseif f == "rectangular" then
    return ui.vstack {
      spacing = 4, align = "leading", fill = "both",
      ui.hstack {
        spacing = 5,
        ui.symbol("cpu", ui.font("headline")),
        ui.text("CPU", ui.font("headline")),
        ui.spacer(),
        ui.text(cpu .. "%", ui.font("headline", { mono = true })),
      },
      ui.chart(history, { min = 0, max = top, slots = o.history, width = 172, height = 46, style = "area", color = "fg", stroke_width = 1.5 }),
    }
  elseif f == "small" then
    return ui.hstack {
      spacing = 16, fill = "both",
      meter("cpu", "CPU", cpu, o.color or "accent"),
      meter("memorychip", "Memory", mem, o.color2 or "success"),
    }
  end
  return ui.hstack {
    spacing = 16, fill = "both",
    ui.vstack {
      spacing = 0, align = "leading", width = 116, fill = "height",
      ui.hstack {
        spacing = 4,
        ui.symbol("cpu", { size = 13, weight = "semibold", color = o.color or "accent" }),
        ui.text("CPU", ui.font("subheadline", { weight = "semibold" })),
      },
      ui.text(cpu .. "%", ui.font("large_title", { weight = "semibold", mono = true })),
      ui.spacer(),
      ui.text("Memory", ui.font("caption", { weight = "semibold", color = "muted" })),
      ui.text(mem .. "%", ui.font("headline", { mono = true, padding = { 0, 0, 5, 0 } })),
      ui.gauge(mem / 100, { style = "linear-capacity", size = 116, color = o.color2 or "success" }),
    },
    ui.chart(history, { min = 0, max = top, slots = o.history, width = 200, height = 138, style = "area", color = o.color or "accent", stroke_width = 1.5 }),
  }
end

locky.widget.define("system", {
  description = "CPU and memory use",
  card = true,
  families = { "circular", "rectangular", "inline", "small", "medium" },
  opts = { style = "rings", every = 2, size = 13, history = 60 },
  choices = { style = { "rings", "bars", "chart", "text" } },
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
    if self.family then
      return family(self.family, cpu, mem, s.history, o)
    end
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
