-- locky.ui: builders for the views widgets return. Locky draws them natively with SwiftUI.
--
--   local ui = locky.ui
--   return ui.vstack {
--     spacing = 4, align = "leading",
--     ui.text("Battery", { weight = "semibold" }),
--     ui.progress(0.82, { color = "success" }),
--     low and ui.text("Plug in soon", { color = "warning" }),  -- false and nil children are skipped
--   }
--
-- Containers take one table: list items are the children, named fields are properties. A child may also
-- be a list of views, which is spliced in, so ui.each() results can be passed as they are.
-- See docs/views.md for every property.
local validate = locky.validate

local ui = {}

local kinds = {
  "vstack", "hstack", "zstack", "grid", "text", "time", "symbol", "image",
  "progress", "ring", "chart", "shape", "dot", "spacer", "divider",
}
local is_kind = {}
for _, kind in ipairs(kinds) do
  is_kind[kind] = true
end

local function is_view(value)
  if type(value) ~= "table" then
    return false
  end
  for kind in pairs(is_kind) do
    if value[kind] ~= nil then
      return true
    end
  end
  return false
end
ui.is_view = is_view

local function add_children(list, value, depth)
  if value == nil or value == false then
    return
  end
  if is_view(value) then
    list[#list + 1] = value
  elseif type(value) == "table" and depth < 4 then
    local last = 0
    for k in pairs(value) do
      if type(k) == "number" and k > last then
        last = k
      end
    end
    for i = 1, last do
      add_children(list, value[i], depth + 1)
    end
  else
    error(("a child must be a view built with locky.ui, got %s"):format(type(value)), 4)
  end
end

local function container(kind)
  return function(t)
    validate(kind, t, "table")
    local node, children, last = {}, {}, 0
    for k, v in pairs(t) do
      if type(k) == "number" then
        if k > last then
          last = k
        end
      else
        node[k] = v
      end
    end
    for i = 1, last do
      add_children(children, t[i], 0)
    end
    node[kind] = children
    return node
  end
end

ui.vstack = container("vstack")
ui.hstack = container("hstack")
ui.zstack = container("zstack")
--- A grid: children fill rows of `columns` cells, left to right.
ui.grid = container("grid")

local function leaf(kind, key_type)
  return function(value, props)
    validate(kind, value, key_type)
    validate(kind .. " properties", props, "table", true)
    local node = {}
    for k, v in pairs(props or {}) do
      node[k] = v
    end
    node[kind] = value
    return node
  end
end

--- Text. Numbers are shown as they are.
function ui.text(value, props)
  if type(value) == "number" then
    value = tostring(value)
  end
  return leaf("text", "string")(value, props)
end

--- Live time or date text that updates itself every second, without running Lua.
--- format: "time" (the system's short time without AM/PM), "date" (weekday, month, day), a date pattern
--- used as it is ("HH:mm", "HH", "mm", "EEEE", "d MMMM"), or "skeleton:EEEEdMMMM" (the user's order).
ui.time = leaf("time", "string")

--- An SF Symbol, such as "battery.75percent".
ui.symbol = leaf("symbol", "string")

--- An image file: an absolute path, "~/...", or a path inside the calling plugin's package.
function ui.image(path, props)
  validate("image", path, "string")
  if path:sub(1, 1) ~= "/" and path:sub(1, 1) ~= "~" then
    local dir = locky.fs.package_dir(2)
    if dir then
      path = dir .. "/" .. path
    end
  end
  return leaf("image", "string")(locky.fs.expand(path), props)
end

--- A bar filled to `value` (0 to 1).
ui.progress = leaf("progress", "number")
--- A ring filled to `value` (0 to 1).
ui.ring = leaf("ring", "number")
--- A chart of numbers, newest last. props.style: "line" (default), "area", or "bar".
ui.chart = leaf("chart", "table")

local function shape(kind)
  return function(props)
    validate(kind, props, "table", true)
    local node = {}
    for k, v in pairs(props or {}) do
      node[k] = v
    end
    node.shape = kind
    return node
  end
end

--- Shapes: props color (fill), stroke, stroke_width, radius (rect corners), width, height, rotation.
ui.rect = shape("rect")
ui.circle = shape("circle")
ui.capsule = shape("capsule")
--- A horizontal line `width` long; rotate it for clock hands.
ui.line = shape("line")
--- A closed shape through props.points, each { x, y } as fractions of its width and height (0 to 1).
ui.polygon = shape("polygon")

--- A small filled circle, default 8 points.
function ui.dot(props)
  local node = shape("circle")(props)
  node.shape = nil
  node.dot = true
  return node
end

function ui.spacer(props)
  local node = props or {}
  node.spacer = true
  return node
end

function ui.divider(props)
  local node = props or {}
  node.divider = true
  return node
end

--- Maps a list to views: ui.each(items, function(item, index) return ui.text(item) end).
function ui.each(list, fn)
  validate("list", list, "table")
  validate("fn", fn, "callable")
  local views = {}
  for i, item in ipairs(list) do
    local view = fn(item, i)
    if view then
      views[#views + 1] = view
    end
  end
  return views
end

return ui
