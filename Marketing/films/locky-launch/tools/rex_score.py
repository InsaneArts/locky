#!/usr/bin/env python3
"""The Rex clip's sound: ten seconds of the launch film's track from its drop, and a soft sound on each move of the
wallpaper's panes (out/cues-rex.json, from `node tools/render.mjs cues --page rex`). Normalized to -14 LUFS.

  python3 tools/rex_score.py   -> out/score-rex.wav
"""
import json, os, subprocess
import numpy as np
from scipy.signal import butter, sosfilt
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 48000
PHASE = 0.024            # how far the track's beats sit after a 0.5 s grid (tools/score.py)
cues = json.load(open(os.path.join(ROOT, "out", "cues-rex.json")))
rng = np.random.default_rng(7)

raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(ROOT, "assets", "music", "b-organic.mp3"), "-f", "f32le", "-ac", "2",
                      "-ar", str(SR), "-"], capture_output=True, check=True).stdout
music = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()
n = int(cues["length"] * SR)
first = int((cues["music"] + PHASE) * SR)
bus = music[first:first + n].astype(np.float64)
bus[:int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))[:, None]


def band(x, lo, hi):
    return sosfilt(butter(2, [lo, hi], btype="band", fs=SR, output="sos"), x)


def tick(f, decay):
    m = int(0.04 * SR)
    t = np.arange(m) / SR
    return band(rng.standard_normal(m) * np.minimum(1, t / 0.0004) * np.exp(-t / decay), f * 0.6, f * 1.6) * 0.9


def swish(dur, f0, f1):
    m = int(dur * SR)
    noise, out = rng.standard_normal(m), np.zeros(m)
    for k in range(24):
        a, b = k * m // 24, (k + 1) * m // 24
        f = f0 * (f1 / f0) ** (k / 23)
        out[a:b] = band(noise, f / 1.6, min(f * 1.6, SR / 2 - 100))[a:b]
    return out * np.sin(np.pi * np.arange(m) / m) ** 1.6 * 0.35


def place(sound, at, gain):
    i = int(round(at * SR))
    m = min(len(sound), n - i)
    bus[i:i + m] += (sound[:m] * 10 ** (gain / 20))[:, None]


for at in cues["open"]:
    place(tick(2600, 0.009), at, -12)
    place(swish(0.3, 900, 4200), at, -19)
for at in cues["move"]:
    place(swish(0.4, 1200, 3000), at, -20)
for at in cues["close"]:
    place(tick(1900, 0.011), at + 0.28, -13)
fade = int(0.9 * SR)
bus[-fade:] *= (np.linspace(1, 0, fade) ** 2)[:, None]
peak = np.abs(bus).max()
if peak > 0.99:
    bus *= 0.99 / peak
tmp, out = os.path.join(ROOT, "out", "score-rex-raw.wav"), os.path.join(ROOT, "out", "score-rex.wav")
sf.write(tmp, bus.astype(np.float32), SR, subtype="FLOAT")
first_pass = subprocess.run(["ffmpeg", "-hide_banner", "-i", tmp, "-af", "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"],
                            capture_output=True, text=True).stderr
m = json.loads(first_pass[first_pass.rindex("{"):first_pass.rindex("}") + 1])
af = (f"loudnorm=I=-14:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}"
      f":measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-af", af, "-ar", str(SR), "-c:a", "pcm_s24le", out], check=True)
os.remove(tmp)
check = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", out, "-af", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
print(os.path.relpath(out), "|", " ".join(check[check.rfind("Summary:"):].split())[:110])
