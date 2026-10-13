-- Pocket's widgets: a handheld game's screen.
--   pocket.clock   the time in a 5×7 pixel font, each pixel a square. opts.pixel (default 14), opts.color
--   pocket.hud     the game's status bar: battery as hearts, uptime as the score, and the day of the year as the level
local ui = locky.ui

local font = {
  ["0"] = { "01110", "10001", "10011", "10101", "11001", "10001", "01110" },
  ["1"] = { "00100", "01100", "00100", "00100", "00100", "00100", "01110" },
  ["2"] = { "01110", "10001", "00001", "00010", "00100", "01000", "11111" },
  ["3"] = { "11111", "00010", "00100", "00010", "00001", "10001", "01110" },
  ["4"] = { "00010", "00110", "01010", "10010", "11111", "00010", "00010" },
  ["5"] = { "11111", "10000", "11110", "00001", "00001", "10001", "01110" },
  ["6"] = { "00110", "01000", "10000", "11110", "10001", "10001", "01110" },
  ["7"] = { "11111", "00001", "00010", "00100", "01000", "01000", "01000" },
  ["8"] = { "01110", "10001", "10001", "01110", "10001", "10001", "01110" },
  ["9"] = { "01110", "10001", "10001", "01111", "00001", "00010", "01100" },
  [":"] = { "0", "1", "1", "0", "1", "1", "0" },
}

local function glyph(ch, pixel, color)
  local rows = {}
  for r, pattern in ipairs(font[ch]) do
    local cells = {}
    for c = 1, #pattern do
      cells[c] = ui.rect({ width = pixel, height = pixel, color = pattern:sub(c, c) == "1" and color or "#00000000" })
    end
    rows[r] = ui.hstack { spacing = pixel * 0.15, cells }
  end
  return ui.vstack { spacing = pixel * 0.15, rows }
end

locky.widget.define("pocket.clock", {
  description = "The time in a 5×7 pixel font",
  opts = { pixel = 14, color = "fg" },
  init = function(self)
    self:every(60, function(self) self:set({ text = locky.date.format("HH:mm") }) end, { align = true })
  end,
  render = function(self)
    local o, text = self.opts, self.state.text
    if not text then return nil end
    local glyphs = {}
    for i = 1, #text do
      glyphs[i] = glyph(text:sub(i, i), o.pixel, o.color)
    end
    return ui.hstack { spacing = o.pixel * 1.2, glyphs }
  end,
})

locky.widget.define("pocket.hud", {
  description = "Battery as hearts, uptime as the score, the day as the level",
  opts = { width = 1240 },
  init = function(self)
    self:every(60, function(self) self:set({ battery = locky.sys.battery(), uptime = locky.sys.uptime(), now = os.time() }) end, { align = true })
  end,
  render = function(self)
    local o, s = self.opts, self.state
    if not s.now then return nil end
    local hearts = {}
    local full = s.battery.present and math.floor(s.battery.percent / 20 + 0.5) or 5
    for i = 1, 5 do
      hearts[i] = ui.symbol(i <= full and "heart.fill" or "heart", { size = 22, color = "fg" })
    end
    local text = { size = 22, design = "monospaced", weight = "bold", color = "fg" }
    return ui.hstack {
      width = o.width,
      ui.hstack { spacing = 6, hearts },
      ui.spacer(),
      ui.text(("SCORE %06d"):format(s.uptime // 60), text),
      ui.spacer(),
      ui.text(("LV %03d"):format(tonumber(os.date("%j", s.now))), text),
    }
  end,
})
