-- Glass Cockpit: an aircraft primary flight display. Artificial horizon, airspeed/altitude tapes, magenta
-- flight-director bugs, green in-limits data on instrument black.
return {
  name = "Glass Cockpit",
  description = "An aircraft PFD: artificial horizon, airspeed and altitude tapes, and magenta flight bugs.",
  author = "Locky",
  palette = {
    bg = "#05070a", fg = "#ffffff", muted = "#8fa3b0", accent = "#ff36c8", surface = "#0c1116", border = "#2a3a44",
    success = "#35e06a", warning = "#ffb000", danger = "#ff4d3d",
    magenta = "#ff36c8", green = "#35e06a", amber = "#ffb000", sky = "#1e6fa8", earth = "#6b4a2b",
  },
  font = { design = "monospaced", weight = "medium" },
  background = { gradient = { "#05070a", "#0a0f14" }, angle = 180 },
  card = { style = "none" },
  auth = {
    style = "box", anchor = "bottom", offset = { 0, -48 }, width = 340, avatar = false, name = false,
    placeholder = "ENTER PASSWORD", focus = "magenta", font = { design = "monospaced", size = 14 },
  },
  widgets = {
    { "clock", anchor = "top", offset = { 0, 66 }, opts = { size = 92, weight = "bold", color = "fg", mono = true, tracking = -1, shadow = 0, numeric = false } },
    { "date", anchor = "top", offset = { 0, 158 }, opts = { format = "EEE dd MMM · HH:mm'Z'", size = 13, color = "green", case = "upper", tracking = 2 } },

    { "pfd.horizon", anchor = "center", offset = { 0, 16 }, opts = { w = 600, h = 360, sky = "#1e6fa8", earth = "#6b4a2b", line = "#ffffff", bug = "#ff36c8" } },
    { "pfd.tape", anchor = "left", offset = { 92, 16 }, opts = { label = "SPD", source = "cpu", color = "#35e06a", w = 96, h = 320 } },
    { "pfd.tape", anchor = "right", offset = { -92, 16 }, opts = { label = "ALT", source = "memory", color = "#ffb000", w = 96, h = 320 } },

    { "uptime", anchor = "bottom-left", offset = { 96, -54 }, opts = { size = 12, color = "muted", label = "FLIGHT TIME" } },
    { "battery", anchor = "bottom-right", offset = { -96, -54 }, opts = { style = "compact", size = 13, color = "green" } },
    { "weather", anchor = "bottom", offset = { 0, -118 }, opts = { style = "line", size = 13, color = "muted" } },
  },
}
