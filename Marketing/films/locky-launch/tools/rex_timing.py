#!/usr/bin/env python3
"""Finds, in a take of the Rex lock screen, the moment it first shows a program that needs the user: the first frame
in which the dot of the agents pane's first row is orange.

  python3 tools/rex_timing.py          the Rex clip: writes that moment, in the clip's own time, to src/rex-timing.json
  python3 tools/rex_timing.py film [TAKE.mkv]
                                       the launch film: cuts four seconds of the take (default rex-film.mkv) around
                                       that moment (two before, two after) as the clip rexfilm in src/clips.json
"""
import json, os, subprocess, sys
import numpy as np

FILM = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(FILM, "src", "clips.json")
clips = json.load(open(path))
film = "film" in sys.argv[1:]
take = next((a for a in sys.argv[1:] if a.endswith(".mkv")), "rex-film.mkv") if film else clips["rexclip"]["file"]
# The dot of the first row: 16 pixels around (1968, 556) of the 3520 x 1980 take.
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(FILM, "footage", take), "-vf",
                      "setpts=PTS-STARTPTS,fps=60,crop=16:16:1960:548", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True).stdout
dot = np.frombuffer(raw, np.uint8).reshape(-1, 16 * 16, 3).astype(np.float32).mean(axis=1)
# The glass under the dot dims it, so the test is its hue: orange has less than half the green of the yellow before it.
orange = (dot[:, 0] > 150) & (dot[:, 1] < 90)
first = next(i for i in range(1, len(orange)) if orange[i] and not orange[i - 1]) / 60
if film:
    clips["rexfilm"] = {"file": take, "in": round(first - 2.0, 3), "out": round(first + 2.3, 3)}
    json.dump(clips, open(path, "w"), indent=1)
    print(f"a program needs the user {first:.3f} s into the take: rexfilm is cut from {first - 2.0:.3f} s")
else:
    needs = round(first - clips["rexclip"]["in"], 3)
    json.dump({"needs": needs}, open(os.path.join(FILM, "src", "rex-timing.json"), "w"))
    print("a program needs the user", needs, "s into the clip")
