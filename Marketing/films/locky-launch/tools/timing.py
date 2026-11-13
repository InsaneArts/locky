#!/usr/bin/env python3
"""What the film needs to know about the footage's timing, read from the takes themselves:

- src/events.json: each session's actions, in its clip's own time (footage/<name>.json has their wall-clock times,
  and every frame of a take carries its wall-clock time).
- src/transitions.json: in each take of the lock's animation, the frames where the way out starts, where the screen
  under it shows alone, and where the way in ends. Measured against the screenshot that take used.

  python3 tools/timing.py
"""
import json, os, subprocess
import numpy as np

FILM = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLIPS = json.load(open(os.path.join(FILM, "src", "clips.json")))
FOOTAGE = os.path.join(FILM, "footage")
SESSIONS = {"browse": "ui-browse", "schedule": "ui-schedule", "customize": "ui-customize", "new": "ui-new", "agent": "ui-agent"}
TAKES = {"lockin": ("lock-in", "desk-launch"), "waytiles": ("way-tiles", "desk-galaxysea"), "waysweep": ("way-sweep", "desk-deepblue"),
         "waydissolve": ("way-dissolve", "desk-braun")}
W, H = 160, 90


def first_frame(path):
    return float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=start_time", "-of", "csv=p=0", path],
                                capture_output=True, text=True).stdout)


events = {}
for clip, name in SESSIONS.items():
    start = first_frame(os.path.join(FOOTAGE, f"{name}.mkv")) + CLIPS[clip].get("in", 0)
    events[clip] = [{**{k: v for k, v in e.items() if k != "t"}, "t": round(e["t"] - start, 3)}
                    for e in json.load(open(os.path.join(FOOTAGE, f"{name}.json"))) if e["kind"] in ("click", "drag", "dragend", "key", "type", "scroll")]
# The agent's take ends on the frame the lock comes in over.
desk = json.load(open(os.path.join(FOOTAGE, "ui-agent-desk.json")))["frame"]
events["agentDesk"] = round(desk / 60 - CLIPS["agent"].get("in", 0), 3)
start = first_frame(os.path.join(FOOTAGE, "lock-in.mkv"))
events["lockinKeys"] = [round(e["t"] - start, 3) for e in json.load(open(os.path.join(FOOTAGE, "lock-in.json"))) if e["kind"] == "type"]


def changes(clip, region=None):
    """How much each frame of a clip differs from the one before, from 0 to 255, in a region (x0, y0, x1, y1 as fractions)."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-framerate", "60", "-i", os.path.join(FILM, "build", "frames", clip, "%05d.jpg"),
                          "-vf", "scale=176:99", "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True).stdout
    f = np.frombuffer(raw, np.uint8).reshape(-1, 99, 176).astype(np.float32)
    if region:
        x0, y0, x1, y1 = region
        f = f[:, int(y0 * 99):int(y1 * 99), int(x0 * 176):int(x1 * 176)]
    return np.concatenate([[0], np.abs(f[1:] - f[:-1]).mean(axis=(1, 2))])


def seen(d, t, within=1.2, after=0.0):
    """The time of the first frame, from `after` seconds past t, that differs clearly from the one before: the app's answer."""
    i0 = int((t + after) * 60) + 1
    calm = np.median(d[max(i0 - 40, 1):i0]) if i0 > 1 else 0
    limit = max(calm * 4, 0.35)
    for i in range(i0, min(i0 + int(within * 60), len(d))):
        if d[i] > limit:
            return round(i / 60, 3)
    return None


# When the app answered each click, drag, and Return: the frame where its picture changes.
for clip in ("customize", "new", "agent", "schedule"):
    d = changes(clip)
    for e in events[clip]:
        if e["kind"] == "click" or (e["kind"] == "key" and e["keys"][0] == "return"):
            e["seen"] = seen(d, e["t"])
# The editor opens on a still picture of the theme and draws the live screen a moment later: when that happens.
opened = next(e for e in events["customize"] if e.get("note") == "Customize…")
raw = subprocess.run(["ffmpeg", "-v", "error", "-framerate", "60", "-i", os.path.join(FILM, "build", "frames", "customize", "%05d.jpg"),
                      "-frames:v", "200", "-vf", "scale=176:99", "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True).stdout
f = np.frombuffer(raw, np.uint8).reshape(-1, 99, 176).astype(np.float32)[:, 10:94, 4:140]
# The live screen is the one that shows two seconds in, before the first drag: the first frame like it.
live = f[int((opened["t"] + 1.7) * 60)]
far = np.abs(f - live).mean(axis=(1, 2))
events["editorLive"] = round(next(i for i in range(int(opened["seen"] * 60), len(f)) if far[i] < 4) / 60, 3)
# The list walk: when each move shows in the list, and when that theme's live preview replaces its still picture.
side, preview = changes("browse", (0.0, 0.05, 0.14, 1.0)), changes("browse", (0.32, 0.07, 0.83, 0.63))
moves = [e["t"] for e in events["browse"] if e["kind"] == "key"]
# The list answers a key 0.16 s later (measured on the first take: 0.14 to 0.18 s).
events["browseSelected"] = [round(t + 0.16, 3) for t in moves]
events["browseLive"] = [seen(preview, t, within=0.8, after=0.07) or round(t + 0.3, 3) for t in events["browseSelected"]]
json.dump(events, open(os.path.join(FILM, "src", "events.json"), "w"), indent=1)


def gray(args):
    raw = subprocess.run(["ffmpeg", "-v", "error", *args, "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, H, W).astype(np.float32)


transitions = {}
for clip, (name, picture) in TAKES.items():
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
json.dump(transitions, open(os.path.join(FILM, "src", "transitions.json"), "w"), indent=1)
for clip in SESSIONS:
    print(clip, [(e.get("note") or e["kind"], e["t"], e.get("seen")) for e in events[clip] if e["kind"] in ("click", "drag") or "seen" in e][:40])
print("editor live", events["editorLive"])
print("list moves", events["browseSelected"])
print("list live ", events["browseLive"])
print("agent desk", events["agentDesk"], "lock keys", events["lockinKeys"])
