#!/usr/bin/env python3
"""The Rex clip's sound: the launch film's track from its drop, and two soft notes when the lock screen first shows a
program that needs the user (out/cues-rex.json, from `node tools/render.mjs cues --page rex`). Normalized to -14 LUFS.

  python3 tools/rex_score.py   -> out/score-rex.wav
"""
import json, os, subprocess
import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 48000
PHASE = 0.024            # how far the track's beats sit after a 0.5 s grid (tools/score.py)
cues = json.load(open(os.path.join(ROOT, "out", "cues-rex.json")))

raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(ROOT, "assets", "music", "b-organic.mp3"), "-f", "f32le", "-ac", "2",
                      "-ar", str(SR), "-"], capture_output=True, check=True).stdout
music = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()
n = int(cues["length"] * SR)
first = int((cues["music"] + PHASE) * SR)
bus = music[first:first + n].astype(np.float64)
bus[:int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))[:, None]


def bell(f, dur=2.4):
    """A soft struck note: one sine bent by another that dies away fast."""
    m = int(dur * SR)
    t = np.arange(m) / SR
    bend = 1.6 * np.exp(-t / 0.5) * np.sin(2 * np.pi * f * 3.5 * t)
    return np.sin(2 * np.pi * f * t + bend) * np.minimum(1, t / 0.003) * np.exp(-t / 0.9) * 0.35


def place(sound, at, gain):
    i = int(round(at * SR))
    m = min(len(sound), n - i)
    bus[i:i + m] += (sound[:m] * 10 ** (gain / 20))[:, None]


# Two notes, a fourth apart, in the track's key.
place(bell(587.33), cues["needs"], -13)
place(bell(783.99), cues["needs"] + 0.14, -15)
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
