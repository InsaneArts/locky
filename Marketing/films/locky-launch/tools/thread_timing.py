#!/usr/bin/env python3
"""The timing of the thread clips' takes, measured as tools/timing.py measures the film's:

- src/thread-events.json: each Settings take's clicks in its clip's own time, with the frame where the app answered.
- src/thread-transitions.json: in each new take of a lock animation, where the way out starts, where the screen under
  it shows alone, and where the way in ends. A take is measured against the screenshot it played over
  (/Users/Shared/locky-film/desk-<theme>.png); without that picture its numbers from the last run stay.

  python3 tools/thread_timing.py
"""
import json, os, subprocess
import numpy as np

FILM = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOOTAGE = os.path.join(FILM, "footage")
CLIPS = json.load(open(os.path.join(FILM, "src", "clips.json")))
SESSIONS = {"set-touchid": "ui-set-touchid", "set-autolock": "ui-set-autolock", "set-anim": "ui-set-anim", "set-photo": "ui-set-photo",
            "set-tour": "ui-set-tour"}
TAKES = {"wayfocus": ("way-focus", "desk-sakura"), "wayfade": ("way-fade", "desk-tokyonight"), "waylift": ("way-lift", "desk-neoncity"),
         "wayiris": ("way-iris", "desk-synthwave")}
W, H = 160, 90


def gray(args, w=W, h=H):
    raw = subprocess.run(["ffmpeg", "-v", "error", *args, "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, h, w).astype(np.float32)


def first_frame(path):
    return float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=start_time", "-of", "csv=p=0", path],
                                capture_output=True, text=True).stdout)


def seen(d, t, within=1.2):
    """The time of the first frame after t that differs clearly from the one before: the app's answer."""
    i0 = int(t * 60) + 1
    calm = np.median(d[max(i0 - 40, 1):i0]) if i0 > 1 else 0
    limit = max(calm * 4, 0.12)
    for i in range(i0, min(i0 + int(within * 60), len(d))):
        if d[i] > limit:
            return round(i / 60, 3)
    return None


events = {}
for clip, name in SESSIONS.items():
    path = os.path.join(FOOTAGE, f"{name}.mkv")
    start = first_frame(path) + CLIPS[clip].get("in", 0)
    f = gray(["-i", path, "-vf", "setpts=PTS-STARTPTS,fps=60,scale=320:180"], 320, 180)
    d = np.concatenate([[0], np.abs(f[1:] - f[:-1]).mean(axis=(1, 2))])
    events[clip] = []
    for e in json.load(open(os.path.join(FOOTAGE, f"{name}.json"))):
        if e["kind"] not in ("click", "key", "drag"):
            continue
        e = {**{k: v for k, v in e.items() if k != "t"}, "t": round(e["t"] - start, 3)}
        e["seen"] = seen(d, e["t"])
        events[clip].append(e)
    print(clip, [(e.get("note") or e["kind"], e["t"], e["seen"]) for e in events[clip]])
json.dump(events, open(os.path.join(FILM, "src", "thread-events.json"), "w"), indent=1)

target = os.path.join(FILM, "src", "thread-transitions.json")
transitions = json.load(open(target)) if os.path.exists(target) else {}
for clip, (name, picture) in TAKES.items():
    if not os.path.exists(f"/Users/Shared/locky-film/{picture}.png"):
        print(f"{clip}: kept (no {picture}.png to measure against)")
        continue
    f = gray(["-i", os.path.join(FOOTAGE, f"{name}.mkv"), "-vf", f"setpts=PTS-STARTPTS,fps=60,scale={W}:{H}"])
    under = gray(["-i", f"/Users/Shared/locky-film/{picture}.png", "-vf", f"scale={W}:{H}", "-frames:v", "1"])[0]
    to_under = np.abs(f - under).mean(axis=(1, 2))
    alone = [i for i in range(len(f)) if to_under[i] < to_under.min() + 0.6]
    a, b = alone[0], alone[-1]
    lock = f[b + 45:b + 75].mean(axis=0)
    to_lock = np.abs(f - lock).mean(axis=(1, 2))
    settled = np.percentile(to_lock[b + 60:b + 100], 90)
    in_end = next(i for i in range(b, len(f)) if to_lock[i] <= settled * 1.15 + 0.3)
    before = np.percentile(to_lock[20:80], 90)
    out_start = max(i for i in range(20, a) if to_lock[i] <= before * 1.15 + 0.3) + 1
    transitions[clip] = {"n": len(f), "out_start": out_start, "desk_from": a, "desk_to": b, "in_end": in_end}
    print(f"{clip}: out {out_start} to {a}, the screen alone {a} to {b}, in {b} to {in_end}, of {len(f)} frames")
json.dump(transitions, open(target, "w"), indent=1)
