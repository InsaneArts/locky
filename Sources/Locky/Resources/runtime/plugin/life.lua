-- life: Conway's Game of Life, quietly evolving: a toy for a screen nobody is using. It starts from a random soup and
-- starts again when it settles. Drawn as rows of text, so a large board stays cheap.
--   opts.columns, opts.rows   the board (default 40 by 20); opts.every seconds per generation (default 0.5)
--   opts.cell    the character for a live cell (default "●"); opts.dead true marks dead cells with "·"
--   opts.size (default 10), opts.color
local ui = locky.ui

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
  init = function(self)
    local o = self.opts
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
