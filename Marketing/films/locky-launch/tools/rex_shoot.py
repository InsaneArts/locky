#!/usr/bin/env python3
"""Shoots the Rex clip's take in the Atlas helper: the locky-rex pack's lock screen, live, with demo sessions.

It copies the pack (PACK, default ~/Development/locky-rex) into the helper, makes four Rex sessions there with the
helper's own Rex server (api, web, deploy, agents), and records the lock screen with the wallpaper's clock four times
as fast, so its 36 s loop takes 9 s. Then it finds the loop's start in the frames (the split across opens one second
into the loop) and writes the clip's in and out points to src/clips.json.

  python3 tools/rex_shoot.py && python3 tools/prepare.py rexclip

Afterwards, in the helper: `rex kill api web deploy agents`, and `rex server stop` if the server was off before.
"""
import json, os, subprocess, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shoot

PACK = os.path.expanduser(os.environ.get("PACK", "~/Development/locky-rex"))
REX = '"$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"'
SPEED, LOOP = 4, 36 / 4

shoot.sh(f"mkdir -p '{shoot.WORK}/pack/themes' '{shoot.WORK}/pack/shaders' '{shoot.WORK}/pack/plugin' '{shoot.WORK}/config' '{shoot.WORK}/rec'")
for rel in ("themes/rex.lua", "shaders/rex.metal", "plugin/rex.lua"):
    text = open(os.path.join(PACK, rel)).read()
    shoot.sh(f"cat > '{shoot.WORK}/pack/{rel}' <<'LOCKYEOF'\n{text}\nLOCKYEOF")
shoot.sh(f"""cat > '{shoot.WORK}/config/init.lua' <<'LOCKYEOF'
locky.pack.add({{ {{ dir = "{shoot.WORK}/pack" }} }})
locky.theme.extend("rex", function(theme) theme.background.speed = {SPEED} end)
LOCKYEOF""")
# The sessions' names show in the take, so privacy mode is off: every name here is made up.
have = shoot.sh(f"{REX} ls 2>/dev/null", timeout=40)
for name in ("api", "web", "deploy", "agents"):
    if not any(line.split()[:1] == [name] for line in have.splitlines()):
        shoot.sh(f"{REX} new {name} >/dev/null 2>&1", timeout=40)
shoot.settings(privacy=False, theme="rex")
take = shoot.lock_clip("rex", seconds=24, settle=1.0, name="rex-clip")
shoot.close()

# A column of pixels in the right part of the panel: dark pixels there are the split across.
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", take, "-vf", "setpts=PTS-STARTPTS,fps=60,crop=4:1700:3290:140", "-f", "rawvideo",
                      "-pix_fmt", "gray", "-"], capture_output=True).stdout
column = np.frombuffer(raw, np.uint8).reshape(-1, 1700, 4).astype(np.float32).mean(axis=2)
split = (column < 50).sum(axis=1) >= 6
opens = [i / 60 for i in range(1, len(split)) if split[i] and not split[i - 1]]
start = next(t - 4 / SPEED for t in opens if t - 4 / SPEED > 0.2)
path = os.path.join(shoot.FILM, "src", "clips.json")
clips = json.load(open(path))
clips["rexclip"] = {"file": "rex-clip.mkv", "in": round(start - 1 / 60, 3), "out": round(start + LOOP + 1.2, 3)}
json.dump(clips, open(path, "w"), indent=1)
print(f"the loop starts {start:.3f} s into the take; the split across opens at {[round(t, 2) for t in opens]}")
