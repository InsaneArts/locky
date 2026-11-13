-- themes/launch.lua
return {
  name = "Launch Day",
  background = {
    shader = "galaxysea", params = { 610, 330 },
    colors = { "#070418", "#26174a", "#5d3fa3",
               "#e27fa4", "#7fcfff" },
  },
  auth = { style = "pill", anchor = "bottom",
           offset = { 0, -60 } },
  widgets = {
    { "date",  anchor = "top", offset = { 0, 110 },
      opts = { size = 22, weight = "semibold" } },
    { "clock", anchor = "top", offset = { 0, 130 },
      opts = { size = 140 } },
    { "text",  anchor = "center",
      opts = { text = "Locky", size = "huge",
               weight = "semibold" } },
    { "text",  anchor = "center", offset = { 0, 86 },
      opts = { color = "muted", text =
        "The lock screen you build yourself." } },
  },
}
