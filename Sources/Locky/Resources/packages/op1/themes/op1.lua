-- OP-1: Teenage Engineering's synth faceplate as a lock screen. A pale aluminium body, white module panels
-- under hairline borders, a big tabular clock, VU-style meters, and one small green OLED. Monospace throughout,
-- orange and screen-green the only accents, each module tagged with a tiny numbered label.
local M, G = 48, 16
local CW = (1440 - 2 * M - 3 * G) / 4           -- four module columns: 324
local function cell(col, row, cols, h)
  local x = M + col * (CW + G)
  local w = cols * CW + (cols - 1) * G
  return { anchor = "top-left", offset = { x, row }, size = { w, h } }
end
local function card(col, row, cols, h, widget, opts, align)
  local c = cell(col, row, cols, h)
  c[1] = widget; c.card = true; c.opts = opts; c.align = align or "center"
  return c
end
-- A tiny numbered module label, pinned to a card's top-left corner.
local function label(col, row, text, color)
  local x = M + col * (CW + G)
  return { "text", anchor = "top-left", offset = { x + 20, row + 16 },
    opts = { text = text, size = 11, weight = "bold", color = color or "#ff6600", alignment = "leading" } }
end

local R1, R2, R3 = 96, 404, 592                 -- row tops
return {
  name = "OP-1",
  description = "A Teenage Engineering synth faceplate: hairline module panels, a tabular clock, meters, and a green OLED.",
  author = "Locky",
  palette = {
    bg = "#f0f0f0", fg = "#0a0a0a", muted = "#9a9a9a", accent = "#ff6600",
    surface = "#ffffff", border = "#d4d4d4",
    success = "#00b84d", warning = "#ff9500", danger = "#ff3b30",
    orange = "#ff6600", green = "#00c853", screen = "#00ff66", ink = "#0a0a0a", alum = "#d4d4d4",
  },
  font = { design = "monospaced" },
  background = { gradient = { "#f4f4f4", "#e9e9e9" }, angle = 165, noise = 0.03 },
  card = { style = "solid", radius = 4, fill = "surface", border = "border" },
  auth = {
    style = "pill", anchor = "bottom", offset = { 0, -36 }, width = 320, avatar = false, name = false,
    placeholder = "PASSWORD", focus = "orange", font = { design = "monospaced", size = 14 },
  },
  widgets = {
    -- Brand strip
    { "text", anchor = "top-left", offset = { M + 2, 44 }, opts = { text = "OP–1", size = 22, weight = "bold", color = "ink", alignment = "leading" } },
    { "text", anchor = "top-left", offset = { M + 108, 50 }, opts = { text = "SYNTHESIZER / LOCK", size = 11, weight = "bold", color = "muted", alignment = "leading" } },
    { "op1.dots", anchor = "top-right", offset = { -M, 46 } },

    -- Row 1: the big clock (3 cols) and the OLED (1 col)
    card(0, R1, 3, 288, "clock", { size = 164, weight = "bold", design = "monospaced", color = "ink", tracking = -3, mono = true, numeric = false, shadow = 0 }),
    { "op1.screen", anchor = "top-left", offset = { M + 3 * (CW + G), R1 }, opts = { w = CW, h = 288, color = "#00ff66" } },

    -- Row 2: meters, power, disk
    card(0, R2, 2, 176, "system", { style = "bars", width = 560, size = 15, color = "orange", color2 = "green" }, "leading"),
    card(2, R2, 1, 176, "battery", { style = "row", size = 18, color = "ink" }),
    card(3, R2, 1, 176, "disk", { style = "bar", width = 236, size = 15, color = "orange", label = "DISK" }),

    -- Row 3: system readout, keyboard, uptime
    card(0, R3, 2, 168, "fetch", { logo = false, colors = true, size = 12, color = "orange", fields = { "os", "cpu", "memory" } }, "bottom-leading"),
    card(2, R3, 1, 168, "keyboard", { style = "code", size = 20, color = "ink" }),
    card(3, R3, 1, 168, "uptime", { size = 18, label = "UP" }),

    -- Module labels
    label(0, R1, "1 · CLOCK"),
    label(0, R2, "3 · METER"),
    label(2, R2, "4 · POWER"),
    label(3, R2, "5 · DISK"),
    label(0, R3, "6 · SYSTEM"),
    label(2, R3, "7 · INPUT"),
    label(3, R3, "8 · UPTIME"),
  },
}
