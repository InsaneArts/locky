#!/usr/bin/env python3
"""The film's soundtrack: the ElevenLabs track under the whole film, and quiet UI sounds, each on a cue the film page
exports (out/cues.json, from `node tools/render.mjs cues`). Normalized to -14 LUFS.

  python3 tools/score.py [assets/music/b-organic.mp3]   -> out/score.wav
"""
import json, os, subprocess, sys
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 48000
MUSIC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "music", "b-organic.mp3")
# How far the track's beats sit after a 0.5 s grid: the film's beats are on the grid. analyse.py's "grid phase" says
# 0.045 s; measured on the finished film at 1 ms, the groove's hits were then 21 ms early, so 0.024 s.
PHASE = 0.024
cues = json.load(open(os.path.join(ROOT, "out", "cues.json")))
LENGTH = cues["length"]
rng = np.random.default_rng(7)


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()


def db(x):
    return 10 ** (x / 20)


def place(bus, sound, at, gain=0.0, pan=0.0):
    """Adds a mono or stereo sound at `at` seconds, with gain in dB and an equal-power pan from -1 to 1."""
    if sound.ndim == 1:
        a = np.pi / 4 * (pan + 1)
        sound = np.stack([sound * np.cos(a), sound * np.sin(a)], axis=1)
    i = int(round(at * SR))
    if i >= len(bus) or i < 0:
        return
    n = min(len(sound), len(bus) - i)
    bus[i:i + n] += sound[:n] * db(gain)


def env(n, attack, decay):
    t = np.arange(n) / SR
    return np.minimum(1, t / max(attack, 1e-4)) * np.exp(-t / decay)


def band(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def low(x, f, order=2):
    return sosfilt(butter(order, f, btype="low", fs=SR, output="sos"), x)


# MARK: Sounds

def swish(dur, f0, f1, q=1.6):
    """Air moving: noise through a band that sweeps from f0 to f1."""
    n = int(dur * SR)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    steps = 24
    for k in range(steps):
        a, b = k * n // steps, (k + 1) * n // steps
        f = f0 * (f1 / f0) ** (k / (steps - 1))
        out[a:b] = band(noise, f / q, min(f * q, SR / 2 - 100))[a:b]
    t = np.arange(n) / SR
    return out * np.sin(np.pi * np.minimum(1, t / dur)) ** 1.6 * 0.35


def tick(f=3200, decay=0.006):
    n = int(0.03 * SR)
    return band(rng.standard_normal(n) * env(n, 0.0004, decay), f * 0.6, f * 1.6) * 0.9


def thock(f=170):
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.03)
    click = low(rng.standard_normal(n), 2400) * env(n, 0.0005, 0.008)
    return (body * 0.8 + click * 0.9) * 0.8


def pop(f):
    n = int(0.16 * SR)
    t = np.arange(n) / SR
    freq = f * (1 + 0.5 * np.exp(-t / 0.012))
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * env(n, 0.002, 0.045) * 0.6


