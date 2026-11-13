#!/usr/bin/env python3
"""Cuts the footage the film uses into frames the page can draw: build/frames/<clip>/00001.jpg, at 60 fps.

src/clips.json names each clip: its file in footage/, the part to keep (in, out, in seconds from the file's first
frame), and an optional width in pixels (default: the file's own). A clip is cut again only when its entry or its
file changed.

  python3 tools/prepare.py [clip ...]
"""
import concurrent.futures, hashlib, json, os, shutil, subprocess, sys

FILM = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLIPS = json.load(open(os.path.join(FILM, "src", "clips.json")))
FPS = 60


def cut(name):
    clip = CLIPS[name]
    source = os.path.join(FILM, "footage", clip["file"])
    out = os.path.join(FILM, "build", "frames", name)
    stamp = hashlib.sha1(json.dumps([clip, os.path.getmtime(source), os.path.getsize(source)]).encode()).hexdigest()
    meta = os.path.join(out, "meta.json")
    if os.path.exists(meta) and json.load(open(meta)).get("stamp") == stamp:
        return name, json.load(open(meta))["n"], "kept"
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    start, end = clip.get("in", 0), clip.get("out")
    # Frames keep their wall-clock times in the file: count from the first one.
    filters = ["setpts=PTS-STARTPTS", f"fps={FPS}"]
    if end is not None:
        filters.append(f"trim={start}:{end}")
    elif start:
        filters.append(f"trim=start={start}")
    filters.append("setpts=PTS-STARTPTS")
    if clip.get("width"):
        filters.append(f"scale={clip['width']}:-2:flags=lanczos")
    source_args = ["-i", source] if not clip.get("still") else ["-loop", "1", "-t", "0.02", "-i", source]
    subprocess.run(["ffmpeg", "-v", "error", "-y", *source_args, "-vf", ",".join(filters), "-q:v", "2", "-pix_fmt", "yuvj420p",
                    os.path.join(out, "%05d.jpg")], check=True)
    n = len([f for f in os.listdir(out) if f.endswith(".jpg")])
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                            "-of", "csv=p=0", os.path.join(out, "00001.jpg")], capture_output=True, text=True).stdout.strip().split(",")
    info = {"stamp": stamp, "n": n, "w": int(probe[0]), "h": int(probe[1])}
    json.dump(info, open(meta, "w"))
    return name, n, "cut"


names = sys.argv[1:] or list(CLIPS)
with concurrent.futures.ThreadPoolExecutor(6) as pool:
    for name, n, what in pool.map(cut, names):
        print(f"{name}: {n} frames, {what}")

# What the page reads: each clip's frame count and size.
index = {}
# Every folder of frames, also those other tools made (the lapse).
for name in sorted(os.listdir(os.path.join(FILM, "build", "frames"))):
    meta = os.path.join(FILM, "build", "frames", name, "meta.json")
    if os.path.exists(meta):
        m = json.load(open(meta))
        index[name] = {"n": m["n"], "w": m["w"], "h": m["h"]}
json.dump(index, open(os.path.join(FILM, "build", "frames", "index.json"), "w"), indent=1)
