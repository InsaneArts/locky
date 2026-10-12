-- Phosphor's widgets: a shell session on an amber CRT, after cool-retro-term.
--   phosphor.session   the transcript: "Last login", a block clock, a neofetch-style info block, and herdr's
--                      agents. Its last line sits on the bottom edge of its box, right above the password
--                      prompt, so give the placement a `size` that ends where the prompt begins; when there is
--                      less to show, the session starts lower, as if the terminal had scrolled.
--     opts.size       text size (default 14, the size of the password prompt)
--     opts.clock_size the block clock's character size (default 28)
--     opts.glow       glow radius of the text (default 3); the clock glows 2.5 times as much
--     opts.clock, opts.fetch, opts.herdr   false leaves that command out; opts.logo false drops neofetch's logo
--     opts.rows       most agents listed (default 5); idle ones are only counted
--     opts.every      seconds between herdr checks (default 5)
--     opts.low        battery percent at or below which the battery line turns `danger` (default 20)
--   phosphor.notice    "Sorry, try again." under the prompt for a few seconds after a wrong password.
local ui = locky.ui
local herdr = require("locky.herdr")

-- The clock's digits: 7 columns by 5 rows of full blocks, two-column strokes, after figlet's "ANSI Regular".
local glyphs = {
  ["0"] = { " █████ ", "██   ██", "██   ██", "██   ██", " █████ " },
  ["1"] = { "   ██  ", " ████  ", "   ██  ", "   ██  ", " ██████" },
  ["2"] = { "██████ ", "     ██", " █████ ", "██     ", "███████" },
  ["3"] = { "██████ ", "     ██", " █████ ", "     ██", "██████ " },
  ["4"] = { "██   ██", "██   ██", "███████", "     ██", "     ██" },
  ["5"] = { "███████", "██     ", "██████ ", "     ██", "██████ " },
  ["6"] = { " █████ ", "██     ", "██████ ", "██   ██", " █████ " },
  ["7"] = { "███████", "     ██", "    ██ ", "   ██  ", "   ██  " },
  ["8"] = { " █████ ", "██   ██", " █████ ", "██   ██", " █████ " },
  ["9"] = { " █████ ", "██   ██", " ██████", "     ██", " █████ " },
  [":"] = { "  ", "██", "  ", "██", "  " },
}

