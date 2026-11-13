#!/usr/bin/env python3
"""Lookout through the day: `locky render` at each hour, with the shader's own hour parameter (packages/lookout).

The frames go to build/frames/lapse/00001.jpg, evenly spaced from FROM to TO hours; the film picks the frame for the
hour it shows. The theme is Lookout as shipped, less its widgets (the clock cannot follow a set hour) and its birds
(they fly by the shader's clock, which every render starts again).

  python3 tools/lapse.py [frames]
"""
import concurrent.futures, json, os, shutil, subprocess, sys, tempfile

FILM = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCKY = "/Applications/Locky.app/Contents/MacOS/Locky"
FROM, TO = 10.5, 22.75
N = next((int(a) for a in sys.argv[1:] if a.isdigit()), 360)
out = os.path.join(FILM, "build", "frames", "lapse")
REPAIR = "--repair" in sys.argv          # keep the frames, and render again only those that came out wrong
if not REPAIR:
    shutil.rmtree(out, ignore_errors=True)
os.makedirs(out, exist_ok=True)
work = tempfile.mkdtemp(prefix="locky-lapse-")


def render(i):
    hour = FROM + (TO - FROM) * i / (N - 1)
    config = os.path.join(work, f"c{i}")
    os.makedirs(config)
    open(os.path.join(config, "settings.json"), "w").write('{ "privacy": true }')
    open(os.path.join(config, "init.lua"), "w").write(f"""
locky.theme.extend("lookout", function(theme)
  theme.widgets = {{}}
  theme.background.params = {{ {hour:.4f}, 0 }}
  theme.background.resolution = 1
end)
""")
    png = os.path.join(work, f"{i}.png")
    env = {**os.environ, "LOCKY_CONFIG_DIR": config, "LOCKY_WALLPAPER": "none"}
    for attempt in range(3):
        r = subprocess.run([LOCKY, "render", "--theme", "lookout", "--size", "1760x990", "--out", png], env=env, capture_output=True, text=True)
        if r.returncode == 0 and os.path.exists(png):
            break
    else:
        raise RuntimeError(f"frame {i}: {r.stdout}{r.stderr}")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", png, "-q:v", "2", "-pix_fmt", "yuvj420p", os.path.join(out, f"{i + 1:05d}.jpg")], check=True)
    os.remove(png)
    shutil.rmtree(config)
    return i


def brightness():
    """Each frame's mean, from 0 to 1."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-framerate", "60", "-i", os.path.join(out, "%05d.jpg"), "-vf", "scale=32:18:flags=area",
                          "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True).stdout
    return [sum(raw[i * 576:(i + 1) * 576]) / 576 / 255 for i in range(len(raw) // 576)]


if not REPAIR:
    with concurrent.futures.ThreadPoolExecutor(8) as pool:
        for i in pool.map(render, range(N)):
            if i % 40 == 0:
                print("frame", i, flush=True)
# Under load a render now and then draws before its shader has a frame, and comes out black: the day's light changes
# slowly, so a frame far from both its neighbours is one of those. They are rendered again, one at a time.
for attempt in range(5):
    b = brightness()
    bad = [i for i in range(N) if abs(b[i] - (b[max(i - 1, 0)] + b[min(i + 1, N - 1)]) / 2) > 0.03 or b[i] < 0.004]
    if not bad:
        break
    print("rendering again:", bad, flush=True)
    for i in bad:
        render(i)
json.dump({"stamp": "lapse", "n": N, "w": 3520, "h": 1980, "from": FROM, "to": TO}, open(os.path.join(out, "meta.json"), "w"))
shutil.rmtree(work, ignore_errors=True)
print("done", N)
