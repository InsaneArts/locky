-- The default theme: northern lights over a mountain lake at night, a large rounded clock, and glass cards.
-- It uses only core widgets, because Locky falls back to it when another theme fails to load.
return {
  name = "Aurora",
  description = "Northern lights over a mountain lake at night. Locky's default.",
  palette = {
    bg = "#02040a", fg = "#ffffff", muted = "#ffffffa6", accent = "#22ee88", surface = "#ffffff1f", border = "#ffffff2e",
    -- The scene's own roles. The shader also reads bg (the sky overhead) and accent (the aurora's green core).
    horizon = "#0a1a2f", aurora_base = "#a533f8", aurora_tips = "#1694e8", ridge_far = "#0b1626", ridge_near = "#05080f",
  },
  font = { design = "rounded" },
  background = {
    -- shaders/aurora.metal. params (all default 1): aurora brightness, star density, and the soft glow behind
    -- the clock (0 turns it off, for a clock placed elsewhere).
    shader = "aurora",
    colors = { "bg", "horizon", "accent", "aurora_base", "aurora_tips", "ridge_far", "ridge_near" },
    speed = 1, resolution = 0.5, fps = 30,
  },
  card = { style = "glass", radius = 22 },
  auth = { style = "pill", anchor = "bottom", offset = { 0, -56 }, avatar = true, name = true },
  widgets = {
    { "date", anchor = "top", offset = { 0, 100 }, opts = { size = 20, weight = "semibold", color = "#ffffffd9", shadow = 8 } },
    -- numeric = false: rolling digits this large cost about 0.4 s of CPU at each minute change.
    { "clock", anchor = "top", offset = { 0, 114 }, opts = { size = 150, weight = "light", tracking = -2, shadow = 6, color = "fg", numeric = false } },
    -- A quiet status row in the bottom corners. The keyboard code has a fixed width, so the battery can sit
    -- beside it; without a battery the keyboard keeps the corner. The agents line hides when herdr is off.
    { "agents", anchor = "bottom-left", offset = { 32, -30 }, card = false, opts = { style = "summary", offline = false, size = 12 } },
    { "battery", anchor = "bottom-right", offset = { -92, -30 }, card = false, opts = { style = "compact", size = 12 } },
    { "keyboard", anchor = "bottom-right", offset = { -32, -30 }, opts = { style = "code", size = 12, color = "muted" } },
  },
}
