-- Gruvbox: a conky desktop in morhetz's retro-groove colors. A big clock on the left, and on the right the sidebar
-- conky fans have kept since the 2000s: system, disk, network, processes, and power, each under a ruled heading.
local x, w = -40, 300
local function heading(text, y)
  return { "gruvbox.heading", anchor = "top-right", offset = { x, y }, opts = { text = text, width = w } }
end
return {
  name = "Gruvbox",
  description = "A conky sidebar in Gruvbox colors: system, disk, network, processes, and power beside a big clock.",
  palette = {
    bg = "#282828", fg = "#ebdbb2", muted = "#a89984", accent = "#fe8019", surface = "#3c3836", border = "#504945",
    success = "#b8bb26", warning = "#fabd2f", danger = "#fb4934",
    panel = "#1d2021", yellow = "#fabd2f", aqua = "#8ec07c", blue = "#83a598", purple = "#d3869b",
  },
  font = { design = "monospaced" },
  background = { gradient = { "#282828", "#32302f" }, angle = 160, noise = 0.03 },
  card = { style = "none" },
  auth = {
    style = "terminal", anchor = "bottom-left", offset = { 64, -56 }, width = 420, avatar = false, name = false,
    prompt = "λ ", focus = "yellow", font = { design = "monospaced", size = 15 },
  },
  widgets = {
    { "gruvbox.panel", anchor = "right", size = { 380, 900 } },
    { "clock", anchor = "left", offset = { 64, -110 },
      opts = { size = 150, weight = "bold", design = "monospaced", color = "yellow", tracking = -4, shadow = 0, numeric = false } },
    { "date", anchor = "left", offset = { 70, -10 },
      opts = { format = "EEEE d MMMM", size = 18, weight = "bold", color = "aqua", case = "upper", tracking = 3, shadow = 0 } },
    { "progress", anchor = "left", offset = { 70, 26 }, opts = { style = "text", size = 13, color = "muted", show = { "day", "week", "year" } } },
    { "quote", anchor = "bottom-left", offset = { 64, -150 },
      opts = { size = 15, max_width = 560, text_align = "leading", color = "fg", font = "Menlo" } },

    heading("SYSTEM", 40),
    { "system", anchor = "top-right", offset = { x, 70 }, opts = { style = "bars", width = w, color = "yellow", color2 = "aqua", size = 12 } },
    heading("DISK", 175),
    { "disk", anchor = "top-right", offset = { x, 205 }, opts = { style = "bar", width = w, color = "blue", label = "Macintosh HD" } },
    heading("NETWORK", 300),
    { "network", anchor = "top-right", offset = { x, 330 }, opts = { style = "chart", width = w, color = "purple", size = 12 } },
    heading("PROCESSES", 460),
    { "top", anchor = "top-right", offset = { x, 490 }, opts = { rows = 6, width = w, size = 12 } },
    heading("POWER", 660),
    { "battery", anchor = "top-right", offset = { x, 690 }, size = { w, 40 }, align = "leading", opts = { style = "row", size = 14 } },
    { "uptime", anchor = "top-right", offset = { x, 744 }, size = { w, 24 }, align = "leading", opts = { size = 13 } },
  },
}