def thump(f=58, dur=0.5):
    """A soft low hit: the lock closing."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    freq = f * (1 + 1.2 * np.exp(-t / 0.03))
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * env(n, 0.003, 0.14) * 0.9


def bell(f, dur=3.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    mod = 1.6 * np.exp(-t / 0.5) * np.sin(2 * np.pi * f * 3.5 * t)
    return np.sin(2 * np.pi * f * t + mod) * env(n, 0.003, 1.1) * 0.35


def reverb(x, seconds=1.4, wet=0.22):
    n = int(seconds * SR)
    ir = rng.standard_normal((n, 2)) * np.exp(-np.arange(n) / SR / (seconds / 6.9))[:, None]
    ir = low(ir.T, 5200).T
    ir /= np.sqrt((ir ** 2).sum(axis=0))
    out = np.stack([fftconvolve(x[:, c], ir[:, c])[:len(x)] for c in range(2)], axis=1)
    return x * (1 - wet) + out * wet


# MARK: The mix

music = decode(MUSIC)
bus = np.zeros((int(LENGTH * SR), 2))
sfx = np.zeros_like(bus)

# The track from its first beat: the film's beats are its beats.
skip = int(PHASE * SR)
start = music[skip:].copy()
start[:int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))[:, None]      # no click on the first sample
place(bus, start, 0.0)

# The hook: the quiet opening has one soft knock on each cut.
for at in cues["cuts"]:
    place(sfx, thock(120), at, gain=-13)
    place(sfx, swish(0.3, 900, 3600), at - 0.05, gain=-23)
# The run: a click and a breath of air on each lock screen.
for i, at in enumerate(cues["run"]):
    place(sfx, tick(2400, 0.009), at, gain=-14, pan=0.25 if i % 2 == 0 else -0.25)
    place(sfx, swish(0.22, 1800, 6500), at, gain=-22)
# The app: the camera steps back, and the list ticks.
place(sfx, swish(0.7, 3200, 500), cues["stepBack"], gain=-16)
for at in cues["list"]:
    place(sfx, tick(3400), at, gain=-15)
# The lock's animations: air in, and a soft low hit as each closes.
for at in cues["ways"] + [cues["lock"]]:
    place(sfx, swish(0.6, 500, 5200), at, gain=-15)
    place(sfx, thump(), at + 0.38, gain=-11 if at == cues["lock"] else -14)
# Live wallpapers: only air.
for at in cues["live"]:
    place(sfx, swish(0.5, 700, 2600), at - 0.1, gain=-24)
# The day runs: a long rise, and a bell at night.
rise = swish(2.5, 300, 4200) * np.linspace(0.25, 1, int(2.5 * SR)) ** 1.5
place(sfx, rise, cues["lapse"][0], gain=-17)
place(sfx, bell(880, 2.4), cues["lapse"][1], gain=-21)
# The windows: pops for what opens, ticks for clicks, air for drags.
place(sfx, pop(830.6), cues["popover"], gain=-15)
place(sfx, tick(2600, 0.008), cues["editor"], gain=-13)
for at in cues["drags"]:
    place(sfx, swish(0.6, 900, 3000), at, gain=-20)
place(sfx, pop(698.5), cues["sheet"], gain=-15)
for at in cues["sizes"]:
    place(sfx, tick(3000, 0.007), at, gain=-13)
place(sfx, pop(1046.5), cues["add"], gain=-14)
for i, at in enumerate(cues["skies"]):
    place(sfx, tick(2500, 0.009), at, gain=-13, pan=0.2)
    place(sfx, swish(0.3, 1500, 6000), at, gain=-20)
for at in cues["states"]:
    place(sfx, tick(2800, 0.008), at, gain=-14)
place(sfx, swish(0.55, 4200, 900), cues["panel"], gain=-17)
for at, f in zip(cues["agent"], [698.5, 830.6, 1046.5]):
    place(sfx, pop(f), at, gain=-15)
# The password: a key for each dot.
for i, at in enumerate(cues["keys"]):
    place(sfx, thock(150 + 12 * (i % 3)) * 0.7, at, gain=-13, pan=float(rng.uniform(-0.15, 0.15)))
# The end card: one bell as the icon arrives.
place(sfx, bell(698.5), cues["icon"], gain=-16)
place(sfx, bell(1046.5) * 0.6, cues["icon"] + 0.012, gain=-20, pan=0.2)

bus += reverb(sfx)
# The picture ends at 64 s: a short fade, so the sound stops with it.
fade = int(0.6 * SR)
bus[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
peak = np.abs(bus).max()
if peak > 0.99:
    bus *= 0.99 / peak
tmp = os.path.join(ROOT, "out", "score-raw.wav")
out = os.path.join(ROOT, "out", "score.wav")
sf.write(tmp, bus.astype(np.float32), SR, subtype="FLOAT")

# Two-pass loudness normalization: -14 LUFS integrated, true peak under -1.5 dBTP.
first = subprocess.run(["ffmpeg", "-hide_banner", "-i", tmp, "-af", "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
m = json.loads(first[first.rindex("{"):first.rindex("}") + 1])
af = (f"loudnorm=I=-14:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}"
      f":measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-af", af, "-ar", str(SR), "-c:a", "pcm_s24le", out], check=True)
os.remove(tmp)
check = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", out, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
print(os.path.relpath(out), "|", " ".join(check[check.rfind("Summary:"):].split()))
