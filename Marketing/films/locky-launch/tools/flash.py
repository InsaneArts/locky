#!/usr/bin/env python3
"""General-flash check after WCAG 2.3.1: relative luminance per frame for the whole frame and each of 16 tiles. A
transition is a swing of 0.10 or more against the previous extreme with the darker side under 0.80; two make a flash.
Reports the worst count in any 1 s window.   python3 tools/qa/flash.py <video>"""
import subprocess, sys
import numpy as np

path = sys.argv[1]
probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", path],
                       capture_output=True, text=True).stdout.strip().split(",")
w0, h0 = int(probe[0]), int(probe[1])
W, H = (160, 90) if w0 > h0 else (90, 160)
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", f"scale={W}:{H}:flags=area", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                     capture_output=True).stdout
frames = np.frombuffer(raw, np.uint8).reshape(-1, H, W, 3).astype(np.float32) / 255
lin = np.where(frames <= 0.04045, frames / 12.92, ((frames + 0.055) / 1.055) ** 2.4)
Y = lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722
series = {"frame": Y.mean(axis=(1, 2))}
for r in range(4):
    for c in range(4):
        series[f"tile {r},{c}"] = Y[:, r * H // 4:(r + 1) * H // 4, c * W // 4:(c + 1) * W // 4].mean(axis=(1, 2))

def transitions(v):
    """Frames where the luminance turns: a swing of 0.10 or more from the last extreme, the darker side under 0.80."""
    out, direction = [], 0
    lo = hi = ext = v[0]
    for i, x in enumerate(v[1:], 1):
        if direction == 0:
            if x - lo >= 0.10 and lo < 0.80:
                out.append(i); direction, ext = 1, x
            elif hi - x >= 0.10 and x < 0.80:
                out.append(i); direction, ext = -1, x
            lo, hi = min(lo, x), max(hi, x)
        elif direction == 1:
            if x > ext: ext = x
            elif ext - x >= 0.10 and x < 0.80:
                out.append(i); direction, ext = -1, x
        else:
            if x < ext: ext = x
            elif x - ext >= 0.10 and ext < 0.80:
                out.append(i); direction, ext = 1, x
    return out

worst = []
for name, v in series.items():
    ts = transitions(v)
    best, at = 0, 0
    for i, f in enumerate(ts):
        n = sum(1 for g in ts[i:] if g - f < 60)
        if n > best: best, at = n, f
    worst.append((best / 2, name, at / 60))
worst.sort(reverse=True)
print(f"{path.split('/')[-1]}: {len(frames)} frames")
for flashes, name, at in worst[:5]:
    print(f"  {name:10s} {flashes:4.1f} flashes in the worst second (from {at:.2f} s){'  OVER 3' if flashes > 3 else ''}")
