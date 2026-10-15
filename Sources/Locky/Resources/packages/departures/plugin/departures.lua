-- Departures: a flip clock and a split-flap board of herdr agents.
--
--   departures.clock    two flip cards, hours and minutes
--   departures.board    a Solari-style board: FLIGHT / DESTINATION / GATE / REMARKS, one row per agent
--   departures.footer   one small mono line: battery and uptime
local ui = locky.ui
local herdr = require("locky.herdr")

-- A date template made only of letters is localized ("mm" becomes "m", "HH" becomes "HH 'Uhr'" in
-- German). A quoted word joiner (invisible, zero width) makes Locky use the pattern as written.
local RAW = "'\u{2060}'"

-------------------------------------------------------------------------------
-- The flip clock
-------------------------------------------------------------------------------

-- One flip card: two halves, the digits, the split, and the hinge notches at both ends of the split.
local function card(o, digits, ampm)
  local s, half = o.size, o.size / 2
  local notch = { width = s * 0.028, height = s * 0.062, radius = s * 0.007, color = o.split }
  return ui.zstack {
    width = s, height = s, radius = o.radius, clip = true,
    border = { "#ffffff14", "#ffffff00", angle = 180 }, border_width = 1,
    ui.rect({ width = s, height = s, color = o.card }),
    ui.rect({ width = s, height = half, color = { "#ffffff05", "#ffffff00", angle = 180 }, offset = { 0, -half / 2 } }),
    ui.rect({ width = s, height = half, color = { "#00000000", "#00000026", angle = 180 }, offset = { 0, half / 2 } }),
    -- numeric = false: rolling digits this large cost about 0.8 s of CPU at each minute change.
    ui.time(RAW .. digits, {
      font = o.font, weight = o.weight, size = o.digits, color = o.color, tracking = o.tracking, mono = true,
      numeric = false, offset = { 0, -o.digits * 0.018 },
    }),
    ampm and ui.time("a", {
      font = o.font, weight = o.weight, size = s * 0.058, color = o.color, opacity = 0.9,
      fill = true, align = "top-leading", padding = { s * 0.075, s * 0.085, 0, 0 },
    }),
    ui.rect({ width = s, height = o.split_width, color = o.split }),
    ui.rect({ width = s, height = 1, color = "#ffffff", opacity = 0.035, offset = { 0, o.split_width / 2 + 0.5 } }),
    ui.rect(locky.tbl.extend("force", notch, { offset = { -half, 0 } })),
    ui.rect(locky.tbl.extend("force", notch, { offset = { half, 0 } })),
  }
end

-- opts.hour24: leave it out to follow the system, or set true or false for 24- or 12-hour time.
locky.widget.define("departures.clock", {
  description = "A flip clock: hours and minutes on two split cards",
  opts = {
    size = 360, gap = 28, radius = 30, digits = 266, tracking = -4,
    font = "Helvetica Neue", weight = "bold",
    color = "digit", card = "surface",
    split = "bg", split_width = 2,
  },
  render = function(self)
    local o = self.opts
    local hour24 = o.hour24
    if hour24 == nil then
      hour24 = locky.date.locale().hour24
    end
    return ui.hstack {
      spacing = o.gap,
      card(o, hour24 and "HH" or "h", not hour24),
      card(o, "mm", false),
    }
  end,
})

-------------------------------------------------------------------------------
-- The board
-------------------------------------------------------------------------------

-- Two-letter "airline" codes for agent kinds; other kinds use their first two letters.
local CODES = {
  claude = "CL", codex = "CX", gemini = "GM", opencode = "OC", cursor = "CU", amp = "AM", aider = "AD",
  copilot = "CP", goose = "GO", droid = "DR", pi = "PI", qwen = "QW", kiro = "KR", crush = "CR",
}

local REMARKS = {
  blocked = { "NEEDS YOU", "warning" },
  done = { "DONE", "muted" },
  working = { "WORKING", "success" },
  idle = { "IDLE", "idle" },
}

local function code(kind)
  local k = tostring(kind or ""):lower()
  if CODES[k] then
    return CODES[k]
  end
  local letters = k:gsub("[^%a]", ""):upper()
  return #letters >= 2 and letters:sub(1, 2) or "AG"
end

-- Punctuation that has a flap of its own, or a stand-in for it.
local PUNCTUATION = {
  ["\u{00B7}"] = "\u{00B7}", ["\u{2010}"] = "-", ["\u{2011}"] = "-", ["\u{2012}"] = "-", ["\u{2013}"] = "-",
  ["\u{2014}"] = "-", ["\u{2018}"] = "'", ["\u{2019}"] = "'", ["\u{02BC}"] = "'", ["\u{2026}"] = "...",
}

