-- git: your repositories at a glance: branch, uncommitted changes, commits to push or pull, and the last commit.
--   opts.repos   a list of folders, such as { "~/code/app", "~/dotfiles" }; shows nothing without one
--   opts.every   seconds between checks (default 60); opts.size, opts.color, opts.width
--   Families: rectangular, inline, small, medium, large (rows like Apple's Stocks).
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

-- A repository's state in a word, and its color, most urgent first: Stocks' pill. `short` fits a narrow row.
local function state(r, short)
  if r.error then
    return short and "–" or "Not a repo", "muted"
  elseif r.changed > 0 then
    return short and ("±" .. r.changed) or (r.changed .. " changed"), "warning"
  elseif r.behind > 0 then
    return short and ("↓" .. r.behind) or (r.behind .. " behind"), "danger"
  elseif r.ahead > 0 then
    return short and ("↑" .. r.ahead) or (r.ahead .. " ahead"), "accent"
  end
  return "Clean", "success"
end

-- The line under a repository's name: its branch and last commit, or (in privacy mode) its counts.
local function subtitle(r, private, long)
  if r.error then
    return "Not a repository"
  end
  local parts = {}
  if not private then
    parts[1] = r.branch
    if long and r.subject then
      parts[2] = r.subject
    end
  end
  if r.ahead > 0 then
    parts[#parts + 1] = "↑" .. r.ahead
  end
  if r.behind > 0 then
    parts[#parts + 1] = "↓" .. r.behind
  end
  if long and r.when and not private then
    parts[#parts + 1] = r.when
  end
  return #parts > 0 and table.concat(parts, " · ") or "Up to date"
end

-- Apple's layouts for each family. `repos` are the ones read so far, each with its place in opts.repos.
local function family(f, repos, configured, o)
  local private = locky.config.privacy == true
  local narrow = f == "small" or f == "rectangular"
  local function name(r)
    return private and ((narrow and "Repo " or "Repository ") .. r.index) or r.name
  end
  if configured == 0 then
    local title = f == "inline" and "No repositories" or "No Repositories"
    if f == "inline" or f == "rectangular" then
      return ui.hstack { spacing = 4, ui.symbol("arrow.triangle.branch", ui.font("subheadline")), ui.text(title, ui.font("subheadline", { color = "muted" })) }
    end
    return ui.vstack {
      spacing = 4, fill = "both",
      ui.symbol("arrow.triangle.branch", { size = 22, weight = "medium", color = "muted" }),
      ui.text(title, ui.font("subheadline", { weight = "semibold", color = "muted" })),
      ui.text("Set opts.repos", ui.font("caption", { color = "muted", lines = 1 })),
    }
  end
  local changed = 0
  for _, r in ipairs(repos) do
    if not r.error and (r.changed > 0 or r.ahead > 0 or r.behind > 0) then
      changed = changed + 1
    end
  end
  local summary = changed == 0 and "All up to date" or ("%d of %d need attention"):format(changed, #repos)
  if f == "inline" then
    return ui.hstack { spacing = 4, ui.symbol("arrow.triangle.branch", ui.font("subheadline")), ui.text(summary, ui.font("subheadline", { lines = 1 })) }
  elseif f == "rectangular" then
    return ui.vstack {
      spacing = 1, align = "leading", fill = "both",
      ui.hstack { spacing = 5, ui.symbol("arrow.triangle.branch", ui.font("headline")), ui.text("Git", ui.font("headline")) },
      ui.each({ repos[1], repos[2] }, function(r)
        return ui.hstack {
          spacing = 6,
          ui.text(name(r), ui.font("subheadline", { lines = 1 })),
          ui.spacer(),
          ui.text((state(r, true)), ui.font("subheadline", { mono = true, color = "muted", lines = 1 })),
        }
      end),
    }
  end
  local small, large = f == "small", f == "large"
  local list = {}
  for i = 1, math.min(small and 4 or large and 6 or 3, #repos) do
    list[i] = repos[i]
  end
  local function pill(r)
    local word, color = state(r)
    return ui.text(word, ui.font("footnote", {
      weight = "semibold", mono = true, lines = 1, color = "#ffffff",
      width = 84, padding = { 3, 0 }, background = color, radius = 6,
    }))
  end
  local header = ui.hstack {
    spacing = 5,
    ui.symbol("arrow.triangle.branch", { size = 13, weight = "semibold", color = o.color or "accent" }),
    ui.text(small and "Git" or "Repositories", ui.font("subheadline", { weight = "semibold" })),
    ui.spacer(),
    not small and ui.text(summary, ui.font("footnote", { weight = "medium", color = "muted", lines = 1 })),
  }
  if small then
    return ui.vstack {
      spacing = 0, align = "leading", fill = "both",
      header,
      ui.spacer(),
      ui.vstack {
        spacing = 6, align = "leading",
        ui.each(list, function(r)
          local word, color = state(r, true)
          return ui.hstack {
            spacing = 6,
            ui.text(name(r), ui.font("footnote", { weight = "semibold", lines = 1 })),
            ui.spacer(),
            ui.text(word, ui.font("footnote", { weight = "semibold", mono = true, color = color, lines = 1 })),
          }
        end),
      },
    }
  end
  return ui.vstack {
    spacing = 0, align = "leading", fill = "both",
    large and ui.vstack { spacing = 0, padding = { 0, 0, 6, 0 }, header },
    ui.each(list, function(r, i)
      return ui.vstack {
        spacing = 0, fill = "width",
        i > 1 and ui.divider(),
        ui.hstack {
          spacing = 10, padding = { large and 8 or 4, 0 },
          ui.vstack {
            spacing = 1, align = "leading",
            ui.text(name(r), ui.font("subheadline", { weight = "semibold", lines = 1 })),
            ui.text(subtitle(r, private, large), ui.font("footnote", { color = "muted", lines = 1 })),
          },
          ui.spacer(),
          pill(r),
        },
      }
    end),
    ui.spacer(),
  }
end

locky.widget.define("git", {
  description = "Your git repositories: branch, changes, and the last commit",
  families = { "rectangular", "inline", "small", "medium", "large" },
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
    if self.family then
      if self.family == "circular" then
        return nil
      end
      local repos = {}
      for i = 1, #o.repos do
        local r = self.state.repos[i]
        if r then
          r.index = i
          repos[#repos + 1] = r
        end
      end
      if #o.repos > 0 and #repos == 0 then
        return nil
      end
      return family(self.family, repos, #o.repos, o)
    end
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
