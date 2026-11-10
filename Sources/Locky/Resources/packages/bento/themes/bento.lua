-- Bento Cockpit: the AGS/eww "command center" rice as a bento grid of rounded cards — circular system
-- gauges, a network chart, a process list — on a calm graphite ground. Dense but tidy; one corner radius,
-- one gap, a green-amber-red load ramp.
local M, G = 48, 16
local CW = (1440 - 2 * M - 3 * G) / 4        -- 4-column grid: 324
local function cell(col, row, cols, h)
  local x = M + col * (CW + G)
  local y = row
  local w = cols * CW + (cols - 1) * G
  return { anchor = "top-left", offset = { x, y }, size = { w, h } }
end
local function card(col, row, cols, h, widget, opts, align)
  local c = cell(col, row, cols, h)
  c[1] = widget; c.card = true; c.opts = opts; c.align = align
  return c
end

local R1, R2, R3 = 48, 300, 552              -- row tops
return {
  name = "Bento Cockpit",
  description = "A command-center bento grid: circular system gauges, a network chart, and a process list on graphite.",
  author = "Locky",
  palette = {
    bg = "#0d1117", fg = "#e6edf3", muted = "#7d8590", accent = "#58a6ff",
    surface = "#161b22", border = "#21262d",
    success = "#3fb950", warning = "#d29922", danger = "#f85149",
    blue = "#58a6ff", green = "#3fb950", amber = "#d29922", red = "#f85149", purple = "#bc8cff",
  },
  font = { design = "rounded" },
  background = { gradient = { "#0d1117", "#090c10" }, angle = 180, noise = 0.015 },
  card = { style = "solid", radius = 18, fill = "surface", border = "border" },
  auth = {
    style = "pill", anchor = "bottom", offset = { 0, -40 }, width = 300, avatar = false, name = false,
    placeholder = "password", focus = "accent", font = { size = 14 },
  },
  widgets = {
    -- Row 1: clock hero (2 cols) + weather (2 cols)
    card(0, R1, 2, 236, "clock", { size = 112, weight = "semibold", color = "fg", tracking = -2, shadow = 0, numeric = false }),
    { "greeting", anchor = "top-left", offset = { M + 32, R1 + 26 }, opts = { size = 15, weight = "medium", color = "accent" } },
    { "date", anchor = "top-left", offset = { M + 32, R1 + 192 }, opts = { format = "EEEE d MMMM", size = 15, weight = "medium", color = "muted" } },
    card(2, R1, 2, 236, "weather", { style = "detail" }),
    -- Row 2: system rings, battery ring, disk ring, uptime
    card(0, R2, 1, 236, "system", { style = "rings", color = "blue", color2 = "green", size = 14, ring = 72 }),
    card(1, R2, 1, 236, "battery", { style = "ring", size = 16, color = "green" }),
    card(2, R2, 1, 236, "disk", { style = "ring", color = "amber", label = "Disk" }),
    card(3, R2, 1, 236, "uptime", { size = 15, label = "Uptime" }, "center"),
    -- Row 3: network chart (2 cols) + top processes (2 cols)
    card(0, R3, 2, 236, "network", { style = "chart", color = "purple", size = 13, height = 150 }, "top-leading"),
    card(2, R3, 2, 236, "top", { rows = 6, size = 13, sort = "cpu" }, "top-leading"),
  },
}
