-- Poster: the International Typographic Style. A Swiss poster made of the time.
--
-- Everything sits on one 12-column grid on the 1440 x 900 layout: 72-point margins, 86-point columns,
-- 24-point gutters. At font size 855 each pair of digits spans 8 columns: the hours columns 1-8, the minutes
-- columns 5-12. The info blocks take columns 9-12 above the minutes; the password field sits in columns
-- 1-3 below the hours.
return {
  name = "Poster",
  description = "The time as a Swiss poster: huge numerals cropped by the edges, red overprinting black, small type on a grid.",
  palette = {
    bg = "#F1EFE8", fg = "#0A0A0A", muted = "#7A7872", accent = "#DA291C", border = "#0A0A0A",
    surface = "#E6E3DA", danger = "#DA291C",
  },
  font = { family = "Helvetica Neue" },
  background = { shader = "poster", colors = { "bg" }, params = { 0.035 }, resolution = 1, fps = 1 },
  card = { style = "none" },
  auth = {
    style = "underline", anchor = "bottom-left", offset = { 72, -84 }, width = 306, avatar = false, name = false,
    placeholder = "", font = { family = "Helvetica Neue" },
  },
  widgets = {
    -- The hours hang from the top edge, the minutes stand on the bottom edge, so both crops hold on any
    -- screen. The minutes come second: they overprint the hours.
    { "poster.numerals", anchor = "top-left", size = { 1440, 900 }, opts = { part = "hours" } },
    { "poster.numerals", anchor = "bottom-right", size = { 1440, 900 }, opts = { part = "minutes" } },
    -- Columns 9-12, from the top margin down. Small type keeps to the edges its neighbors keep to.
    { "poster.info", anchor = "top-right", offset = { -72, 48 }, size = { 416, 300 }, align = "top" },
    -- The weekday, the ticks, and the square all stand on the bottom margin line, 48 points up.
    { "poster.weekday", anchor = "bottom-left", offset = { 29, -48 } },
    { "poster.seconds", anchor = "bottom-left", offset = { 72, -46 } },
  },
}
