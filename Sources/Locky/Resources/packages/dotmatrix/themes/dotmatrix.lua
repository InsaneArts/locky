-- Dot Matrix: a 5x7 dot-matrix clock on a faint dot grid. Black, white, gray, and one red dot.
return {
  name = "Dot Matrix",
  description = "A dot-matrix clock on a ghost dot grid: black, white, and one pulsing red dot.",
  author = "Locky",
  palette = {
    bg = "#000000", fg = "#ffffff", muted = "#8a8a8e", surface = "#00000000", border = "#ffffff4d", danger = "#d71921",
    -- The one red: the colon's pulsing dot and blocked agents.
    signal = "#d71921",
    -- The password field is always focused, and focus draws its border in accent: white keeps it an
    -- outline box and leaves red to the one dot.
    accent = "#ffffff80",
    -- Unlit clock dots: 7% white on black, opaque so the background grid does not show through them.
    dim = "#121212",
  },
  font = { design = "monospaced", weight = "medium" },
  background = { shader = "dotmatrix", colors = { "bg", "fg" }, params = { 12, 1.5, 0.04 }, resolution = 1, fps = 1 },
  card = { style = "outline", radius = 10, border = "border" },
  auth = {
    style = "box", anchor = "bottom", offset = { 0, -84 }, width = 288,
    avatar = false, name = false, placeholder = "PASSWORD", font = { design = "monospaced" },
  },
  widgets = {
    { "dotmatrix.word", anchor = "top", offset = { 0, 216 }, size = { 596, 28 }, align = "leading" },
    { "dotmatrix.agents", anchor = "top", offset = { 0, 216 }, size = { 596, 28 }, align = "trailing" },
    { "dotmatrix.clock", anchor = "top", offset = { 0, 270 } },
    { "dotmatrix.pulse", anchor = "top", offset = { 0, 270 } },
    { "dotmatrix.info", anchor = "top", offset = { 0, 464 } },
  },
}
