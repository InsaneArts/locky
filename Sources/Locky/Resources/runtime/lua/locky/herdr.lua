-- locky.herdr: coding agents from herdr (https://herdr.dev), for any widget.
--
--   local herdr = require("locky.herdr")
--   init = function(self)
--     herdr.watch(self, function(self, data) self:set({ herdr = data }) end)
--   end
--
-- Locky keeps one live connection to herdr's socket while a widget watches, so a change shows at once.
-- data is false when herdr is not running, otherwise:
--   { agents = { { id, status, kind, title, workspace, since }, ... }, counts = { blocked, done, working, idle,
--     unknown }, need = blocked + done, fetched (seconds since 1970) }
-- since is the seconds the agent had its status at `fetched`, or nil when it began before Locky connected.
-- Agents come sorted: blocked, done, working, idle, the oldest change first in each. In privacy mode
-- (locky.config.privacy) a title is the agent's kind ("Claude") and the workspace is "".
local M = {}

M.colors = { blocked = "warning", done = "success", working = "accent", idle = "muted", unknown = "muted" }
M.words = { blocked = "Needs you", done = "Done", working = "Working", idle = "Idle", unknown = "Unknown" }

-- Most characters a title keeps.
local longest = 44

-- "[ * ] Action Required | Add rate limiting | api" reads "Add rate limiting"; a long title ends on a word.
local function clean(title)
  title = title:gsub("^%[ *. *%] *", ""):gsub("^Action Required | ", ""):gsub(" | [^|]*$", "")
  title = title:gsub("^%s+", ""):gsub("%s+$", "")
  if (utf8.len(title) or #title) > longest then
    local cut = title:sub(1, (utf8.offset(title, longest + 1) or #title + 1) - 1)
    title = (cut:match("^(.+)%s") or cut):gsub("[%s%p]+$", "") .. "…"
  end
  return title
end

local function capital(s)
  return (s:gsub("^%l", string.upper))
end

local rank = { blocked = 1, done = 2, working = 3, idle = 4 }

-- The data above from the host's agents: { agents = { { id, status, agent, display_agent, name, title,
-- terminal_title_stripped, workspace, state_change_seq, changed } }, fetched }.
local function shape(raw)
  local private = locky.config.privacy == true
  local agents, counts = {}, { blocked = 0, done = 0, working = 0, idle = 0, unknown = 0 }
  for _, a in ipairs(raw.agents or {}) do
    local status = rank[a.status] and a.status or "unknown"
    counts[status] = counts[status] + 1
    local kind = capital(a.display_agent or a.agent or "agent")
    local title = a.name or a.title or (a.terminal_title_stripped and clean(a.terminal_title_stripped))
    agents[#agents + 1] = {
      id = a.id,
      status = status,
      kind = kind,
      title = (private or not title or title == "") and kind or title,
      workspace = private and "" or capital(a.workspace or ""),
      since = a.changed and math.max(0, raw.fetched - a.changed) or nil,
      seq = a.state_change_seq,
    }
  end
  -- Stable: the same agents keep their places from one change to the next.
  table.sort(agents, function(x, y)
    local rx, ry = rank[x.status] or 5, rank[y.status] or 5
    if rx ~= ry then
      return rx < ry
    end
    if (x.seq or 0) ~= (y.seq or 0) then
      return (x.seq or 0) < (y.seq or 0)
    end
    return tostring(x.id) < tostring(y.id)
  end)
  for _, a in ipairs(agents) do
    a.seq = nil
  end
  return { agents = agents, counts = counts, need = counts.blocked + counts.done, fetched = raw.fetched }
end

--- Turns `herdr api snapshot` output into the data above, or nil when it is not a snapshot.
function M.parse(json)
  local ok, reply = pcall(locky.json.decode, json)
  local snapshot = ok and type(reply) == "table" and reply.result and reply.result.snapshot
  if type(snapshot) ~= "table" then
    return nil
  end
  local labels = {}
  for _, w in ipairs(snapshot.workspaces or {}) do
    labels[w.workspace_id] = w.label
  end
  local raw = { agents = {}, fetched = locky.now() }
  for i, a in ipairs(snapshot.agents or {}) do
    raw.agents[i] = {
      id = a.terminal_id or a.pane_id, status = a.agent_status, agent = a.agent, display_agent = a.display_agent,
      name = a.name, title = a.title, terminal_title_stripped = a.terminal_title_stripped,
      workspace = labels[a.workspace_id], state_change_seq = a.state_change_seq,
    }
  end
  return shape(raw)
end

--- Calls fn(self, data or false) now when herdr's agents are known and again each time they change, owned by the
--- widget `self`. The old form watch(self, seconds, fn) still works; the seconds no longer count.
function M.watch(self, seconds, fn)
  if fn == nil then
    seconds, fn = nil, seconds
  end
  locky.validate("seconds", seconds, "number", true)
  locky.validate("fn", fn, "callable")
  self:_herdr(function(self, raw)
    fn(self, raw and shape(raw) or false)
  end)
end

--- Seconds agent `a` of `data` has had its status now, or nil when that is not known.
function M.elapsed(data, a)
  return a.since and a.since + math.max(0, locky.now() - (data.fetched or locky.now())) or nil
end

--- A short time, as the agents widget shows it: "now", "12m", "3h", "2d".
function M.duration(seconds)
  local minutes = math.floor(seconds / 60)
  if minutes < 1 then
    return "now"
  elseif minutes < 60 then
    return minutes .. "m"
  elseif minutes < 24 * 60 then
    return math.floor(minutes / 60) .. "h"
  end
  return math.floor(minutes / (24 * 60)) .. "d"
end

return M
