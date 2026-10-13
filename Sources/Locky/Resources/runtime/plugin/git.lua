-- git: your repositories at a glance: branch, uncommitted changes, commits to push or pull, and the last commit.
--   opts.repos   a list of folders, such as { "~/code/app", "~/dotfiles" }; shows nothing without one
--   opts.every   seconds between checks (default 60); opts.size, opts.color, opts.width
-- Privacy mode shows the counts only: no repository, branch, or commit message.
local ui = locky.ui

-- git in `path`. A repository's own config could run a program (core.fsmonitor), and a plugin's theme may point
-- this widget at a repository it ships: a bare one is refused, and no fsmonitor runs.
local function git(path, ...)
  return { "git", "-c", "safe.bareRepository=explicit", "-c", "core.fsmonitor=false", "-C", path, ... }
end

-- `git status --porcelain=v2 --branch` → branch, ahead, behind, changed files.
local function status(text)
  local branch = text:match("# branch%.head (%S+)") or "?"
  local ahead, behind = text:match("# branch%.ab %+(%d+) %-(%d+)")
  local changed = 0
  for line in text:gmatch("[^\n]+") do
    if not line:match("^#") then
      changed = changed + 1
    end
  end
  return { branch = branch, ahead = tonumber(ahead) or 0, behind = tonumber(behind) or 0, changed = changed }
end

locky.widget.define("git", {
  description = "Your git repositories: branch, changes, and the last commit",
  opts = { repos = {}, every = 60, size = 12, width = 300 },
  init = function(self)
    self.state.repos = {}
    self:every(self.opts.every, function(self)
      for i, folder in ipairs(self.opts.repos) do
        local path = locky.fs.expand(folder)
        self:system(git(path, "status", "--porcelain=v2", "--branch"), function(self, result)
          if result.code ~= 0 then
            self.state.repos[i] = { name = folder:match("([^/]+)/*$") or folder, error = true }
            self:refresh()
            return
          end
          local repo = status(result.stdout)
          repo.name = path:match("([^/]+)/*$") or folder
          self:system(git(path, "log", "-1", "--format=%s%x09%cr"), function(self, log)
            repo.subject, repo.when = log.stdout:match("^([^\t]*)\t([^\n]*)")
            self.state.repos[i] = repo
            self:refresh()
          end)
        end)
      end
    end)
  end,
  render = function(self)
    local o = self.opts
    local s = o.size
    local private = locky.config.privacy == true
    local rows = {}
    for i = 1, #o.repos do
      local r = self.state.repos[i]
      if r and r.error then
        rows[#rows + 1] = ui.text((private and "" or r.name .. ": ") .. "not a repository", { size = s, color = "muted" })
      elseif r then
        local marks = {}
        if r.changed > 0 then marks[#marks + 1] = ui.text("●" .. r.changed, { size = s, color = "warning", mono = true }) end
        if r.ahead > 0 then marks[#marks + 1] = ui.text("↑" .. r.ahead, { size = s, color = "accent", mono = true }) end
        if r.behind > 0 then marks[#marks + 1] = ui.text("↓" .. r.behind, { size = s, color = "danger", mono = true }) end
        if #marks == 0 then marks[1] = ui.text("✓", { size = s, color = "success" }) end
        rows[#rows + 1] = private and ui.hstack { spacing = 6, marks } or ui.vstack {
          spacing = 2, align = "leading",
          ui.hstack {
            spacing = 8, width = o.width,
            ui.text(r.name, { size = s, weight = "semibold", color = o.color, lines = 1 }),
            ui.text(r.branch, { size = s, color = "muted", mono = true, lines = 1 }),
            ui.spacer(),
            ui.hstack { spacing = 6, marks },
          },
          r.subject and ui.text(
            r.subject .. " · " .. (r.when or ""),
            { size = s * 0.85, color = "muted", lines = 1, max_width = o.width }
          ),
        }
      end
    end
    if #rows == 0 then
      return nil
    end
    return ui.vstack { spacing = s * 0.8, align = "leading", rows }
  end,
})
