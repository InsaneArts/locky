-- wordclock.words: the classic English 11 x 10 letter grid, and which of its words spell a time.
--
--   local words = require("wordclock.words")
--   local lit, dots = words.at(14, 37)   -- "IT IS TWENTY FIVE TO THREE", 2 corner dots
--   lit["3:7"] == true                   -- row 3, column 7 is lit
--
-- Like the original, the grid shows the last five-minute step that has passed, and the corner dots
-- count the minutes after it (1 to 4). From :35 the phrase counts down TO the next hour.
-- Plain Lua: no Locky API, so it can be tested on its own.
local M = {}

M.grid = {
  "ITLISASAMPM",
  "ACQUARTERDC",
  "TWENTYFIVEX",
  "HALFSTENFTO",
  "PASTERUNINE",
  "ONESIXTHREE",
  "FOURFIVETWO",
  "EIGHTELEVEN",
  "SEVENTWELVE",
  "TENSEOCLOCK",
}

-- Each word: { row, first column, last column }, counted from 1.
M.words = {
  it = { 1, 1, 2 }, is = { 1, 4, 5 },
  a = { 2, 1, 1 }, quarter = { 2, 3, 9 },
  twenty = { 3, 1, 6 }, five_minutes = { 3, 7, 10 },
  half = { 4, 1, 4 }, ten_minutes = { 4, 6, 8 }, to = { 4, 10, 11 },
  past = { 5, 1, 4 },
  one = { 6, 1, 3 }, two = { 7, 9, 11 }, three = { 6, 7, 11 }, four = { 7, 1, 4 }, five = { 7, 5, 8 },
  six = { 6, 4, 6 }, seven = { 9, 1, 5 }, eight = { 8, 1, 5 }, nine = { 5, 8, 11 }, ten = { 10, 1, 3 },
  eleven = { 8, 6, 11 }, twelve = { 9, 6, 11 },
  oclock = { 10, 6, 11 },
}

local HOURS = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve" }

-- The phrase for each five-minute step after the hour (0 to 11).
local STEPS = {
  [0] = {},
  { "five_minutes", "past" },
  { "ten_minutes", "past" },
  { "a", "quarter", "past" },
  { "twenty", "past" },
  { "twenty", "five_minutes", "past" },
  { "half", "past" },
  { "twenty", "five_minutes", "to" },
  { "twenty", "to" },
  { "a", "quarter", "to" },
  { "ten_minutes", "to" },
  { "five_minutes", "to" },
}

--- The words for a time, in reading order, and the number of corner dots (0 to 4).
--- hour: 0 to 23, minute: 0 to 59.
function M.phrase(hour, minute)
  local step, dots = minute // 5, minute % 5
  local list = { "it", "is" }
  for _, word in ipairs(STEPS[step]) do
    list[#list + 1] = word
  end
  local h = (hour + (step >= 7 and 1 or 0)) % 12
  list[#list + 1] = HOURS[h == 0 and 12 or h]
  if step == 0 then
    list[#list + 1] = "oclock"
  end
  return list, dots
end

--- The lit cells for a time, as a set of "row:column" keys, and the number of corner dots.
function M.at(hour, minute)
  local list, dots = M.phrase(hour, minute)
  local lit = {}
  for _, word in ipairs(list) do
    local w = M.words[word]
    for column = w[2], w[3] do
      lit[w[1] .. ":" .. column] = true
    end
  end
  return lit, dots
end

--- The phrase as text, such as "IT IS TWENTY FIVE TO THREE", read from the grid.
function M.text(hour, minute)
  local list = M.phrase(hour, minute)
  local parts = {}
  for _, word in ipairs(list) do
    local w = M.words[word]
    parts[#parts + 1] = M.grid[w[1]]:sub(w[2], w[3])
  end
  return table.concat(parts, " ")
end

return M
