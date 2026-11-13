#!/usr/bin/env python3
"""Checks a rendered film by measurement: its size, rate, and length; its loudness; where its hard cuts fall against
the beat grid (each should be one frame before a half second); and the flash check.
  python3 tools/verify.py out/locky-launch-1080p.mp4"""
import json, os, re, subprocess, sys
path = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
info = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,width,height,r_frame_rate,pix_fmt,color_space,duration,sample_rate,channels:format=duration,size",
                                  "-of", "json", path], capture_output=True, text=True).stdout)
for s in info["streams"]:
    print("stream:", {k: v for k, v in s.items()})
print("file: %.2f s, %.1f MB" % (float(info["format"]["duration"]), int(info["format"]["size"]) / 1e6))
loud = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
print("loudness:", " ".join(loud[loud.rfind("Summary:"):].split())[:150])
cuts = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-vf", "select='gt(scene,0.25)',showinfo", "-an", "-f", "null", "-"], capture_output=True, text=True).stderr
times = [float(t) for t in re.findall(r"pts_time:([0-9.]+)", cuts)]
early, on, off = [], [], []
for t in times:
    beat = round(t * 4 + 0.07) / 4            # the nearest quarter second at or just after
    d = round((beat - t) * 60)
    (early if d == 1 else on if d == 0 else off).append((round(t, 3), d))
print(f"hard cuts found: {len(times)}; one frame before a quarter second: {len(early)}; on it: {len(on)}; elsewhere: {len(off)}")
print("  on the beat frame:", [t for t, _ in on])
print("  elsewhere (frames before the next quarter second):", off)
flash = subprocess.run([sys.executable, os.path.join(here, "flash.py"), path], capture_output=True, text=True).stdout
print("flash check:", "OVER 3 in some second" if "OVER" in flash else "passes;", flash.strip().splitlines()[1].strip() if len(flash.strip().splitlines()) > 1 else "")
