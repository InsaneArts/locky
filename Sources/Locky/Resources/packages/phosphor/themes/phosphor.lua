-- Phosphor: an amber CRT terminal, after cool-retro-term. A shell session fills the top-left of the tube, and
-- the password prompt is its next line.
local left, top, height = 64, 52, 604  -- the session's box; the prompt starts where it ends

return {
  name = "Phosphor",
  description = "An amber CRT terminal: a shell session with a block clock, neofetch, and herdr's agents.",
  palette = {
    bg = "#0D0700", fg = "#FFB000", muted = "#B37B00", accent = "#FFB000", surface = "#1A0F00",
    border = "#FFB00055", danger = "#FF5F3F", bright = "#FFC547",
  },
  font = { design = "monospaced" },
  background = {
    shader = "phosphor", colors = { "#0D0700", "#050200", "fg" },
    params = { 6, 1, 1, 1 }, resolution = 0.5, fps = 24,
  },
  overlay = { shader = "phosphor-overlay", params = { 300, 0.16, 0.4, 1 }, resolution = 1, fps = 10 },
  card = { style = "none" },
  auth = {
    style = "terminal", anchor = "top-left", offset = { left, top + height }, width = 420,
    avatar = false, name = false, hint = false, placeholder = "",
    glow = 3,  -- the same glow as the transcript, so the prompt reads as part of it
  },
  widgets = {
    { "phosphor.session", anchor = "top-left", offset = { left, top }, size = { 900, height } },
    { "phosphor.notice", anchor = "top-left", offset = { left, top + height + 17 } },
  },
}
