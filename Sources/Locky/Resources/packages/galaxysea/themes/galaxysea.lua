-- Galaxy Sea: the Milky Way over a sea so calm it mirrors it, and a small boat on the horizon. After "Floating in
-- Space", one of Wallpaper Engine's most subscribed wallpapers.
return {
  name = "Galaxy Sea",
  description = "The Milky Way mirrored in a calm sea, a small boat on the horizon, and the odd meteor.",
  palette = {
    bg = "#070418", fg = "#fbf4ff", muted = "#e9dcf5a6", accent = "#f0a6c8", surface = "#ffffff12", border = "#ffffff24",
    -- The scene: the sky at the horizon, then the galaxy's violet, pink core, and blue edge.
    horizon = "#26174a", violet = "#5d3fa3", pink = "#e27fa4", blue = "#7fcfff",
  },
  font = { family = "Didot" },
  background = {
    -- params: the horizon (points from the top) and the boat's x (9999 hides it).
    shader = "galaxysea", colors = { "bg", "horizon", "violet", "pink", "blue" }, params = { 610, 330 }, resolution = 0.5, fps = 24,
  },
  card = { style = "glass", radius = 18 },
  auth = {
    style = "pill", anchor = "bottom", offset = { 0, -86 }, width = 250, avatar = false, name = false,
    placeholder = "password", focus = "accent",
  },
  widgets = {
    { "clock", anchor = "top-left", offset = { 110, 96 },
      opts = { format = "HH:mm", size = 124, font = "Didot", weight = "regular", tracking = 2, shadow = 18, color = "fg", numeric = false } },
    { "date", anchor = "top-left", offset = { 116, 252 },
      opts = { format = "EEEE, d MMMM", size = 20, font = "Didot", italic = true, color = "muted", shadow = 8 } },
    { "moon", anchor = "top-right", offset = { -60, 60 }, opts = { style = "symbol", size = 40 } },
    { "weather", anchor = "bottom-left", offset = { 44, -40 }, opts = { style = "line", size = 13 } },
    { "battery", anchor = "bottom-right", offset = { -44, -40 }, card = false, opts = { style = "compact", size = 13 } },
  },
}
