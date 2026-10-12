-- locky.herdr: coding agents from herdr (https://herdr.dev), for any widget.
--
--   local herdr = require("locky.herdr")
--   init = function(self)
--     herdr.watch(self, 3, function(self, data) self:set({ herdr = data }) end)
--   end
--
-- data is false when herdr is not running, otherwise:
--   { agents = { { status, kind, title, workspace }, ... }, counts = { blocked, done, working, idle, unknown },
--     need = blocked + done }
-- Agents come sorted: blocked, done, working, idle. In privacy mode (locky.config.privacy) a title is the
-- agent's kind ("Claude") and the workspace is "".
local M = {}

M.colors = { blocked = "warning", done = "success", working = "accent", idle = "muted", unknown = "muted" }
M.words = { blocked = "Needs you", done = "Done", working = "Working", idle = "Idle", unknown = "Unknown" }

local function clean(title)
  title = title:gsub("^%[ *. *%] *", ""):gsub("^Action Required | ", ""):gsub(" | [^|]*$", "")
  return title
end

local function capital(s)
  return (s:gsub("^%l", string.upper))
end

local rank = { blocked = 1, done = 2, working = 3, idle = 4 }

--- Turns `herdr api snapshot` output into the data above, or nil when it is not a snapshot.
function M.parse(json)
  local ok, reply = pcall(locky.json.decode, json)
  local snapshot = ok and type(reply) == "table" and reply.result and reply.result.snapshot
  if type(snapshot) ~= "table" then
    return nil
  end
  local workspaces = {}
  for _, w in ipairs(snapshot.workspaces or {}) do
    workspaces[w.workspace_id] = w.label
  end
  local agents, counts = {}, { blocked = 0, done = 0, working = 0, idle = 0, unknown = 0 }
  for _, a in ipairs(snapshot.agents or {}) do
    local status = rank[a.agent_status] and a.agent_status or "unknown"
    counts[status] = counts[status] + 1
    local kind = capital(a.display_agent or a.agent or "agent")
    local private = locky.config.privacy
    agents[#agents + 1] = {
      status = status,
      kind = kind,
      title = private and kind or a.name or a.title or (a.terminal_title_stripped and clean(a.terminal_title_stripped)) or capital(a.agent or "agent"),
      workspace = private and "" or capital(workspaces[a.workspace_id] or ""),
    }
  end
  table.sort(agents, function(x, y)
    return (rank[x.status] or 5) < (rank[y.status] or 5)
  end)
  return { agents = agents, counts = counts, need = counts.blocked + counts.done }
end

--- Asks herdr now and every `seconds`, owned by the widget `self`; calls fn(self, data or false).
function M.watch(self, seconds, fn)
  locky.validate("seconds", seconds, "number")
  locky.validate("fn", fn, "callable")
  self:every(seconds, function(self)
    self:system({ "herdr", "api", "snapshot" }, { timeout = math.max(2, math.min(seconds, 5)) }, function(self, result)
      fn(self, result.code == 0 and M.parse(result.stdout) or false)
    end)
  end)
end

return M
