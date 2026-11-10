-- Neo-Brutalism: raw web blocks. Thick near-black borders, hard offset shadows, and clashing bright fills on a
-- cream ground. A huge clock on lime, each panel tagged with a mono label, oversized type throughout.
local M = 50
local W = {}
local function block(x, y, w, h, fill, label_color, label)
  W[#W + 1] = { "brutal.block", anchor = "top-left", offset = { x, y },
    opts = { w = w, h = h, fill = fill, label = label, label_color = label_color } }
end
-- Content laid on a block, inset to clear the thick border and the corner label.
local function on(x, y, w, h, widget, opts, align, L, T, R, B)
  L, T, R, B = L or 30, T or 56, R or 30, B or 28
  W[#W + 1] = { widget, anchor = "top-left", offset = { x + L, y + T },
    size = { w - L - R, h - T - B }, opts = opts, align = align or "top-leading" }
end

local ink = "#1c1b18"
-- Top-left: the hero clock on lime
block(M, 48, 768, 372, "#e6ff02", ink, "// CLOCK")
on(M, 48, 768, 372, "clock", { size = 182, weight = "heavy", color = ink, mono = true, numeric = false, tracking = -5, shadow = 0 }, "center")
-- Top-right: weather on electric blue
block(M + 786, 48, 554, 176, "#2b2bff", "#ffffff", "WEATHER")
-- The line style: the hero's high/low row is always "muted" grey, unreadable on blue.
on(M + 786, 48, 554, 176, "weather", { style = "line", size = 30, color = "#ffffff", muted = "#ffffff", multicolor = false, place = false }, "leading", 30, 50, 24, 22)
-- Date on coral
block(M + 786, 244, 268, 176, "#ff6b6b", ink, "DATE")
on(M + 786, 244, 268, 176, "date", { format = "d", size = 86, weight = "heavy", color = ink, mono = true, numeric = false, shadow = 0 }, "center", 20, 44, 20, 40)
on(M + 786, 244, 268, 176, "date", { format = "EEE · MMM", size = 18, weight = "bold", color = ink, case = "upper", shadow = 0 }, "bottom", 20, 40, 20, 20)
-- Battery on mint
block(M + 1072, 244, 268, 176, "#7bed9f", ink, "PWR")
on(M + 1072, 244, 268, 176, "battery", { style = "row", color = ink, size = 22 }, "leading", 28, 56, 20, 24)
-- Bottom-left: a quote on white
block(M, 448, 812, 300, "#ffffff", ink, "QUOTE")
on(M, 448, 812, 300, "quote", { size = 30, color = ink, max_width = 720, text_align = "leading", font = nil }, "top-leading", 34, 62, 30, 26)
-- Bottom-right: the month on butter
block(M + 830, 448, 510, 300, "#fff7c2", ink, "CAL")
on(M + 830, 448, 510, 300, "calendar", { size = 15, title = true, today_color = "#2b2bff", today_text = "#ffffff" }, "center", 30, 48, 24, 14)

return {
  name = "Neo-Brutalism",
  description = "Raw web blocks: thick borders, hard shadows, and clashing bright fills on cream, with a huge clock on lime.",
  author = "Locky",
  palette = {
    bg = "#fbf7ee", fg = "#1c1b18", muted = "#6b6a66", accent = "#2b2bff",
    surface = "#ffffff", border = "#1c1b18",
    success = "#1c1b18", warning = "#ff6b6b", danger = "#ff6b6b",
    lime = "#e6ff02", coral = "#ff6b6b", blue = "#2b2bff", mint = "#7bed9f", butter = "#fff7c2", ink = "#1c1b18",
  },
  font = { weight = "medium" },
  background = { color = "#fbf7ee" },
  card = { style = "none" },
  auth = {
    style = "box", anchor = "bottom", offset = { 0, -46 }, width = 420, avatar = false, name = false,
    placeholder = "PASSWORD", focus = "blue", font = { size = 16, weight = "bold" },
  },
  widgets = W,
}
