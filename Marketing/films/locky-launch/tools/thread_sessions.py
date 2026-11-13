#!/usr/bin/env python3
"""The thread clips' recorded sessions: the Settings window, the Welcome, and four more lock animations.

Like sessions.py: real clicks in the Atlas helper, each logged with its wall-clock time and its point in the window.
Locky runs as a screenshot run (--behind), which starts no auto-lock and no Touch ID button tap: the switches these
takes turn on change only the film's own settings.json.

  python3 tools/thread_sessions.py touchid autolock animation photo tour welcome ways
"""
import json, os, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shoot, sessions
from shoot import atlas, sh

# A take records the window with the helper's desktop around it, 16:9: pop-up menus reach past the window's edge.
# The window (780 x 580 points) sits at MARGIN in the region. Points below are the window's own.
REGION = (1280, 720)
MARGIN = (250, 40)
ROWS = {"General": 117, "Lock Screen": 155, "Unlock": 193, "Customization": 231, "Plugins": 269}
STYLES = ["Fade", "Focus", "Iris", "Lift", "Sweep", "Dissolve", "Tiles"]      # the Lock animation menu, under None


class Settings:
    """The Settings window in Dark mode, with the keyboard, and a take of the region around it."""
    def __init__(self, name, section="settings", **values):
        shoot.close()
        shoot.settings(**values)
        sh(f"LOCKY_CONFIG_DIR='{shoot.WORK}/config' LOCKY_WALLPAPER=none LOCKY_APPEARANCE=dark nohup '{shoot.LOCKY}' window {section} --behind "
           f"> '{shoot.WORK}/locky.log' 2>&1 &")
        time.sleep(4.0)
        b = [w for w in atlas("windows")["windows"] if w.get("owner") == "Locky"][0]["bounds"]
        self.wx, self.wy = b["x"], b["y"]
        atlas("click", str(int(b["x"] + 500)), str(int(b["y"] + 545)))      # an empty place: the window takes the keyboard
        time.sleep(1.2)
        self.take = sessions.Take(name, frame=(b["x"] - MARGIN[0], b["y"] - MARGIN[1], *REGION))

    def controls(self, role):
        """The centres of the pane's controls of a role, top to bottom, in the window's points."""
        els = atlas("elements", "--app", "Locky").get("elements", [])
        frames = sorted((e["frame"] for e in els if e.get("role") == role), key=lambda f: f["y"])
        return [(f["x"] + f["width"] / 2 - self.wx, f["y"] + f["height"] / 2 - self.wy) for f in frames]

    def click(self, x, y, wait=0.8, note=""):
        self.take.click(x + MARGIN[0], y + MARGIN[1], wait=wait, note=note)


def touchid():
    """Settings › General: the switch that makes the Touch ID button show Locky's lock."""
    s = Settings("ui-set-touchid", theme="sakura")
    switch = s.controls("AXCheckBox")[1]
    s.take.start()
    s.take.wait(1.6)
    s.click(*switch, wait=3.0, note="touch id")
    s.take.end()
    print(sh(f"cat '{shoot.WORK}/config/settings.json'"))
    shoot.close()
    shoot.settings()


def autolock():
    """Settings › General › Lock Automatically: after 5 minutes, with the display, and with sleep."""
    s = Settings("ui-set-autolock", theme="sakura", lock_key=True)
    pop = s.controls("AXPopUpButton")[0]
    switches = s.controls("AXCheckBox")
    s.take.start()
    s.take.wait(1.6)
    s.click(*pop, wait=1.5, note="menu")
    s.click(pop[0] + 12, pop[1] + 24.2 * 3, wait=1.5, note="For 5 minutes")      # Never, 1, 2, 5 minutes: a row is 24 points
    s.click(*switches[2], wait=1.1, note="display")
    s.click(*switches[3], wait=2.4, note="sleep")
    s.take.end()
    print(sh(f"cat '{shoot.WORK}/config/settings.json'"))
    shoot.close()
    shoot.settings()


