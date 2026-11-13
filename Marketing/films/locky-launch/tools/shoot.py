#!/usr/bin/env python3
"""Shoots real Locky footage in the Atlas helper (a hidden second login), so nothing shows on the owner's desktop.

Locky runs there from /Applications/Locky.app with its own config folder (atlas-work/locky-film/config), in its
screenshot mode (--behind), so previews draw while the helper's windows are hidden. ffmpeg records the helper's
screen at its real pixels (2 per point) and crops to the window's content. Every frame carries its wall-clock time,
and every click is logged with its wall-clock time, so the film can draw a pointer in step with the footage.

  import shoot; shoot.lock_clip("default", 6)
"""
import json, os, subprocess, time

FILM = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOOTAGE = os.path.join(FILM, "footage")
# The helper's home folder, asked of the helper itself. This account can read files there, so footage is copied out.
HELPER_HOME = json.loads(subprocess.run(["atlas", "run", "--", "/bin/sh", "-c", 'printf %s "$HOME"'], capture_output=True, text=True).stdout or "{}").get("output", "")
WORK = f"{HELPER_HOME}/atlas-work/locky-film"
LOCKY = "/Applications/Locky.app/Contents/MacOS/Locky"
FFMPEG = "/opt/homebrew/bin/ffmpeg"
# A preview's content, in points: the largest 16:9 that fits between the menu bar and the Dock.
SIZE = (1760, 990)


def atlas(*args, timeout=120):
    r = subprocess.run(["atlas", *args], capture_output=True, text=True, timeout=timeout)
    try:
        return json.loads(r.stdout or r.stderr or "{}")
    except json.JSONDecodeError:
        return {"ok": False, "raw": r.stdout + r.stderr}


def sh(script, timeout=20):
    """Runs a shell script as the helper and returns its output."""
    d = atlas("run", "--timeout", str(timeout), "--", "/bin/sh", "-c", script, timeout=timeout + 30)
    return d.get("output", "") if d.get("ok") else f"FAILED: {d}"


def settings(**values):
    """Writes the helper's settings.json: privacy mode on, and no ambient fade unless asked for."""
    data = {"privacy": True, "ambient_after": 0, **values}
    sh(f"mkdir -p '{WORK}/config' '{WORK}/rec' && cat > '{WORK}/config/settings.json' <<'EOF'\n{json.dumps(data, indent=1)}\nEOF")


def close():
    atlas("close", "--app", "Locky")
    time.sleep(0.6)


def launch(*args, env=""):
    """Starts Locky in the helper with these arguments, and returns once its window shows."""
    quoted = " ".join(f"'{a}'" for a in args)
    sh(f"LOCKY_CONFIG_DIR='{WORK}/config' LOCKY_WALLPAPER=none {env} nohup '{LOCKY}' {quoted} > '{WORK}/locky.log' 2>&1 &")
    for _ in range(40):
        time.sleep(0.25)
        windows = atlas("windows").get("windows", [])
        mine = [w for w in windows if "Locky" in (w.get("title") or "") or (w.get("title") or "") in ("Themes", "Settings")
                or w.get("bounds", {}).get("width") in (SIZE[0], 1600)]
        if mine:
            return mine[0]["bounds"]
    raise RuntimeError("no Locky window")


def windows():
    return [(w.get("title"), w.get("bounds")) for w in atlas("windows").get("windows", [])]


def record(name, crop, cursor=0):
    """Starts ffmpeg in the helper. crop is (x, y, w, h) in points. stop(name) ends it. Frames keep their wall-clock
    times (-copyts), so -t cannot limit the length: it would count from 1970."""
    x, y, w, h = [int(v * 2) for v in crop]
    limit = ""
    out = f"{WORK}/rec/{name}.mkv"
    sh(f"rm -f '{out}'; nohup {FFMPEG} -nostdin -hide_banner -loglevel error -use_wallclock_as_timestamps 1 -f avfoundation -framerate 60 "
       f"-capture_cursor {cursor} -pixel_format bgr0 -i '0:none' {limit} -vf 'crop={w}:{h}:{x}:{y}' -c:v libx264 -preset ultrafast "
       f"-crf 8 -pix_fmt yuv420p -copyts -y '{out}' < /dev/null > '{WORK}/rec/{name}.log' 2>&1 & echo $! > '{WORK}/rec/{name}.pid'")
    time.sleep(1.2)          # the capture session takes about a second to deliver its first frame


def stop(name):
    sh(f"kill -INT $(cat '{WORK}/rec/{name}.pid'); sleep 1.5; true")


def fetch(name):
    os.makedirs(FOOTAGE, exist_ok=True)
    subprocess.run(["cp", f"{WORK}/rec/{name}.mkv", os.path.join(FOOTAGE, f"{name}.mkv")], check=True)
    return os.path.join(FOOTAGE, f"{name}.mkv")


class Log:
    """Each action with the wall-clock time it was sent, next to the clip."""
    def __init__(self, name):
        self.name, self.events = name, []

    def add(self, kind, **data):
        self.events.append({"t": time.time(), "kind": kind, **data})

    def save(self):
        json.dump(self.events, open(os.path.join(FOOTAGE, f"{self.name}.json"), "w"), indent=1)


def lock_clip(theme, seconds=6, settle=4.0, name=None):
    """A live lock screen, full frame: the preview's content at 3520 x 1980 pixels."""
    close()
    b = launch("preview", "--theme", theme, "--size", f"{SIZE[0]}x{SIZE[1]}", "--behind")
    time.sleep(settle)
    title = b["height"] - SIZE[1]
    name = name or f"lock-{theme}"
    record(name, (b["x"], b["y"] + title, SIZE[0], SIZE[1]))
    time.sleep(seconds)
    stop(name)
    return fetch(name)


if __name__ == "__main__":
    import sys
    settings()
    for theme in sys.argv[1:]:
        print(lock_clip(theme), flush=True)
    close()
