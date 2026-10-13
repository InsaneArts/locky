-- Tokyo Night: the hyprlock look the Linux crowd made famous, in folke's Tokyo Night colors. Your wallpaper, blurred
-- and tinted (or a neon night when there is none), hours over minutes in two colors, and status in the corners.
return {
  name = "Tokyo Night",
  description = "The hyprlock look in Tokyo Night colors: split clock, weather, and status in the corners.",
  palette = {
    bg = "#1a1b26", fg = "#c0caf5", muted = "#565f89", accent = "#7aa2f7", surface = "#24283bcc", border = "#414868",
    success = "#9ece6a", warning = "#e0af68", danger = "#f7768e",
    blue = "#7aa2f7", magenta = "#bb9af7", cyan = "#7dcfff", orange = "#ff9e64", lights = "#e0af68",
  },
  font = { design = "monospaced", weight = "medium" },
  background = locky.sys.wallpaper() and { wallpaper = true, blur = 40, dim = 0.2, tint = "bg", tint_amount = 0.55 }
    or { shader = "tokyonight", colors = { "bg", "blue", "magenta", "lights" }, resolution = 0.5, fps = 20 },
  card = { style = "solid", radius = 14, fill = "surface", border = "border" },
  auth = {
    style = "pill", anchor = "bottom", offset = { 0, -110 }, width = 300, avatar = true, name = false,
    placeholder = "password…", focus = "magenta", font = { design = "monospaced", size = 14 },
  },
  widgets = {
    { "clock", anchor = "top", offset = { 0, 90 },
      opts = { stacked = true, size = 170, weight = "heavy", design = "monospaced", color = "blue", minutes_color = "magenta",
               tracking = 0, shadow = 0, numeric = false } },
    { "date", anchor = "center", offset = { 0, 50 }, opts = { format = "skeleton:EEEEdMMMM", size = 20, weight = "semibold", color = "cyan", shadow = 0 } },
    { "greeting", anchor = "center", offset = { 0, 86 }, opts = { size = 16, weight = "regular", color = "fg" } },
    { "weather", anchor = "top-right", offset = { -32, 28 }, opts = { style = "line", size = 14 } },
    { "battery", anchor = "top-left", offset = { 32, 28 }, card = false, opts = { style = "compact", size = 14 } },
    { "away", anchor = "bottom-left", offset = { 32, -28 }, opts = { size = 12 } },
    { "keyboard", anchor = "bottom-right", offset = { -32, -28 }, opts = { style = "code", size = 12, color = "muted" } },
  },
}
