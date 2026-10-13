-- Lookout: layered ridges fading into haze and a fire lookout on the near ridge, in the light of the real time of day:
-- dawn pink, day gold, dusk orange, and a starry blue night with the lookout's window lit. After the Firewatch-style
-- mountain wallpapers that are perennial Wallpaper Engine favorites.
return {
  name = "Lookout",
  description = "Layered ridges and a fire lookout in the light of the real time of day, from dawn to a starry night.",
  palette = {
    bg = "#2d0c1e", fg = "#fff3e2", muted = "#ffe9cfb3", accent = "#fb8b24", surface = "#2d0c1e99", border = "#ffffff26",
    -- The scene at dusk: the sky low down, the far and near ridges, and the sun. Day and night are worked out from these.
    glow = "#f7a35c", far = "#c1543b", near = "#3a0d1f", sun = "#ffd38a",
  },
  font = { family = "Futura", weight = "medium" },
  background = {
    -- params: the hour to show (-1 follows the clock), how many birds.
    shader = "lookout", colors = { "bg", "glow", "far", "near", "sun" }, params = { -1, 1 }, resolution = 0.5, fps = 24,
  },
  card = { style = "glass", radius = 14 },
  auth = {
    style = "pill", anchor = "bottom", offset = { 0, -60 }, width = 250, avatar = false, name = false,
    placeholder = "password", focus = "accent", font = { family = "Futura", size = 14 },
  },
  widgets = {
    { "clock", anchor = "top-left", offset = { 96, 70 },
      opts = { format = "HH:mm", size = 120, font = "Futura", weight = "medium", tracking = 1, shadow = 14, color = "fg", numeric = false } },
    { "date", anchor = "top-left", offset = { 102, 214 },
      opts = { format = "EEEE d MMMM", size = 16, font = "Futura", weight = "medium", case = "upper", tracking = 4, color = "muted", shadow = 6 } },
    { "sun", anchor = "top-right", offset = { -80, 76 }, opts = { width = 260 } },
    { "weather", anchor = "top-right", offset = { -84, 250 }, opts = { style = "line", size = 14 } },
    { "battery", anchor = "bottom-right", offset = { -44, -40 }, card = false, opts = { style = "compact", size = 13 } },
  },
}
