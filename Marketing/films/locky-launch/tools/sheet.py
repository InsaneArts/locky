#!/usr/bin/env python3
"""A contact sheet of a rendered film at given times, each still marked with its time.
  python3 tools/sheet.py VIDEO OUT.jpg T1,T2,... [COLUMNS]"""
import subprocess, sys
video, out, times = sys.argv[1], sys.argv[2], sys.argv[3].split(",")
cols = int(sys.argv[4]) if len(sys.argv) > 4 else 4
inputs, parts = [], []
for i, t in enumerate(times):
    inputs += ["-ss", t, "-i", video]
    parts.append(f"[{i}:v]trim=end_frame=1,scale=640:360,drawtext=text='{t} s':x=10:y=10:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6[s{i}]")
layout = "|".join(f"{(k % cols) * 646}_{(k // cols) * 366}" for k in range(len(times)))
graph = ";".join(parts) + ";" + "".join(f"[s{k}]" for k in range(len(times))) + f"xstack=inputs={len(times)}:layout={layout}:fill=0x202020"
subprocess.run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", graph, "-frames:v", "1", "-q:v", "3", out], check=True)
print(out)
