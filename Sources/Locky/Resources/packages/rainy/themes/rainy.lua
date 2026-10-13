-- Rainy: a lo-fi window on a rainy night. Rain slides down the glass in front of a city out of focus, and the screen
-- says the time the way you would: in words.
return {
  name = "Rainy",
  description = "A lo-fi rainy window: drops sliding down the glass, city lights out of focus, the time in words.",
  palette = {
    bg = "#141826", fg = "#f6ecdf", muted = "#c4b6a6", accent = "#ffb36b", surface = "#ffffff14", border = "#ffffff22",
    sky = "#1b2135", street = "#0c0e17", warm = "#ffa65a", cool = "#6aa7ff",
  },
  font = { family = "Avenir Next", weight = "regular" },
  background = { shader = "rainy", colors = { "sky", "street", "warm", "cool" }, params = { 1 }, resolution = 0.5, fps = 20 },
  card = { style = "glass", radius = 18 },
  auth = {
    style = "pill", anchor = "bottom", offset = { 0, -90 }, width = 260, avatar = false, name = false,
    placeholder = "password", focus = "accent", font = { family = "Avenir Next", size = 14 },
  },
  widgets = {
    { "fuzzy", anchor = "left", offset = { 96, -110 },
      opts = { size = 64, weight = "medium", font = "Avenir Next", text_align = "leading", max_width = 700, prefix = "it's ", color = "fg" } },
    { "date", anchor = "left", offset = { 100, -30 },
      opts = { format = "EEEE, d MMMM", size = 20, font = "Avenir Next", weight = "medium", color = "muted", shadow = 0 } },
    { "weather", anchor = "left", offset = { 100, 14 }, opts = { style = "line", size = 17, multicolor = true } },
    { "quote", anchor = "bottom-left", offset = { 100, -100 },
      opts = { size = 16, italic = true, max_width = 520, text_align = "leading", font = "Avenir Next", color = "muted" } },
    { "clock", anchor = "top-right", offset = { -60, 44 },
      opts = { format = "HH:mm", size = 26, font = "Avenir Next", weight = "medium", color = "muted", shadow = 0, numeric = false } },
  },
}
