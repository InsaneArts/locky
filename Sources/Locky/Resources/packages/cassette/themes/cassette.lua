-- Cassette Futurism: a 1970s mission console (Nostromo / MU-TH-UR). Green + amber phosphor on a curved CRT with
-- scanlines, a warning lamp, and engraved mono labels. The CRT look is a scanline overlay over the widgets.
local function label(text, ax, off, color)
  return { "text", anchor = ax, offset = off, opts = { text = text, size = 13, color = color or "amber", case = "upper", tracking = 2, font = "Menlo" } }
end
return {
  name = "Cassette Futurism",
  description = "A 1970s mission console: green-and-amber phosphor on a scanlined CRT, with a warning lamp.",
  author = "Locky",
  palette = {
    bg = "#0c0e0a", fg = "#4de64d", muted = "#6b7355", accent = "#ffb000", surface = "#13170d", border = "#2a3320",
    success = "#4de64d", warning = "#e8c84b", danger = "#d8341e",
    green = "#4de64d", amber = "#ffb000", beige = "#bdb39a", lamp = "#d8341e",
  },
  font = { design = "monospaced", weight = "medium" },
  background = { gradient = { "#0e120b", "#070906" }, angle = 180, noise = 0.02 },
  overlay = { shader = "cassette-crt", fps = 20 },
  card = { style = "outline", radius = 4, border = "border" },
  auth = {
    style = "terminal", anchor = "bottom", offset = { 0, -56 }, width = 440, avatar = false, name = false,
    prompt = "> ", focus = "green", font = { design = "monospaced", size = 15 },
  },
  widgets = {
    -- Top: console banner + warning lamp
    label("// MU-TH-UR 6000  ·  INTERFACE 2037", "top-left", { 70, 54 }, "green"),
    { "text", anchor = "top-right", offset = { -70, 54 }, opts = { text = "● SYSTEMS NOMINAL", size = 13, color = "danger", case = "upper", tracking = 2, font = "Menlo" } },

    -- Center: big phosphor clock + date
    { "clock", anchor = "center", offset = { 0, -26 }, opts = { size = 148, weight = "bold", color = "green", mono = true, tracking = 2, shadow = 0, numeric = false, glow = 10 } },
    { "date", anchor = "center", offset = { 0, 70 }, opts = { format = "EEEE  dd.MM.yyyy", size = 15, color = "amber", case = "upper", tracking = 4 } },

    -- Left: boot log
    { "fetch", anchor = "bottom-left", offset = { 70, -120 }, opts = { size = 12, logo = false, color = "green" } },

    -- Right: telemetry panel
    label("[ TELEMETRY ]", "bottom-right", { -70, -214 }, "amber"),
    { "system", anchor = "bottom-right", offset = { -70, -124 }, size = { 280, 80 }, align = "trailing", opts = { style = "bars", width = 280, color = "amber", color2 = "green", size = 12 } },
    { "battery", anchor = "bottom-right", offset = { -70, -42 }, size = { 280, 30 }, align = "trailing", opts = { style = "row", size = 13, color = "amber" } },
  },
}
