#!/usr/bin/env python3
"""Shoots the Rex clip's take in the Atlas helper: the locky-rex pack's lock screen, live, over made-up Rex sessions.

It copies the pack (PACK, default ~/Development/locky-rex) into the helper, and makes twelve Rex sessions there with
the helper's own Rex server. Nine of them hold a program that reports a status with the Program Status Protocol
(OSC 7501), as a coding agent does in Rex: real reports, with made-up words. Three of those programs report again
while the camera runs: one's progress grows until it is done, one starts to need the user, one finishes. The sessions
are made over three minutes, so the reports have different ages. The lock screen looks at Rex every second (the
widgets' `every`), and its wallpaper's clock runs three times as fast, so the lights' motion shows in a short clip.
Afterwards the script removes its sessions, and stops Rex's server if the server was off before.

  python3 tools/rex_shoot.py && python3 tools/prepare.py rexclip
"""
import base64, json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shoot

PACK = os.path.expanduser(os.environ.get("PACK", "~/Development/locky-rex"))
REX = '"$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"'
SPEED = 3
GO = f"{shoot.WORK}/go"


def report(app, state, line=None, kind=None, progress=None):
    """One report's pairs, as the protocol writes them."""
    out = [f"state={state}", f"app={app}"]
    if kind: out.append(f"kind={kind}")
    if progress is not None: out.append(f"progress={progress}")
    if line: out.append("msg=" + base64.b64encode(line.encode()).decode())
    return ":".join(out)


# Each group is made together, then the script waits: (seconds to wait after, [(session, panes, first report, later
# reports as (seconds after the one before, report))]). The lock screen lists sessions newest first.
terraform = lambda p: report("terraform", "working", "Applying 12 changes", progress=p)
GROUPS = [
    (75, [("scratch", 1, None, []), ("cli", 3, report("cargo", "working", "Compiling locky v0.1.0", progress=38), []), ("design", 1, None, []),
          ("mobile", 2, report("codex", "done", "Opened a pull request"), []), ("db", 1, report("claude-code", "working", "Writing the migration"), []),
          ("infra", 4, None, []), ("release", 2, report("claude-code", "done", "Tagged v0.1.0"), []), ("docs", 1, report("claude-code", "idle"), [])]),
    (65, [("web", 2, report("claude-code", "done", "Fixed the flaky login test"), [])]),
    (50, [("deploy", 1, terraform(22), [(1.5, terraform(p)) for p in (34, 46, 58, 70, 82, 94)] + [(1.5, report("terraform", "done", "Applied 12 changes"))]),
          ("agents", 3, report("claude-code", "working", "Refactoring the theme loader"), [(9.0, report("claude-code", "done", "Refactored the theme loader"))])]),
    (4, [("api", 2, report("codex", "working", "Planning the migration"), [(5.5, report("codex", "blocked", "Run the database migration?", kind="permission"))])]),
]

shoot.sh(f"mkdir -p '{shoot.WORK}/pack/themes' '{shoot.WORK}/pack/shaders' '{shoot.WORK}/pack/plugin' '{shoot.WORK}/config' '{shoot.WORK}/rec'")
for rel in ("themes/rex.lua", "shaders/rex.metal", "plugin/rex.lua"):
    text = open(os.path.join(PACK, rel)).read()
    shoot.sh(f"cat > '{shoot.WORK}/pack/{rel}' <<'LOCKYEOF'\n{text}\nLOCKYEOF")
shoot.sh(f"""cat > '{shoot.WORK}/config/init.lua' <<'LOCKYEOF'
locky.pack.add({{ {{ dir = "{shoot.WORK}/pack" }} }})
locky.theme.extend("rex", function(theme) theme.background.speed = {SPEED} end)
-- The clip shows reports as they arrive: the widgets look at Rex every second, not every five.
locky.theme.extend("rex", function(theme)
  for _, placement in ipairs(theme.widgets) do
    if placement[1]:match("^rex%.") then placement.opts = {{ every = 1 }} end
  end
end)
LOCKYEOF""")
# A pane's program: it reports once, as the protocol has it; when the go file appears, it makes its later reports,
# each so many seconds after the one before; then it stays, so a working or blocked record stays too.
shoot.sh(f"""cat > '{shoot.WORK}/report.sh' <<'LOCKYEOF'
#!/bin/sh
go=$1
[ -n "$2" ] && printf '\\033]7501;%s\\033\\\\' "$2"
shift 2
if [ $# -ge 2 ]; then
  while [ ! -f "$go" ]; do sleep 0.1; done
  while [ $# -ge 2 ]; do sleep "$1"; printf '\\033]7501;%s\\033\\\\' "$2"; shift 2; done
fi
exec sleep 3600
LOCKYEOF
rm -f '{GO}'""")

was_running = "running" in shoot.sh(f"{REX} --autostart=false ls >/dev/null 2>&1 && echo running || echo off")
made = []
try:
    for wait, sessions in GROUPS:
        for label, panes, first, later in sessions:
            made.append(label)
            steps = " ".join(f"{delay} '{pairs}'" for delay, pairs in later)
            shoot.sh(f"{REX} new {label} --shell none -- /bin/sh '{shoot.WORK}/report.sh' '{GO}' '{first or ''}' {steps}", timeout=40)
            if panes > 1:
                block = json.loads(shoot.sh(f"{REX} --autostart=false block ls -s {label} --json", timeout=40))["blocks"][0]["block_id"]
                for _ in range(panes - 1):
                    shoot.sh(f"{REX} split -b '{block}' --shell none --focus=false -- /bin/sh '{shoot.WORK}/report.sh' '{GO}' ''", timeout=40)
        time.sleep(wait)
    shoot.settings(privacy=False, theme="rex")
    shoot.close()
    b = shoot.launch("preview", "--theme", "rex", "--size", f"{shoot.SIZE[0]}x{shoot.SIZE[1]}", "--behind")
    time.sleep(4.0)
    shoot.record("rex-clip", (b["x"], b["y"] + b["height"] - shoot.SIZE[1], shoot.SIZE[0], shoot.SIZE[1]))
    went = time.time()
    shoot.sh(f"touch '{GO}'")
    time.sleep(17)
    shoot.stop("rex-clip")
    take = shoot.fetch("rex-clip")
    json.dump({"go": went}, open(os.path.join(shoot.FOOTAGE, "rex-clip.json"), "w"))
finally:
    shoot.close()
    print(shoot.sh(f"{REX} --autostart=false kill {' '.join(made)} 2>&1 | tail -1", timeout=60))
    if not was_running:
        print(shoot.sh(f"{REX} --autostart=false server stop 2>&1 | tail -1", timeout=40))

path = os.path.join(shoot.FILM, "src", "clips.json")
clips = json.load(open(path))
clips["rexclip"] = {"file": "rex-clip.mkv", "in": 1.0, "out": 15.4}
json.dump(clips, open(path, "w"), indent=1)
print(take)
