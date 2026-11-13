#!/usr/bin/env python3
"""The film's recorded sessions in the real app: real clicks, drags, and typing in the Atlas helper.

Each session writes footage/<name>.mkv and footage/<name>.json (every action with its wall-clock time and its
point in the window, so the film can draw a pointer in step). Coordinates are the window's own points: the Themes
window is 1760 x 990, at the right edge of the helper's screen so that popovers stay inside it.

  python3 tools/sessions.py browse|schedule|customize|font|new|agent|lock ...
"""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shoot
from shoot import atlas, sh

X, Y, W, H = 992, 72, 1760, 990


class Take:
    def __init__(self, name):
        self.name, self.log = name, shoot.Log(name)

    def start(self):
        shoot.record(self.name, (X, Y, W, H))
        self.log.add("start")

    def end(self):
        self.log.add("end")
        shoot.stop(self.name)
        shoot.fetch(self.name)
        self.log.save()
        print(self.name, "saved", flush=True)

    def wait(self, seconds):
        time.sleep(seconds)

    def click(self, x, y, wait=0.8, note=""):
        self.log.add("click", x=x, y=y, note=note)
        atlas("click", str(X + x), str(Y + y))
        time.sleep(wait)

    def named(self, name, wait=1.0):
        d = atlas("click", "--app", "Locky", "--name", name)
        f = (d.get("element") or {}).get("frame") or {}
        self.log.add("click", x=f.get("x", 0) + f.get("width", 0) / 2 - X, y=f.get("y", 0) + f.get("height", 0) / 2 - Y, note=name)
        time.sleep(wait)

    def drag(self, x0, y0, x1, y1, wait=0.9, note=""):
        self.log.add("drag", x=x0, y=y0, x1=x1, y1=y1, note=note)
        atlas("drag", str(X + x0), str(Y + y0), str(X + x1), str(Y + y1))
        self.log.add("dragend", x=x1, y=y1)
        time.sleep(wait)

    def key(self, *keys, wait=0.3, note=""):
        self.log.add("key", keys=list(keys), note=note)
        atlas("key", *keys)
        time.sleep(wait)

    def type(self, text, wait=0.5):
        self.log.add("type", text=text)
        atlas("type", text)
        self.log.add("typed")
        time.sleep(wait)

    def scroll(self, x, y, lines, wait=0.5):
        """A wheel turn a line at a time, so the list moves, not jumps."""
        self.log.add("scroll", x=x, y=y, lines=lines)
        step = 1 if lines > 0 else -1
        left = abs(lines)
        while left:
            n = min(left, 15)
            actions = []
            for _ in range(n):
                actions += [{"type": "scroll", "x": X + x, "y": Y + y, "dy": step}, {"type": "wait", "ms": 28}]
            atlas("input", json.dumps(actions))
            left -= n
        time.sleep(wait)


def popup(value):
    """The centre of the pop-up button that shows `value`, in window points."""
    for e in atlas("elements", "--app", "Locky", "--role", "AXPopUpButton").get("elements", []):
        if e.get("value") == value:
            f = e["frame"]
            return f["x"] + f["width"] / 2 - X, f["y"] + f["height"] / 2 - Y
    raise RuntimeError(f"no pop-up button shows {value}")


def open_themes(editing=None, **settings):
    """The Themes window, moved to the right edge of the screen, with its list focused on the theme in use."""
    shoot.close()
    shoot.settings(**settings)
    args = ["window", "themes", "--size", f"{W}x{H}", "--behind"] + (["--theme", editing] if editing else [])
    shoot.launch(*args)
    time.sleep(2.0)
    b = [w for w in shoot.windows() if w[1]["width"] == W][0][1]
    if b["x"] != X:
        atlas("drag", str(int(b["x"] + 750)), str(int(b["y"] + 26)), str(int(b["x"] + 750 + X - b["x"])), str(int(b["y"] + 26)))
        time.sleep(0.8)
    b = [w for w in shoot.windows() if w[1]["width"] == W][0][1]
    assert (b["x"], b["y"]) == (X, Y), b
    time.sleep(1.5)


def wait_second(lo=0, hi=3):
    """Waits until the clock's seconds are between lo and hi: two takes that must show the same minute start here."""
    while not lo <= time.localtime().tm_sec <= hi:
        time.sleep(0.2)