def animation():
    """Settings › Lock Screen: the Lock animation menu, and the small preview that plays the chosen style."""
    s = Settings("ui-set-anim", "lock-screen", theme="sakura")
    pop = s.controls("AXPopUpButton")[0]
    now = "Focus"
    s.take.start()
    s.take.wait(1.6)
    for style in ("Tiles", "Iris", "Sweep"):
        s.click(*pop, wait=1.7, note="menu")
        # The menu opens with the style in use over the button.
        s.click(pop[0] - 8, pop[1] + 24 * (STYLES.index(style) - STYLES.index(now)), wait=3.4, note=style)
        now = style
    s.take.end()
    print(sh(f"cat '{shoot.WORK}/config/settings.json'"))
    shoot.close()
    shoot.settings()


def photo():
    """Settings › Unlock: the Take a photo menu. The pointer goes down to "After 3 wrong passwords", and nothing is
    chosen: a choice makes macOS ask for the camera."""
    s = Settings("ui-set-photo", "unlock", theme="sakura")
    pop = s.controls("AXPopUpButton")[0]
    s.take.start()
    s.take.wait(1.6)
    s.click(*pop, wait=1.4, note="menu")
    # The menu opens with Never over the button; a row is 24 points. Fifteen small moves in 0.6 s: the film's pointer
    # takes the same time (it draws a logged drag so).
    to = (pop[0] + 34, pop[1] + 48)
    s.take.log.add("drag", x=pop[0] + MARGIN[0], y=pop[1] + MARGIN[1], x1=to[0] + MARGIN[0], y1=to[1] + MARGIN[1], note="After 3 wrong passwords")
    moves = []
    for i in range(1, 16):
        moves += [{"type": "move", "x": s.wx + pop[0] + (to[0] - pop[0]) * i / 15, "y": s.wy + pop[1] + (to[1] - pop[1]) * i / 15}, {"type": "wait", "ms": 40}]
    print(atlas("input", json.dumps(moves)).get("ok"))
    s.take.wait(3.6)
    s.take.key("escape", wait=1.2)
    s.take.end()
    print(sh(f"cat '{shoot.WORK}/config/settings.json'"))
    shoot.close()


def tour():
    """The five panes, one after the other."""
    s = Settings("ui-set-tour", theme="sakura")
    s.take.start()
    s.take.wait(1.6)
    for row in ("Lock Screen", "Unlock", "Customization", "Plugins", "General"):
        s.click(100, ROWS[row], wait=1.7, note=row)
    s.take.end()
    shoot.close()


def welcome():
    """The Welcome window's last page, If Something Goes Wrong, as a still: assets/thread/welcome-3.png."""
    shoot.close()
    shoot.settings(theme="sakura")
    sh(f"LOCKY_CONFIG_DIR='{shoot.WORK}/config' LOCKY_WALLPAPER=none LOCKY_APPEARANCE=dark nohup '{shoot.LOCKY}' window welcome --behind "
       f"> '{shoot.WORK}/locky.log' 2>&1 &")
    time.sleep(5.0)
    b = [w for w in atlas("windows")["windows"] if w.get("owner") == "Locky"][0]["bounds"]
    for _ in range(2):
        atlas("click", "--app", "Locky", "--name", "Continue")
        time.sleep(1.8)
    out = os.path.join(shoot.FILM, "assets", "thread")
    os.makedirs(out, exist_ok=True)
    crop = f"crop={int(b['width'] * 2)}:{int(b['height'] * 2)}:{int(b['x'] * 2)}:{int(b['y'] * 2)}"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", atlas("screenshot")["path"], "-vf", crop, os.path.join(out, "welcome-3.png")], check=True)
    shoot.close()


# Four more of the seven lock animations, each over its theme's page in the Themes window, as sessions.ways() does.
WAYS = [("way-focus", "sakura", "focus"), ("way-fade", "tokyonight", "fade"), ("way-lift", "neoncity", "lift"), ("way-iris", "synthwave", "iris")]


def ways():
    for name, theme, style in WAYS:
        desk = f"/Users/Shared/locky-film/desk-{theme}.png"
        sessions.page_frame(theme, desk)
        sessions.lock_take(name, theme, style, desk, hold=3.2)
    shoot.close()


if __name__ == "__main__":
    for name in sys.argv[1:]:
        globals()[name]()
