-- away: when the screen locked, how long ago, and wrong passwords since, like hyprlock's $FAIL and $ATTEMPTS.
--   Families: inline ("Locked 14:53 · 2 wrong passwords"), circular, rectangular, small.
--   opts.style   "line" (default) or "stack"; opts.size, opts.color
local ui = locky.ui

local function span(seconds)
  local m = seconds // 60
  if m < 1 then
    return "just now"
  elseif m < 60 then
    return m .. " min ago"
  end
  return ("%d h %02d min ago"):format(m // 60, m % 60)
end

local function wrong(n)
  return ("%d wrong password%s"):format(n, n == 1 and "" or "s")
end

-- Apple's layouts: monochrome on the Lock Screen, the wrong passwords in the danger color on the card.
local function family(s, f)
  local at = locky.date.format("time", s.since)
  local ago = span(s.now - s.since)
  local lock = s.failed > 0 and "exclamationmark.lock.fill" or "lock.fill"
  if f == "inline" then
    local text = ("Locked %s · %s"):format(at, s.failed > 0 and wrong(s.failed) or ago)
    return ui.hstack { spacing = 4, ui.symbol(lock, ui.font("subheadline")), ui.text(text, ui.font("subheadline", { mono = true, lines = 1 })) }
  elseif f == "circular" then
    local m = (s.now - s.since) // 60
    local short = m < 1 and "now" or m < 60 and (m .. "m") or (m // 60 .. "h")
    return ui.vstack {
      spacing = 1,
      ui.symbol(lock, { size = 16, weight = "medium" }),
      ui.text(at, { size = 15, weight = "semibold", mono = true }),
      ui.text(s.failed > 0 and (s.failed .. " wrong") or short, { size = 10, weight = "semibold", color = "muted", mono = true }),
    }
  elseif f == "rectangular" then
    return ui.vstack {
      spacing = 1, align = "leading", fill = "both",
      ui.hstack { spacing = 5, ui.symbol(lock, ui.font("headline")), ui.text("Locked", ui.font("headline")) },
      ui.text(at, ui.font("title2", { weight = "semibold", mono = true })),
      ui.text(s.failed > 0 and wrong(s.failed) or ago, ui.font("subheadline", { color = "muted", lines = 1 })),
    }
  end
  return ui.vstack {
    spacing = 0, align = "leading", fill = "both",
    ui.hstack { spacing = 5, ui.symbol("lock.fill", ui.font("subheadline", { weight = "semibold" })), ui.text("Locked", ui.font("subheadline", { weight = "semibold" })) },
    ui.spacer(),
    ui.text(at, { size = 44, weight = "semibold", mono = true, lines = 1 }),
    ui.text(ago, ui.font("subheadline", { weight = "medium", color = "muted", lines = 1 })),
    s.failed > 0 and ui.hstack {
      spacing = 4, color = "danger", padding = { 6, 0, 0, 0 },
      ui.symbol("exclamationmark.triangle.fill", ui.font("footnote")),
      ui.text(wrong(s.failed), ui.font("footnote", { weight = "semibold", lines = 1 })),
    },
  }
end

locky.widget.define("away", {
  description = "When the screen locked, and wrong passwords since",
  opts = { style = "line", size = 13 },
  choices = { style = { "line", "stack" } },
  families = { "inline", "circular", "rectangular", "small" },
  init = function(self)
    self.state.since, self.state.failed = os.time(), 0
    self:on("auth_failed", function(self)
      self:set({ failed = self.state.failed + 1 })
    end)
    self:every(60, function(self)
      self:set({ now = os.time() })
    end, { align = true })
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.now then
      return nil
    end
    if self.family then
      return family(s, self.family)
    end
    local locked = ("Locked at %s · %s"):format(locky.date.format("time", s.since), span(s.now - s.since))
    local failed = s.failed > 0 and ui.hstack {
      spacing = 5,
      ui.symbol("exclamationmark.triangle.fill", { size = o.size, color = "danger" }),
      ui.text(("%d wrong password%s"):format(s.failed, s.failed == 1 and "" or "s"), { size = o.size, color = "danger" }),
    }
    if o.style == "stack" then
      return ui.vstack { spacing = 4, align = "leading", ui.text(locked, { size = o.size, color = o.color or "muted" }), failed }
    end
    return ui.hstack { spacing = 12, ui.text(locked, { size = o.size, color = o.color or "muted" }), failed }
  end,
})