def browse():
    """B2: the list of 43. Bauhaus is in use; the selection goes down the list, and each theme goes live."""
    open_themes(theme="bauhaus")
    atlas("click", str(X + 120), str(Y + 143))     # the Bauhaus row: the list takes the keyboard
    time.sleep(2.5)
    wait_second()
    t = Take("ui-browse")
    t.start()
    t.wait(2.4)
    for _ in range(12):
        began = time.time()
        t.key("down", wait=0)
        # A second a step: some themes take most of it to draw their live preview. The film cuts the waits.
        time.sleep(max(0, 1.0 - (time.time() - began)))
    t.wait(1.6)
    t.end()


def schedule():
    """D3: the Schedule popover, with a theme for the day and one for the night."""
    open_themes(theme="lookout", schedule={"mode": "time", "day": "lookout", "night": "observatory",
                                           "day_starts": "07:00", "night_starts": "19:00"})
    time.sleep(1.5)
    t = Take("ui-schedule")
    t.start()
    t.wait(1.4)
    t.click(1732, 26, wait=3.2, note="schedule")
    t.end()


def customize():
    """E: Customize on Aurora. Drag the clock and the date, add a calendar, and change the sky."""
    sh(f"rm -rf '{shoot.WORK}/config/themes'")
    open_themes(theme="default")
    atlas("click", str(X + 120), str(Y + 95))
    time.sleep(2.5)
    t = Take("ui-customize")
    t.start()
    t.wait(1.2)
    t.named("Customize…", wait=2.2)
    t.drag(730, 278, 372, 300, note="clock")
    t.drag(730, 190, 372, 196, note="date")
    t.wait(0.3)
    t.click(1512, 26, wait=1.6, note="add")
    t.scroll(880, 500, 20, wait=0.7)
    t.click(909, 587, wait=0.9, note="medium")
    t.click(937, 587, wait=0.9, note="large")
    t.click(909, 587, wait=0.9, note="medium")
    t.click(880, 470, wait=1.8, note="add calendar")
    t.drag(730, 520, 1150, 330, note="calendar")
    t.click(300, 720, wait=1.0, note="deselect")
    t.click(1693, 100, wait=0.8, note="background")
    t.click(1669, 125, wait=1.6, note="animated")
    for name, (x, y) in [("galaxysea", (1697, 236)), ("deepblue", (1697, 159)), ("synthwave", (1609, 698)), ("sakura", (1609, 621))]:
        t.click(x, y, wait=1.5, note=name)
    t.wait(1.0)
    t.end()


def font():
    """E4: the font's design. The session goes on from customize()'s theme."""
    t = Take("ui-font")
    # The Font section is below the backgrounds: scroll the inspector to its end first.
    atlas("scroll", str(X + 1610), str(Y + 600), "--dy", "60")
    time.sleep(1.0)
    t.start()
    t.wait(1.0)
    for now, then, down in [("Rounded", "Serif", 24), ("Serif", "Monospaced", 24), ("Monospaced", "Serif", -24)]:
        x, y = popup(now)
        t.click(x, y, wait=0.8, note="design")
        t.click(x - 20, y + down, wait=1.5, note=then)
    t.wait(0.8)
    t.end()


def new():
    """F1: a theme from nothing. A sky, a word, a line: the film's end card."""
    sh(f"rm -rf '{shoot.WORK}/config/themes'")
    open_themes(theme="default")
    time.sleep(1.0)
    t = Take("ui-new")
    t.start()
    t.wait(1.2)
    t.click(1697, 26, wait=2.6, note="new theme")
    t.click(1690, 80, wait=0.4, note="name")
    t.key("cmd+a", wait=0.2)
    t.type("Launch Day", wait=0.3)
    t.key("return", wait=0.8)
    t.click(1693, 146, wait=0.8, note="background")
    t.click(1669, 171, wait=1.4, note="animated")
    t.click(1697, 282, wait=1.8, note="galaxysea")
    t.click(1512, 26, wait=1.4, note="add")
    t.key("cmd+a", wait=0.1)
    t.type("text", wait=1.2)
    t.click(633, 385, wait=1.8, note="add text")
    t.click(1665, 350, wait=0.4, note="text field")
    t.key("cmd+a", wait=0.2)
    t.type("Locky", wait=0.3)
    t.key("return", wait=0.9)
    t.click(1692, 392, wait=0.8, note="size")
    t.click(1679, 441, wait=1.0, note="huge")
    t.click(1693, 430, wait=0.8, note="weight")
    t.click(1680, 479, wait=1.0, note="semibold")
    t.click(1512, 26, wait=1.4, note="add")
    t.key("cmd+a", wait=0.1)
    t.type("text", wait=1.2)
    t.click(633, 385, wait=1.8, note="add text")
    t.click(1665, 350, wait=0.4, note="text field")
    t.key("cmd+a", wait=0.2)
    t.type("The lock screen you build yourself.", wait=0.3)
    t.key("return", wait=0.9)
    t.drag(730, 520, 730, 603, note="line")
    t.click(1656, 468, wait=0.8, note="color")
    t.click(1656, 621, wait=1.0, note="muted")
    t.click(300, 760, wait=2.0, note="deselect")
    t.end()