--- The five lines of block characters that spell `text` ("12:34").
local function banner(text)
  local rows = { {}, {}, {}, {}, {} }
  for i = 1, #text do
    local glyph = glyphs[text:sub(i, i)]
    if glyph then
      for r = 1, 5 do
        local row = rows[r]
        if #row > 0 then
          row[#row + 1] = "  "
        end
        row[#row + 1] = glyph[r]
      end
    end
  end
  for r = 1, 5 do
    rows[r] = table.concat(rows[r])
  end
  return rows
end

--- `s` cut or padded with spaces to exactly `n` characters, so columns line up on the character grid.
local function fit(s, n)
  local len = utf8.len(s) or #s
  if len > n then
    s = s:sub(1, (utf8.offset(s, n) or n) - 1):gsub("%s+$", "") .. "…"
    len = utf8.len(s) or #s
  end
  return s .. string.rep(" ", n - len)
end

-- neofetch's logo, as a padlock instead of a vendor's mark.
local logo = {
  "        .:cc:.        ",
  "      .dKXXXXKb.      ",
  "     dXK'    'KXb     ",
  "     KXl      lXK     ",
  "     KX:      :XK     ",
  "     KX:      :XK     ",
  " .ooooKXooooooXKoooo. ",
  " NMMMMMMMMMMMMMMMMMMN ",
  " NMMMMMMMW''WMMMMMMMN ",
  " NMMMMMMMM  MMMMMMMMN ",
  " NMMMMMMMMMMMMMMMMMMN ",
  " 'kNMMMMMMMMMMMMMMNk' ",
}

local function plural(n, word)
  return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

--- neofetch's uptime: "3 days, 15 hours, 22 mins".
local function uptime(seconds)
  local d, h, m = seconds // 86400, seconds % 86400 // 3600, seconds % 3600 // 60
  local parts = {}
  if d > 0 then parts[#parts + 1] = plural(d, "day") end
  if h > 0 then parts[#parts + 1] = plural(h, "hour") end
  if m > 0 or #parts == 0 then parts[#parts + 1] = plural(m, "min") end
  return table.concat(parts, ", ")
end

local function battery(b)
  if not b or not b.present then
    return nil
  end
  local state
  if b.state == "charged" then
    state = "Charged"
  elseif b.charging then
    state = b.until_full and ("Charging, %d:%02d to full"):format(b.until_full // 60, b.until_full % 60) or "Charging"
  elseif b.plugged then
    state = "Plugged in"
  else
    state = b.remaining and ("Discharging, %d:%02d left"):format(b.remaining // 60, b.remaining % 60) or "Discharging"
  end
  return ("%d%% [%s]"):format(b.percent or 0, state)
end

local status_words = { blocked = "needs you", done = "done", working = "working", idle = "idle", unknown = "unknown" }

locky.widget.define("phosphor.session", {
  description = "A shell session: last login, a block clock, neofetch, and herdr agents",
  opts = { size = 14, clock_size = 28, glow = 3, clock = true, fetch = true, logo = true, herdr = true, rows = 5, every = 5, low = 20 },
  init = function(self)
    local o = self.opts
    local user, host = locky.sys.user().name, locky.sys.hostname().host:gsub("%.local$", "")
    local hour24 = locky.date.locale().hour24
    self.state.user, self.state.host = user, host
    self.state.login = locky.date.format(hour24 and "EEE MMM d HH:mm" or "EEE MMM d h:mm a")

    if o.clock then
      self:every(60, function(self)
        local time = locky.date.format(hour24 and "HH:mm" or "h:mm")
        local date = locky.date.format("skeleton:EEEEdMMMMyyyy")
        if time ~= self.state.time or date ~= self.state.date then
          self:set({ time = time, date = date, ampm = not hour24 and locky.date.format("a") or nil })
        end
      end, { align = true })
    end

    if o.fetch then
      local os_, machine = locky.sys.os(), locky.sys.machine()
      local name = locky.str.trim(("%s %s %s"):format(os_.name, os_.codename or "", os_.version):gsub("%s+", " "))
      self.state.fixed = {
        os = os_.build ~= "" and ("%s (%s)"):format(name, os_.build) or name,
        host = machine.model ~= "" and machine.model or nil,
        chip = machine.chip ~= "" and ("%s (%d)"):format(machine.chip, machine.cores) or nil,
      }
      locky.sys.cpu() -- primes the meter: the first reading has nothing to compare with
      local function read(self)
        local memory, keyboard, b = locky.sys.memory(), locky.sys.keyboard(), locky.sys.battery()
        local info = {
          uptime = uptime(locky.sys.uptime()),
          battery = battery(b),
          low = b.present and not b.charging and (b.percent or 100) <= o.low,
          cpu = ("%d%%"):format(math.floor(locky.sys.cpu().usage + 0.5)),
          memory = memory.used and ("%dMiB / %dMiB (%d%%)"):format(memory.used // 1048576, memory.total // 1048576, math.floor(memory.percent + 0.5)) or nil,
          keyboard = keyboard.name,
        }
        local key = locky.json.encode(info)
        if key ~= self.state.info_key then
          self:set({ info = info, info_key = key })
        end
      end
      self:after(1, read)
      self:every(10, read, { now = false })
    end

    if o.herdr then
      herdr.watch(self, o.every, function(self, data)
        -- Only what the table shows: a change elsewhere in herdr's snapshot draws nothing.
        local key = "off"
        if data then
          local parts = { data.counts.idle }
          for _, a in ipairs(data.agents) do
            if a.status ~= "idle" then
              parts[#parts + 1] = a.status .. "\0" .. a.title .. "\0" .. a.workspace
            end
          end
          key = table.concat(parts, "\1")
        end
        if key ~= self.state.herdr_key then
          self:set({ herdr = data, herdr_key = key })
        end
      end)
    end
  end,

  render = function(self)
    local o, s = self.opts, self.state
    -- Wait for herdr (milliseconds) and the first CPU reading (a second), so the session appears whole.
    if (o.herdr and s.herdr == nil) or (o.fetch and not s.info) then
      return nil
    end
    local size, glow = o.size, o.glow

    local function text(value, color, extra)
      -- Leading, so trailing spaces hang off the end instead of shifting the line: columns stay on the grid.
      local props = { size = size, color = color or "fg", glow = glow, text_align = "leading", lines = 1 }
      if extra then
        for k, v in pairs(extra) do props[k] = v end
      end
      return ui.text(value, props)
    end
    local function prompt(command)
      return ui.hstack {
        spacing = 0,
        text(s.user .. "@" .. s.host .. " ~ % ", "accent"),
        text(command, "fg"),
      }
    end
    local blank = text(" ")

    local lines = { text("Last login: " .. s.login .. " on console", "muted") }

    if o.clock and s.time then
      local rows = banner(s.time)
      local clock = {}
      for r = 1, 5 do
        clock[r] = ui.text(rows[r], { size = o.clock_size, color = "fg", glow = glow * 2.5, text_align = "leading" })
      end
      lines[#lines + 1] = prompt("clock")
      lines[#lines + 1] = ui.hstack {
        align = "bottom", spacing = o.clock_size * 0.6, padding = { size * 0.5, 0, size * 0.6, 0 },
        -- Lines of █ touch only without the font's line gap: the block is 1 em tall, the line 1.18 em.
        ui.vstack { align = "leading", spacing = -o.clock_size * 0.18, clock },
        s.ampm and text(s.ampm, "bright", { padding = { 0, 0, o.clock_size * 0.2, 0 } }),
      }
      lines[#lines + 1] = text(s.date, "muted")
    end

    if o.fetch and s.info then
      local i, f = s.info, s.fixed
      local header = s.user .. "@" .. s.host
      local function field(label, value, color)
        if not value then return nil end
        return ui.hstack { spacing = 0, text(label .. ": ", "bright", { weight = "bold" }), text(value, color) }
      end
      local shades = {}
      for k = 1, 8 do
        shades[k] = ui.text("███", { size = size, color = "fg", opacity = k / 8 })
      end
      local art = {}
      for r, row in ipairs(logo) do
        art[r] = text(row, "fg")
      end
      lines[#lines + 1] = blank
      lines[#lines + 1] = prompt("neofetch")
      lines[#lines + 1] = ui.hstack {
        align = "top", spacing = size * 1.8,
        o.logo and ui.vstack { align = "leading", spacing = 0, art },
        ui.vstack {
          align = "leading", spacing = 0,
          ui.hstack {
            spacing = 0,
            text(s.user, "bright", { weight = "bold" }), text("@", "fg"), text(s.host, "bright", { weight = "bold" }),
          },
          text(string.rep("-", utf8.len(header) or #header), "muted"),
          field("OS", f.os),
          field("Host", f.host),
          field("Chip", f.chip),
          field("Uptime", i.uptime),
          field("Battery", i.battery, i.low and "danger" or nil),
          field("CPU Usage", i.cpu),
          field("Memory", i.memory),
          field("Keyboard", i.keyboard),
          blank,
          ui.hstack { spacing = 0, glow = glow, shades },
        },
      }
    end

    if o.herdr then
      local data = s.herdr
      lines[#lines + 1] = blank
      lines[#lines + 1] = prompt("herdr status")
      if not data then
        lines[#lines + 1] = text("herdr: offline", "muted")
      else
        local shown, more = {}, 0
        for _, a in ipairs(data.agents) do
          if a.status ~= "idle" then
            if #shown < o.rows then shown[#shown + 1] = a else more = more + 1 end
          end
        end
        if #shown > 0 then
          lines[#lines + 1] = text(fit("STATUS", 11) .. fit("TITLE", 42) .. "WORKSPACE", "bright", { weight = "bold" })
          for _, a in ipairs(shown) do
            local word = fit(status_words[a.status] or a.status, 9)
            lines[#lines + 1] = ui.hstack {
              spacing = 0,
              a.status == "blocked" and text(word, "bg", { background = "fg", glow = false })
                or text(word, a.status == "done" and "bright" or "fg"),
              text("  " .. fit(a.title, 40) .. "  " .. fit(a.workspace, 16), a.status == "working" and "fg" or "bright"),
            }
          end
        end
        local footer = {}
        if more > 0 then footer[#footer + 1] = ("%d more"):format(more) end
        if data.counts.idle > 0 then footer[#footer + 1] = ("%d idle"):format(data.counts.idle) end
        if #data.agents == 0 then footer[#footer + 1] = "no agents" end
        if #footer > 0 then
          lines[#lines + 1] = text((#shown > 0 and "+ " or "") .. table.concat(footer, ", "), "muted")
        end
      end
    end

    return ui.vstack { align = "bottom-leading", fill = true, spacing = 0, lines }
  end,
})

locky.widget.define("phosphor.notice", {
  description = "\"Sorry, try again.\" after a wrong password, under the prompt",
  opts = { size = 14, seconds = 6, text = "Sorry, try again." },
  init = function(self)
    self:on("auth_failed", function(self)
      local n = (self.state.n or 0) + 1
      self:set({ n = n, shown = true })
      self:after(self.opts.seconds, function(self)
        if self.state.n == n then
          self:set({ shown = false })
        end
      end)
    end)
  end,
  render = function(self)
    if not self.state.shown then
      return nil
    end
    return ui.text(self.opts.text, { size = self.opts.size, color = "danger", glow = 3, text_align = "leading" })
  end,
})
