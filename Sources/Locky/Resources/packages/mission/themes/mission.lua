-- Mission: the lock screen as a flight controller's console. The clock counts mission elapsed time from the moment
-- the screen locked; around it, the time in UTC and Unix, the Mac's telemetry, a binary time code, and the
-- downlink.
return {
  name = "Mission",
  description = "A flight controller's console: mission elapsed time since lock, telemetry, UTC, and the downlink.",
  palette = {
    bg = "#05070a", fg = "#e9eef5", muted = "#7c8899", accent = "#ff9f1c", secondary = "#5ce1e6", surface = "#1a222d",
    border = "#2a3442", success = "#4ade80", warning = "#ff9f1c", danger = "#ff4d4d",
    grid = "#0f1824", vignette = "#000000",
  },
  font = { design = "monospaced" },
  background = { shader = "mission", colors = { "bg", "grid", "vignette" }, resolution = 0.5, fps = 1 },
  card = { style = "outline", radius = 4, border = "border" },
  auth = {
    style = "terminal", anchor = "bottom-left", offset = { 60, -60 }, width = 420, avatar = false, name = false,
    prompt = "AUTH> ", focus = "accent", font = { design = "monospaced", size = 15 },
  },
  widgets = {
    { "mission.header", anchor = "top", offset = { 0, 28 } },
    { "mission.met", anchor = "top-left", offset = { 60, 96 }, opts = { size = 70 } },
    { "clock", anchor = "top-left", offset = { 64, 210 },
      opts = { format = "HH:mm", size = 26, design = "monospaced", weight = "regular", color = "muted", shadow = 0, numeric = false } },
    { "mission.clocks", anchor = "top-right", offset = { -60, 104 }, card = true, opts = {} },
    { "mission.telemetry", anchor = "left", offset = { 60, 70 }, card = true },
    { "nerdclock", anchor = "top-right", offset = { -60, 300 }, card = true, opts = { style = "binary", size = 14, color = "accent" } },
    { "network", anchor = "right", offset = { -60, 110 }, card = true, opts = { style = "chart", width = 300, color = "secondary" } },
    { "progress", anchor = "center", offset = { 40, -120 }, opts = { style = "rings", size = 13, color = "accent", track = "surface" } },
    { "countdown", anchor = "bottom-right", offset = { -60, -60 }, opts = { style = "line", size = 13, color = "muted" } },
  },
}