def restore_launch():
    """Puts the theme that new() made (config/settings-launch.json, themes/untitled-theme.lua) and the agent's widget
    back into the helper's config."""
    film = shoot.FILM
    for src, dst in [("config/settings-launch.json", "settings.json"), ("config/themes/untitled-theme.lua", "themes/untitled-theme.lua"),
                     ("config/plugin/vacation.lua", "plugin/vacation.lua")]:
        text = open(os.path.join(film, src)).read()
        sh(f"mkdir -p '{shoot.WORK}/config/themes' '{shoot.WORK}/config/plugin' && cat > '{shoot.WORK}/config/{dst}' <<'LOCKYEOF'\n{text}\nLOCKYEOF")


def open_editor(theme):
    """Customize for `theme`, in the window at the right edge, without touching settings.json."""
    shoot.close()
    shoot.launch("window", "themes", "--size", f"{W}x{H}", "--behind", "--theme", theme)
    time.sleep(2.0)
    b = [w for w in shoot.windows() if w[1]["width"] == W][0][1]
    if b["x"] != X:
        atlas("drag", str(int(b["x"] + 750)), str(int(b["y"] + 26)), str(int(b["x"] + 750 + X - b["x"])), str(int(b["y"] + 26)))
        time.sleep(0.8)
    time.sleep(2.0)


def agent():
    """F3: the widget a coding agent wrote (config/plugin/vacation.lua) goes onto the new theme from Add Widget."""
    text = open(os.path.join(shoot.FILM, "config/plugin/vacation.lua")).read()
    sh(f"mkdir -p '{shoot.WORK}/config/plugin' && cat > '{shoot.WORK}/config/plugin/vacation.lua' <<'LOCKYEOF'\n{text}\nLOCKYEOF")
    open_editor("untitled-theme")
    wait_second()            # lock() follows in the same minute: the editor's clock and the lock's must agree
    t = Take("ui-agent")
    t.start()
    t.wait(1.4)
    t.click(1512, 26, wait=1.5, note="add")
    t.key("cmd+a", wait=0.1)
    t.type("vac", wait=1.3)
    t.click(633, 385, wait=1.9, note="add vacation")
    # The new widget lands on the word in the middle, so it goes to the corner by Pinned to, not by a drag. The
    # grid's place depends on the widget's header: read it from the app.
    els = atlas("elements", "--app", "Locky").get("elements", [])
    cells = [e["frame"] for e in els if e.get("role") == "AXButton" and round(e["frame"]["width"]) == 16 and round(e["frame"]["height"]) == 11]
    cell = min(cells, key=lambda f: (f["y"], -f["x"]))
    fields = sorted((e["frame"] for e in els if e.get("role") == "AXTextField" and round(e["frame"]["width"]) == 60), key=lambda f: f["x"])
    t.click(cell["x"] + 8 - X, cell["y"] + 5 - Y, wait=1.2, note="pin top right")
    t.click(fields[0]["x"] + 30 - X, fields[0]["y"] + 12 - Y, wait=0.3, note="offset x")
    t.key("cmd+a", wait=0.15)
    t.type("-56", wait=0.2)
    t.key("tab", wait=0.5)
    t.key("cmd+a", wait=0.15)
    t.type("56", wait=0.2)
    t.key("return", wait=1.0)
    t.click(300, 780, wait=2.2, note="deselect")
    t.end()


FILM_BUILD = "/Users/Shared/locky-film/Locky.app/Contents/MacOS/Locky"


