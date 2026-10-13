-- Notebook: a page of a ruled school notebook. The time in marker, the day and your to-do list by hand, a sticky
-- note saying you will be back, and a coffee ring.
return {
  name = "Notebook",
  description = "A ruled notebook page: the time in marker, your todo.txt by hand, a sticky note, and a coffee ring.",
  palette = {
    bg = "#fbf8ef", fg = "#22336b", muted = "#7d8597", accent = "#c8333a", surface = "#ffffff", border = "#22336b55",
    ink = "#22336b", pen = "#c8333a", paper = "#fbf8ef", rule = "#8fb3e0", margin = "#e06b6b", desk = "#4a3b2c",
    coffee = "#8a5a2b",
  },
  font = { family = "Bradley Hand" },
  background = { shader = "notebook", colors = { "paper", "rule", "margin", "desk", "coffee" }, params = { 30, 0.11 },
                 resolution = 1, fps = 0 },
  card = { style = "none" },
  auth = {
    style = "underline", anchor = "bottom", offset = { 60, -110 }, width = 300, avatar = false, name = false,
    placeholder = "password", focus = "pen", font = { family = "Bradley Hand", size = 20 },
  },
  widgets = {
    { "clock", anchor = "top-left", offset = { 210, 70 },
      opts = { size = 130, font = "Marker Felt", weight = "regular", color = "ink", tracking = 0, shadow = 0, numeric = false } },
    { "date", anchor = "top-left", offset = { 214, 236 },
      opts = { format = "EEEE, d MMMM", size = 30, font = "Bradley Hand", weight = "bold", color = "ink", shadow = 0 } },
    { "fuzzy", anchor = "top-left", offset = { 214, 280 },
      opts = { size = 22, font = "Bradley Hand", weight = "regular", color = "muted" } },
    { "notebook.todo", anchor = "top-left", offset = { 210, 370 } },
    { "notebook.sticky", anchor = "top-right", offset = { -110, 300 } },
    { "notebook.weather", anchor = "top-right", offset = { -120, 90 } },
  },
}
