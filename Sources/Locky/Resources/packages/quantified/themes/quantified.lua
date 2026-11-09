-- Quantified Self: a wearable health dashboard (Oura / WHOOP). Near-black, big scores, rounded tiles, and
-- rings colored by a green-amber-red zone ramp. Calm consumer data-viz.
local M, G = 84, 24
local CW, CH = 300, 224
local function tile(i, widget, opts, align)
  local x = M + i * (CW + G)
  return { widget, anchor = "top-left", offset = { x, 486 }, size = { CW, CH }, card = true, opts = opts, align = align }
end
return {
  name = "Quantified Self",
  description = "A wearable dashboard: near-black tiles, big scores, and rings in green-amber-red zones.",
  author = "Locky",
  palette = {
    bg = "#000000", fg = "#f2f4f5", muted = "#7a8089", accent = "#2bd575", surface = "#141619", border = "#20242a",
    success = "#2bd575", warning = "#ffc24b", danger = "#ff5a5f",
    green = "#2bd575", amber = "#ffc24b", red = "#ff5a5f", blue = "#0093e7",
  },
  font = { design = "rounded", weight = "medium" },
  background = { gradient = { "#0a0b0d", "#000000" }, angle = 180 },
  card = { style = "solid", radius = 26, fill = "surface", border = "border" },
  auth = {
    style = "pill", anchor = "bottom", offset = { 0, -40 }, width = 280, avatar = false, name = false,
    placeholder = "password", focus = "green", font = { size = 14 },
  },
  widgets = {
    { "greeting", anchor = "top", offset = { 0, 108 }, opts = { size = 17, weight = "medium", color = "green" } },
    { "clock", anchor = "top", offset = { 0, 140 }, opts = { size = 150, weight = "semibold", color = "fg", tracking = -3, shadow = 0, numeric = false } },
    { "date", anchor = "top", offset = { 0, 320 }, opts = { format = "EEEE d MMMM", size = 16, weight = "medium", color = "muted", case = "upper", tracking = 2 } },
    -- A row of metric tiles
    tile(0, "progress", { style = "rings", size = 13, color = "green" }, "center"),
    tile(1, "system", { style = "rings", color = "green", color2 = "amber", size = 13, ring = 58 }, "center"),
    tile(2, "battery", { style = "ring", size = 18, color = "green" }, "center"),
    tile(3, "disk", { style = "ring", color = "blue", label = "Disk" }, "center"),
  },
}