-- Letters of any script (accented Latin, Greek, Cyrillic, Georgian, CJK, ...), by code point.
local function is_letter(cp)
  return (cp >= 0xC0 and cp <= 0x24F and cp ~= 0xD7 and cp ~= 0xF7) or (cp >= 0x370 and cp <= 0x1FFF)
    or (cp >= 0x3040 and cp <= 0x9FFF) or (cp >= 0xAC00 and cp <= 0xD7AF)
end

-- Board text: letters, digits, and a little punctuation, one space between words. Emoji and symbols
-- become spaces. The flaps show it in capitals.
local function board_text(s)
  local out = {}
  for ch in tostring(s or ""):gmatch(utf8.charpattern) do
    if #ch == 1 then
      out[#out + 1] = ch:match("[%w%-%.,:;!%?&%+/#'%(%)@%%]") or " "
    else
      local ok, cp = pcall(utf8.codepoint, ch, 1, 1, true)
      out[#out + 1] = PUNCTUATION[ch] or (ok and is_letter(cp) and ch) or " "
    end
  end
  return locky.str.trim((table.concat(out):gsub("%s+", " ")))
end

-- The characters of a string, one per flap.
local function chars(s)
  local list = {}
  for ch in s:gmatch(utf8.charpattern) do
    list[#list + 1] = ch
  end
  return list
end

local TRAILING = " -,:;/&+\u{00B7}"

-- Cuts `s` to `n` characters, at a word break when one is close.
local function fit(s, n)
  local list = chars(s)
  if #list <= n then
    return s
  end
  local cut = n
  if list[n + 1] ~= " " then
    for i = n, math.ceil(n * 0.6), -1 do
      if list[i] == " " or list[i] == "-" or list[i] == "/" then
        cut = i - 1
        break
      end
    end
  end
  while cut > 0 and TRAILING:find(list[cut], 1, true) do
    cut = cut - 1
  end
  return table.concat(list, "", 1, cut)
end

-- The columns, in tiles. A column gap is one tile of empty space.
local COLUMNS = {
  { key = "flight", label = "FLIGHT", tiles = 4 },
  { key = "destination", label = "DESTINATION", tiles = 20 },
  { key = "gate", label = "GATE", tiles = 11 },
  { key = "remarks", label = "REMARKS", tiles = 9 },
}

-- Board order: who needs you, who is working, then who is done (and idle, when listed).
local ORDER = { blocked = 1, working = 2, done = 3, idle = 4 }

local function slots()
  local n = #COLUMNS - 1
  for _, c in ipairs(COLUMNS) do
    n = n + c.tiles
  end
  return n
end

-- What the board shows: a list of rows, each a list of { text, color } per column, plus a message row.
local function rows_for(data, o)
  if data == nil then
    return {}
  end
  if data == false then
    return { message = o.offline }
  end
  local agents = {}
  for i, a in ipairs(data.agents) do
    if ORDER[a.status] and (a.status ~= "idle" or o.idle) then
      agents[#agents + 1] = { a = a, rank = ORDER[a.status] * 1000 + i }
    end
  end
  table.sort(agents, function(x, y) return x.rank < y.rank end)
  local rows = {}
  for i = 1, math.min(#agents, o.rows) do
    local a = agents[i].a
    rows[i] = {
      flight = { code(a.kind) .. (i < 10 and " " or "") .. i, "fg" },
      destination = { fit(board_text(a.title), COLUMNS[2].tiles), "fg" },
      gate = { fit(board_text(a.workspace), COLUMNS[3].tiles), "fg" },
      remarks = { REMARKS[a.status][1], REMARKS[a.status][2] },
    }
  end
  if #rows == 0 then
    rows.message = o.empty
  end
  return rows
end

-- A key for the visible content, so the board redraws only when it changed.
local function key_for(rows, counts)
  if rows.message then
    return rows.message
  end
  local parts = {}
  for _, r in ipairs(rows) do
    parts[#parts + 1] = table.concat({ r.flight[1], r.destination[1], r.gate[1], r.remarks[1] }, "|")
  end
  if counts then
    parts[#parts + 1] = ("%d/%d/%d"):format(counts.blocked, counts.working, counts.done)
  end
  return table.concat(parts, "\n")
end

locky.widget.define("departures.board", {
  description = "A split-flap departures board of herdr agents",
  opts = {
    rows = 5,          -- most agents listed
    idle = false,      -- true lists idle agents too, after the others
    tile = { 19, 27 }, -- one flap, in points
    gap = 3,           -- between flaps
    row_gap = 5,
    size = 21,         -- letter size on the flaps
    font = "HelveticaNeue-CondensedBold",
    title = "Departures",
    offline = "No departures · herdr offline",
    empty = "No departures",
  },
  init = function(self)
    herdr.watch(self, function(self, data)
      local rows = rows_for(data, self.opts)
      local key = key_for(rows, data and data.counts)
      if key ~= self.state.key then
        self:set({ key = key, rows = rows, counts = data and data.counts or false })
      end
    end)
  end,
  render = function(self)
    local o = self.opts
    local tw, th, g = o.tile[1], o.tile[2], o.gap
    local width = slots() * (tw + g) - g
    local rows = self.state.rows or {}

    local letter = {
      font = o.font, weight = "bold", size = o.size, case = "upper", lines = 1,
      width = tw, height = th, background = "flap", radius = 2,
    }
    local blank = ui.text(" ", letter)
    local space = ui.rect({ width = tw, height = th })

    local function tiles(text, n, color, out)
      local list = chars(text)
      for i = 1, n do
        local ch = list[i]
        if ch == nil or ch == " " then
          out[#out + 1] = blank
        else
          out[#out + 1] = ui.text(ch, locky.tbl.extend("force", letter, { color = color }))
        end
      end
    end

    local function row(r)
      local cells = {}
      if r and r.message then
        tiles(fit(board_text(r.message), slots()), slots(), "muted", cells)
      else
        for c, col in ipairs(COLUMNS) do
          if c > 1 then
            cells[#cells + 1] = space
          end
          local value = r and r[col.key]
          tiles(value and value[1] or "", col.tiles, value and value[2] or "fg", cells)
        end
      end
      -- The split across the row, and a little shade on the lower flaps.
      return ui.zstack {
        ui.hstack { spacing = g, cells },
        ui.rect({ width = width, height = th / 2, color = "#000000", opacity = 0.1, offset = { 0, th / 4 } }),
        ui.rect({ width = width, height = 1, color = "bg" }),
      }
    end

    local list = {}
    for i = 1, o.rows do
      if i == 1 and rows.message then
        list[i] = row({ message = rows.message })
      else
        list[i] = row(rows[i])
      end
    end

    local labels = {}
    for c, col in ipairs(COLUMNS) do
      if c > 1 then
        labels[#labels + 1] = ui.rect({ width = tw, height = 1 })
      end
      labels[#labels + 1] = ui.text(col.label, {
        font = o.font, weight = "bold", size = 12, tracking = 1.6, color = "muted",
        width = col.tiles * (tw + g) - g, text_align = "leading",
      })
    end

    local counts = self.state.counts
    local summary = {}
    if counts then
      for _, s in ipairs({ { "blocked", "NEEDS YOU" }, { "working", "WORKING" }, { "done", "DONE" } }) do
        local n = counts[s[1]] or 0
        if n > 0 then
          summary[#summary + 1] = ui.hstack {
            spacing = 5,
            ui.text(n, { font = o.font, weight = "bold", size = 14, color = REMARKS[s[1]][2], mono = true }),
            ui.text(s[2], { font = o.font, weight = "bold", size = 14, tracking = 1.2, color = "muted" }),
          }
        end
      end
    end

    return ui.vstack {
      align = "leading", spacing = 0,
      ui.zstack {
        width = width,
        ui.hstack {
          fill = "width", align = "leading", spacing = 12,
          ui.symbol("airplane.departure", { size = 24, weight = "semibold", color = "accent" }),
          ui.text(o.title, { font = o.font, weight = "bold", size = 30, tracking = 5, case = "upper", color = "accent" }),
        },
        ui.hstack { fill = "width", align = "trailing", spacing = 18, summary },
      },
      ui.hstack { spacing = g, padding = { 16, 0, 8, 0 }, labels },
      ui.vstack { spacing = o.row_gap, list },
    }
  end,
})

-------------------------------------------------------------------------------
-- The footer
-------------------------------------------------------------------------------

local function uptime(seconds)
  local d, h, m = seconds // 86400, seconds % 86400 // 3600, seconds % 3600 // 60
  return d > 0 and ("%dD %02dH"):format(d, h) or ("%dH %02dM"):format(h, m)
end

locky.widget.define("departures.footer", {
  description = "Battery and uptime in one small mono line",
  opts = { size = 11, color = "muted", tracking = 1.5 },
  init = function(self)
    self:every(60, function(self)
      local parts = {}
      local b = locky.sys.battery()
      if b and b.present and b.percent then
        parts[#parts + 1] = ("BATTERY %d%%"):format(b.percent) .. (b.charging and " CHARGING" or "")
      end
      parts[#parts + 1] = "UP " .. uptime(locky.sys.uptime())
      local text = table.concat(parts, "  ·  ")
      if text ~= self.state.text then
        self:set({ text = text })
      end
    end)
  end,
  render = function(self)
    local o = self.opts
    if not self.state.text then
      return nil
    end
    return ui.text(self.state.text, { design = "monospaced", weight = "medium", size = o.size, tracking = o.tracking, color = o.color })
  end,
})
