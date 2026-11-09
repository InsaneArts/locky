-- TUI Grid: a btop terminal dashboard. Rounded bordered boxes with "┤ title ├" tabs, tiled edge to edge over a
-- flat ink ground, one monospace size throughout. A neofetch host box, a big teal clock, a live CPU chart, disk,
-- and the net and proc boxes that fill in on the live lock.
local M, G = 28, 14
local PL, PT, PR, PB = 18, 40, 18, 16            -- content inset inside a box (top clears the title tab)
local W = {}
local function box(x, y, w, h, title, color)
  W[#W + 1] = { "tui.box", anchor = "top-left", offset = { x, y }, opts = { w = w, h = h, title = title, color = color } }
end
local function fill(x, y, w, h, widget, opts, align)
  W[#W + 1] = { widget, anchor = "top-left", offset = { x + PL, y + PT },
    size = { w - PL - PR, h - PT - PB }, opts = opts, align = align or "top-leading" }
end
local function at(x, y, w, h, widget, opts, align)   -- a free overlay inside a box, no inset
  W[#W + 1] = { widget, anchor = "top-left", offset = { x, y }, size = { w, h }, opts = opts, align = align }
end

-- Row 1: host (neofetch) + time
box(M, 28, 656, 232, "host", "cyan")
fill(M, 28, 656, 232, "fetch", { logo = "lock", size = 13, color = "cyan", fields = { "os", "host", "kernel", "uptime", "cpu" } }, "leading")
box(M + 670, 28, 714, 232, "time", "teal")
at(M + 670, 48, 714, 168, "clock", { size = 116, weight = "bold", color = "teal", mono = true, numeric = false, shadow = 0, tracking = -2 }, "center")
at(M + 670, 212, 714, 36, "fuzzy", { prefix = "", case = "lower", size = 15, weight = "regular", color = "muted", text_align = "center" }, "center")

-- Row 2: cpu (live history chart over meters) + disk
box(M, 274, 910, 244, "cpu", "teal")
at(M + PL, 314, 874, 112, "system", { style = "chart", color = "teal", width = 866, height = 108, size = 14 }, "top-leading")
at(M + PL, 434, 874, 66, "system", { style = "bars", color = "teal", color2 = "cyan", width = 866, size = 13 }, "top-leading")
box(M + 924, 274, 460, 244, "disk", "amber")
fill(M + 924, 274, 460, 244, "disk", { style = "bar", color = "amber", width = 404, size = 15, label = "root" }, "leading")

-- Row 3: net + proc (blank in render, live on the lock — the boxes keep the grid readable)
box(M, 532, 685, 240, "net", "cyan")
fill(M, 532, 685, 240, "network", { style = "chart", color = "cyan", width = 630, height = 140, size = 13 }, "top-leading")
box(M + 699, 532, 685, 240, "proc", "red")
fill(M + 699, 532, 685, 240, "top", { rows = 8, sort = "cpu", size = 13, width = 640 }, "top-leading")

return {
  name = "TUI Grid",
  description = "A btop terminal dashboard: bordered boxes with title tabs, a CPU chart, a neofetch host, and a teal clock.",
  author = "Locky",
  palette = {
    bg = "#0f1116", fg = "#d5dae3", muted = "#5a6373", accent = "#2bd4a8",
    surface = "#171a21", border = "#3a4454",
    success = "#2bd4a8", warning = "#e6c96b", danger = "#e06c75",
    teal = "#2bd4a8", amber = "#e6c96b", red = "#e06c75", cyan = "#7dcfff",
  },
  font = { design = "monospaced" },
  background = { gradient = { "#0f1116", "#0c0e12" }, angle = 180, noise = 0.012 },
  card = { style = "none" },
  auth = {
    style = "terminal", anchor = "bottom", offset = { 0, -30 }, width = 560, avatar = false, name = false,
    prompt = "locky:~$ ", placeholder = "password", focus = "teal", font = { design = "monospaced", size = 15 },
  },
  widgets = W,
}
