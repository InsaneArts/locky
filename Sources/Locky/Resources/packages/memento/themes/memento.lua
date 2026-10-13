-- Memento: memento mori for the year, after the "year progress" counters power users keep. The day of the year, a dot
-- for every day (the past ones filled), how much of the day, week, and month is left, and a stoic's word.
return {
  name = "Memento",
  description = "Memento mori: the day of the year, a dot for every day, and a stoic's word.",
  palette = {
    bg = "#121110", fg = "#ece6da", muted = "#8c857a", accent = "#c9a96e", surface = "#2a2724", border = "#ece6da30",
  },
  font = { family = "Hoefler Text" },
  background = { gradient = { "#171614", "#0c0b0a" }, angle = 180, noise = 0.05 },
  card = { style = "none" },
  auth = {
    style = "underline", anchor = "bottom", offset = { 0, -56 }, width = 240, avatar = false, name = false,
    placeholder = "", focus = "accent", font = { family = "Hoefler Text", size = 15 },
  },
  widgets = {
    { "date", anchor = "top", offset = { 0, 48 },
      opts = { format = "EEEE · d MMMM yyyy", size = 13, font = "Hoefler Text", case = "upper", tracking = 6, color = "muted", shadow = 0 } },
    { "memento.day", anchor = "top", offset = { 0, 96 } },
    { "progress", anchor = "center", offset = { 0, -10 }, opts = { style = "dots", columns = 37, size = 22, color = "fg", track = "surface" } },
    { "progress", anchor = "center", offset = { 0, 150 }, opts = { style = "text", show = { "day", "week", "month" }, size = 13, color = "muted" } },
    { "quote", anchor = "bottom", offset = { 0, -150 },
      opts = { font = "Hoefler Text", italic = true, size = 20, max_width = 760, every = 60, quotes = {
        { "It is not that we have a short time to live, but that we waste a lot of it.", "Seneca" },
        { "Begin at once to live, and count each separate day as a separate life.", "Seneca" },
        { "Let us prepare our minds as if we had come to the very end of life.", "Seneca" },
        { "You could leave life right now. Let that determine what you do and say and think.", "Marcus Aurelius" },
        { "Waste no more time arguing what a good man should be. Be one.", "Marcus Aurelius" },
        { "Think of yourself as dead. You have lived your life. Now take what is left and live it properly.", "Marcus Aurelius" },
        { "First say to yourself what you would be; and then do what you have to do.", "Epictetus" },
      } } },
    { "clock", anchor = "top-right", offset = { -48, 40 },
      opts = { format = "HH:mm", size = 22, font = "Hoefler Text", weight = "regular", color = "muted", shadow = 0, tracking = 2, numeric = false } },
  },
}
