#!/usr/bin/env python3
"""Finds, in the Rex clip's take, the moment the lock screen first shows a program that needs the user: the first
frame in which the dot of the agents pane's first row is orange. Writes it, in the clip's own time, to
src/rex-timing.json, where the clip's page and its sound read it.

  python3 tools/rex_timing.py
"""
import json, os, subprocess
import numpy as np

FILM = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
clip = json.load(open(os.path.join(FILM, "src", "clips.json")))["rexclip"]
# The dot of the first row: 16 pixels around (1968, 556) of the 3520 x 1980 take.
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(FILM, "footage", clip["file"]), "-vf",
                      "setpts=PTS-STARTPTS,fps=60,crop=16:16:1960:548", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True).stdout
dot = np.frombuffer(raw, np.uint8).reshape(-1, 16 * 16, 3).astype(np.float32).mean(axis=1)
# The glass under the dot dims it, so the test is its hue: orange has less than half the green of the yellow before it.
orange = (dot[:, 0] > 150) & (dot[:, 1] < 90)
first = next(i for i in range(1, len(orange)) if orange[i] and not orange[i - 1])
needs = round(first / 60 - clip["in"], 3)
json.dump({"needs": needs}, open(os.path.join(FILM, "src", "rex-timing.json"), "w"))
print("a program needs the user", needs, "s into the clip")
