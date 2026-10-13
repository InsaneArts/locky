-- life: Conway's Game of Life, quietly evolving: a toy for a screen nobody is using. It starts from a random soup and
-- starts again when it settles. Drawn as rows of text, so a large board stays cheap.
--   opts.columns, opts.rows   the board (default 40 by 20); opts.every seconds per generation (default 0.5)
--   opts.cell    the character for a live cell (default "●"); opts.dead true marks dead cells with "·"
--   opts.size (default 10), opts.color
--   Families: small, medium, large: a grid of quiet dots, the live ones lit, sized to the family.
local ui = locky.ui

-- Each family's board, in cells of `pitch` points: its content area (size less Apple's margins), less a line for
-- the caption under medium and large.
local pitch = 9.2
local boards = { small = { 15, 15 }, medium = { 36, 13 }, large = { 36, 36 } }

--- The next generation of `board` (rows of booleans), on a torus.
local function step(board, columns, rows)
  local next = {}
  for y = 1, rows do
    local row = {}
    for x = 1, columns do
      local n = 0
      for dy = -1, 1 do
        local line = board[(y + dy - 1) % rows + 1]
        for dx = -1, 1 do
          if (dx ~= 0 or dy ~= 0) and line[(x + dx - 1) % columns + 1] then
            n = n + 1
          end
        end
      end
      row[x] = n == 3 or (n == 2 and board[y][x])
    end
    next[y] = row
  end
  return next
end

local function soup(columns, rows)
  local board = {}
  for y = 1, rows do
    board[y] = {}
    for x = 1, columns do
      board[y][x] = math.random() < 0.3
    end
  end
  return board
end

local function key(board)
  local parts = {}
  for y, row in ipairs(board) do
    local bits = {}
    for x, alive in ipairs(row) do
      bits[x] = alive and "1" or "0"
    end
    parts[y] = table.concat(bits)
  end
  return table.concat(parts, "/")
end

locky.widget.define("life", {
  description = "Conway's Game of Life, evolving quietly",
  opts = { columns = 40, rows = 20, every = 0.5, cell = "●", size = 10 },
  families = { "small", "medium", "large" },
  init = function(self)
    local o = self.opts
    local board = boards[self.family]
    if board then
      -- A copy, so the family's size does not change the opts other placements share.
      o = setmetatable({ columns = board[1], rows = board[2] }, { __index = self.opts })
    end
    math.randomseed(os.time())
    self.state.board = soup(o.columns, o.rows)
    self.state.seen = {}
    self.state.generation = 0
    self:every(o.every, function(self)
      local s = self.state
      local board = step(s.board, o.columns, o.rows)
      local k = key(board)
      -- A board that repeats (still life, blinkers) or has run long starts again.
      s.generation = s.generation + 1
      if s.seen[k] or s.generation > 400 then
        board, s.seen, s.generation = soup(o.columns, o.rows), {}, 0
        k = key(board)
      end
      s.seen[k] = true
      self:set({ board = board })
    end)
  end,
  render = function(self)
    local o, board = self.opts, self.state.board
    local size = boards[self.family]
    if self.family then
      if not size then
        return nil
      end
      -- Two layers of the same glyph, so they line up: every cell dim, then the live ones lit. An SF Mono cell is
      -- 0.618 em wide: the font is a hair under `pitch`, so a row fits without being cut.
      local font = { size = (pitch - 0.1) / 0.618, design = "monospaced", height = pitch, lines = 1 }
      local grid, lit, alive = {}, {}, 0
      local dim = string.rep("•", size[1])
      for y, row in ipairs(board) do
        local cells = {}
        for x, live in ipairs(row) do
          cells[x] = live and "•" or " "
          alive = alive + (live and 1 or 0)
        end
        grid[y] = ui.text(dim, font)
        lit[y] = ui.text(table.concat(cells), font)
      end
      local dots = ui.zstack {
        ui.vstack { spacing = 0, opacity = 0.16, grid },
        ui.vstack { spacing = 0, color = o.color, glow = 3, lit },
      }
      if self.family == "small" then
        return ui.vstack { fill = "both", dots }
      end
      return ui.vstack {
        spacing = 0, fill = "both",
        dots,
        ui.spacer(),
        ui.hstack {
          ui.text("Generation " .. self.state.generation, ui.font("caption", { weight = "semibold", color = "muted", mono = true })),
          ui.spacer(),
          ui.text(alive .. " alive", ui.font("caption", { weight = "semibold", color = "muted", mono = true })),
        },
      }
    end
    local lines = {}
    for y, row in ipairs(board) do
      local cells = {}
      for x, alive in ipairs(row) do
        cells[x] = alive and o.cell or (o.dead and "·" or " ")
      end
      lines[y] = ui.text(table.concat(cells, " "), { size = o.size, design = "monospaced", color = o.color, lines = 1 })
    end
    return ui.vstack { spacing = 0, lines }
  end,
})