def lock_take(name, theme, style, desk, typing=None, hold=2.5, tail=2.5):
    """The lock's own way in, over a real screenshot: the film build of Locky (the scratch worktree; its one change is
    that $LOCKY_DESKTOP stands in for the preview's drawn desktop). Return in the preview plays the way in again."""
    shoot.close()
    sh(f"LOCKY_CONFIG_DIR='{shoot.WORK}/config' LOCKY_WALLPAPER=none LOCKY_DESKTOP='{desk}' nohup '{FILM_BUILD}' preview --theme '{theme}' "
       f"--transition '{style}' --size {shoot.SIZE[0]}x{shoot.SIZE[1]} --behind > '{shoot.WORK}/locky.log' 2>&1 &")
    time.sleep(5.0)
    b = [w for w in shoot.windows() if "Preview" in (w[0] or "")][0][1]
    top = b["height"] - shoot.SIZE[1]
    cx, cy = b["x"] + 880, b["y"] + top + 300
    atlas("click", str(int(cx)), str(int(cy)))          # the window takes the keyboard
    time.sleep(1.5)
    log = shoot.Log(name)
    shoot.record(name, (b["x"], b["y"] + top, shoot.SIZE[0], shoot.SIZE[1]))
    log.add("start")
    time.sleep(0.8)
    log.add("key", keys=["return"], note="lock")
    atlas("key", "return")
    time.sleep(hold)
    if typing:
        for ch in typing:
            log.add("type", text=ch)
            atlas("type", ch)
            time.sleep(0.09)
        time.sleep(tail)
    log.add("end")
    shoot.stop(name)
    shoot.fetch(name)
    log.save()
    print(name, "saved", flush=True)


def lock():
    """G: the lock comes in over the editor's last frame, and a password is typed (letters, never a real one)."""
    # The editor's last frame, from the agent's take, is the screen the lock comes in over.
    import subprocess
    src = os.path.join(shoot.FOOTAGE, "ui-agent.mkv")
    n = int(subprocess.run(["ffprobe", "-v", "error", "-count_frames", "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", src],
                           capture_output=True, text=True).stdout)
    desk = "/Users/Shared/locky-film/desk-launch.png"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-vf", f"setpts=PTS-STARTPTS,select='gte(n\\,{n - 8})'", "-frames:v", "1", desk], check=True)
    os.chmod(desk, 0o644)
    json.dump({"frame": n - 8}, open(os.path.join(shoot.FOOTAGE, "ui-agent-desk.json"), "w"))
    lock_take("lock-in", "untitled-theme", "iris", desk, typing="makeityours", hold=2.6, tail=8.0)


def page_frame(theme, out):
    """A fresh frame of the Themes window with `theme` in use, as the screen a lock comes in over."""
    import subprocess
    open_themes(theme=theme)
    wait_second(5, 9)        # a few seconds into the minute: the preview's clock has turned by then
    shot = atlas("screenshot")["path"]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", shot, "-vf", f"crop={W * 2}:{H * 2}:{X * 2}:{Y * 2}", out], check=True)
    os.chmod(out, 0o644)


def ways():
    """B2 and S in step with the clock: the list walk, then three locks, each in the minute of the frame under it."""
    import subprocess
    # The theme the film builds later is not in the list yet.
    sh(f"rm -rf '{shoot.WORK}/config/themes'")
    browse()
    # The walk's last theme: its frame in the walk is the screen the first lock comes in over.
    log = json.load(open(os.path.join(shoot.FOOTAGE, "ui-browse.json")))
    src = os.path.join(shoot.FOOTAGE, "ui-browse.mkv")
    first = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=start_time", "-of", "csv=p=0", src], capture_output=True, text=True).stdout)
    keys = [e["t"] - first for e in log if e["kind"] == "key"]
    desk = "/Users/Shared/locky-film/desk-galaxysea.png"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-vf", f"setpts=PTS-STARTPTS,select='gte(t\\,{keys[9] + 0.9:.3f})'", "-frames:v", "1", desk], check=True)
    os.chmod(desk, 0o644)
    lock_take("way-tiles", "galaxysea", "tiles", desk, hold=3.2)
    for name, theme, style in [("way-sweep", "deepblue", "sweep"), ("way-dissolve", "braun", "dissolve")]:
        desk = f"/Users/Shared/locky-film/desk-{theme}.png"
        page_frame(theme, desk)
        lock_take(name, theme, style, desk, hold=3.2)


if __name__ == "__main__":
    for name in sys.argv[1:]:
        globals()[name]()
