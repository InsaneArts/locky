-- Cyberdeck HUD: a duotone vector instrument panel. Amber for data, cyan for structure, red only for alerts.
-- Corner brackets, a big glowing clock, and telemetry rails tagged like a cockpit: [ SYS ] [ NET ] [ PROC ].
local function corner(c, ax)
  return { "cyberdeck.corner", anchor = ax, offset = ({ ["top-left"] = { 30, 30 }, ["top-right"] = { -30, 30 }, ["bottom-left"] = { 30, -30 }, ["bottom-right"] = { -30, -30 } })[ax], opts = { corner = c, color = "cyan", len = 46, thick = 2 } }
end
local function tag(text, ax, off, color)
  return { "cyberdeck.tag", anchor = ax, offset = off, opts = { text = text, color = color or "cyan", size = 12 } }
end
return {
  name = "Cyberdeck HUD",
  description = "A duotone vector cockpit: corner brackets, a glowing amber clock, and bracketed telemetry rails.",
  author = "Locky",
  palette = {
    bg = "#060a0c", fg = "#ffc24b", muted = "#5b7a82", accent = "#ffb000", surface = "#0e171b", border = "#143038",
    success = "#35e0d4", warning = "#ffb000", danger = "#ff4d3d",
    amber = "#ffc24b", amber2 = "#ffb000", cyan = "#35e0d4", alert = "#ff4d3d",
  },
  font = { design = "monospaced", weight = "medium" },
  background = { gradient = { "#060a0c", "#0a1418" }, angle = 135, noise = 0.02 },
  card = { style = "none" },
  auth = {
    style = "terminal", anchor = "bottom", offset = { 0, -58 }, width = 440, avatar = false, name = false,
    prompt = "AUTH> ", focus = "cyan", font = { design = "monospaced", size = 15 },
  },
  widgets = {
    corner("tl", "top-left"), corner("tr", "top-right"), corner("bl", "bottom-left"), corner("br", "bottom-right"),

    -- Center: status line + big glowing clock + date
    tag("SYS · SECURED", "top", { 0, 46 }, "cyan"),
    { "clock", anchor = "center", offset = { 0, -36 },
      opts = { size = 150, weight = "bold", color = "amber", mono = true, tracking = -3, shadow = 0, numeric = false, glow = 12 } },
    { "date", anchor = "center", offset = { 0, 74 }, opts = { format = "EEE dd.MM.yyyy", size = 15, color = "cyan", case = "upper", tracking = 4 } },

    -- Left rail: SYS bars + power
    tag("SYS", "left", { 96, -56 }, "cyan"),
    { "system", anchor = "left", offset = { 96, -22 }, opts = { style = "bars", width = 230, color = "amber", color2 = "cyan", size = 12 } },
    tag("PWR", "left", { 96, 78 }, "cyan"),
    { "battery", anchor = "left", offset = { 96, 106 }, opts = { style = "row", size = 13, color = "amber" } },

    -- Right rail: NET chart + disk (network fills on the live lock)
    tag("NET", "right", { -326, -56 }, "cyan"),
    { "network", anchor = "right", offset = { -96, -22 }, size = { 230, 70 }, align = "top-trailing", opts = { style = "chart", width = 230, color = "cyan", size = 12 } },
    tag("VOL", "right", { -326, 78 }, "cyan"),
    { "disk", anchor = "right", offset = { -96, 106 }, size = { 230, 40 }, align = "trailing", opts = { style = "bar", width = 230, color = "amber", label = "Macintosh HD" } },

    -- Bottom: process ticker (fills live) + uptime
    tag("PROC", "bottom-left", { 96, -150 }, "cyan"),
    { "top", anchor = "bottom-left", offset = { 96, -40 }, opts = { rows = 4, width = 340, size = 12, sort = "cpu" } },
    { "uptime", anchor = "bottom-right", offset = { -96, -46 }, opts = { size = 12, color = "muted", label = "UPTIME" } },
  },
}
