-- Dieter Rams / Braun: functionalism on warm grey. A Braun analog clock is the single hero, its one yellow
-- second hand the only colour that moves. Down the right, date, weather and calendar sit as quiet labelled
-- blocks on a calm modular grid; thin battery and system readouts rest in the lower left. Less, but better.
local CX = 972                              -- right column: left edge
local CW = 372                              -- right column: width
local LX = CX + 8                           -- label left edge, indented into the block
return {
  name = "Braun",
  description = "Dieter Rams functionalism: a Braun analog clock hero, one yellow accent, quiet labelled blocks on warm grey.",
  author = "Locky",
  palette = {
    bg = "#d8d4cc", fg = "#1a1a1a", muted = "#8c887f", subtle = "#6f6b62",
    surface = "#edebe6", surface2 = "#e4e1da", border = "#c7c2b8",
    accent = "#f5c518", success = "#1a1a1a", warning = "#f5c518", danger = "#f5c518",
    yellow = "#f5c518",
  },
  font = { weight = "regular" },
  background = { color = "#d8d4cc" },
  card = { style = "solid", radius = 6, fill = "surface", border = "border" },
  auth = {
    style = "underline", anchor = "bottom", offset = { 0, -70 }, width = 300, avatar = false, name = false,
    placeholder = "password", focus = "accent", font = { size = 14 }, hint_align = "center",
  },
  widgets = {
    -- The hero: a Braun analog clock, warm-grey face, black hands, numerals, one yellow second hand.
    { "analog", anchor = "left", offset = { 352, -14 },
      opts = { style = "braun", size = 316, seconds = true, face = "surface", hands = "fg", ticks = "muted", second = "accent" } },
    -- Right column, three quiet labelled blocks stacked on a modular grid.
    { "text", anchor = "top-left", offset = { LX, 116 }, opts = { text = "DATE", size = 11, weight = "semibold", color = "muted", alignment = "leading" } },
    { "date", anchor = "top-left", offset = { CX, 144 }, size = { CW, 66 }, align = "leading", card = true,
      opts = { format = "EEEE d MMMM", size = 23, weight = "regular", color = "fg" } },
    { "text", anchor = "top-left", offset = { LX, 234 }, opts = { text = "WEATHER", size = 11, weight = "semibold", color = "muted", alignment = "leading" } },
    { "weather", anchor = "top-left", offset = { CX, 262 }, size = { CW, 282 }, align = "top-leading", card = true,
      opts = { style = "detail", color = "fg", multicolor = false, place = false } },
    { "text", anchor = "top-left", offset = { LX, 568 }, opts = { text = "CALENDAR", size = 11, weight = "semibold", color = "muted", alignment = "leading" } },
    { "calendar", anchor = "top-left", offset = { CX, 596 }, size = { CW, 236 }, align = "top", card = true,
      opts = { title = true, today_color = "accent", size = 15 } },
    -- Thin, bare readouts in the lower left: the accent shows only when attention is needed.
    { "battery", anchor = "bottom-left", offset = { 94, -158 }, card = false, opts = { style = "compact", size = 15, color = "fg", low = 20 } },
    { "system", anchor = "bottom-left", offset = { 94, -74 }, card = false, opts = { style = "bars", width = 236, size = 12, color = "fg", color2 = "muted" } },
  },
}
