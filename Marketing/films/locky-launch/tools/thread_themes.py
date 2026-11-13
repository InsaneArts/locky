#!/usr/bin/env python3
"""The list of the 43 themes for the thread's first clip: src/thread-themes.json, and a half-second clip of each in
src/clips.json (t-<id>).

The names come from `locky themes`. The six the owner likes best go first; the others follow from dark to light, so
the cuts never flash. A theme's words are ink on a light picture and white on a dark one, measured where they sit.

  python3 tools/thread_themes.py
"""
import json, os, re, subprocess, tempfile
import numpy as np

FILM = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCKY = "/Applications/Locky.app/Contents/MacOS/Locky"
FIRST = ["sakura", "synthwave", "neoncity", "tokyonight", "gruvbox", "mocha"]
W, H = 192, 108

listing = subprocess.run([LOCKY, "themes"], capture_output=True, text=True, env={**os.environ, "LOCKY_CONFIG_DIR": tempfile.mkdtemp()}).stdout
names = dict(re.findall(r"^(\S+) \((.+?)\) — ", listing, re.M))
assert len(names) == 43, len(names)


def look(theme):
    """A frame of the theme's take, small and gray."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(FILM, "footage", f"lock-{theme}.mkv"), "-vf",
                          f"setpts=PTS-STARTPTS,trim=start=1.2,scale={W}:{H}", "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "gray", "-"],
                         capture_output=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(H, W).astype(np.float32)


themes = []
for theme, name in names.items():
    g = look(theme)
    words = g[int(H * 0.72):int(H * 0.88), int(W * 0.05):int(W * 0.42)]      # where the name and the count sit
    themes.append({"id": theme, "name": name, "ink": "dark" if words.mean() > 140 else "light", "light": round(float(g.mean()), 1)})
rest = sorted((t for t in themes if t["id"] not in FIRST), key=lambda t: t["light"])
themes = [next(t for t in themes if t["id"] == f) for f in FIRST] + rest
json.dump(themes, open(os.path.join(FILM, "src", "thread-themes.json"), "w"), indent=1)

path = os.path.join(FILM, "src", "clips.json")
clips = json.load(open(path))
for t in themes:
    clips[f"t-{t['id']}"] = {"file": f"lock-{t['id']}.mkv", "in": 1.0, "out": 1.6, "width": 2112}
json.dump(clips, open(path, "w"), indent=1)
for t in themes:
    print(f"{t['id']:14} {t['name']:20} {t['ink']:5} {t['light']}")
