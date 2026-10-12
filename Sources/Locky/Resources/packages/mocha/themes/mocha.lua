-- Mocha: the r/unixporn classic. Catppuccin Mocha (MIT) on your blurred wallpaper, with i3lock-color's ring:
-- the password field is the ring, and the time sits inside it.
return {
  name = "Mocha",
  description = "Catppuccin Mocha with an i3lock-color ring.",
  palette = {
    bg = "#1e1e2e", fg = "#cdd6f4", muted = "#a6adc8", accent = "#a6e3a1", success = "#a6e3a1",
    warning = "#f5e0dc", danger = "#eba0ac", border = "#313244", surface = "#313244",
    -- Catppuccin Mocha by name, for the widgets.
    base = "#1e1e2e", mantle = "#181825", crust = "#11111b", text = "#cdd6f4", subtext0 = "#a6adc8",
    overlay0 = "#6c7086", surface0 = "#313244", surface1 = "#45475a", mauve = "#cba6f7", green = "#a6e3a1",
    rosewater = "#f5e0dc", blue = "#89b4fa", maroon = "#eba0ac", peach = "#fab387", yellow = "#f9e2af",
    red = "#f38ba8", lavender = "#b4befe",
    disc = "#181825cc",  -- inside the ring, behind the time: mantle at 80%
  },
  font = { design = "monospaced" },
  background = locky.sys.wallpaper() and { wallpaper = true, blur = 30, dim = 0.15, tint = "bg", tint_amount = 0.8 }
    or { gradient = { "bg", "mantle" }, angle = 180, noise = 0.04 },
  card = { style = "none" },
  auth = { style = "ring", anchor = "center", offset = { 0, 0 }, width = 320, font = { design = "monospaced" } },
  widgets = {
    { "mocha.center", anchor = "center" },
    { "mocha.user", anchor = "top-left", offset = { 36, 32 } },
    { "mocha.status", anchor = "top-right", offset = { -36, 32 } },
    { "mocha.agents", anchor = "bottom-left", offset = { 36, -32 } },
    { "mocha.label", anchor = "bottom-right", offset = { -36, -32 } },
  },
}
