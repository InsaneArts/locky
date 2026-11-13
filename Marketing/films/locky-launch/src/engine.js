// The film's mechanics: a canvas, a frame cache, and drawing helpers. Nothing here knows the film's shots.
// Every frame is drawn from its time alone: seek(t) draws, finds which pictures it lacks, loads them, and draws again.

export const W = 1920, H = 1080, FPS = 60;
const q = new URLSearchParams(location.search);
export const SCALE = Number(q.get("scale") || 1);
export const GUIDES = q.get("guides") === "1";

export const canvas = document.getElementById("c");
canvas.width = W * SCALE;
canvas.height = H * SCALE;
export const ctx = canvas.getContext("2d", { alpha: false });

// MARK: Math

export const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const lerp = (a, b, p) => a + (b - a) * p;
/** Progress 0 to 1 of a span that starts at `start` and lasts `dur` seconds. */
export const span = (t, start, dur) => clamp((t - start) / dur);
export const ease = {
  linear: (p) => p,
  inCubic: (p) => p ** 3,
  outCubic: (p) => 1 - (1 - p) ** 3,
  inOutCubic: (p) => (p < 0.5 ? 4 * p ** 3 : 1 - (-2 * p + 2) ** 3 / 2),
  inOutQuint: (p) => (p < 0.5 ? 16 * p ** 5 : 1 - (-2 * p + 2) ** 5 / 2),
  outExpo: (p) => (p >= 1 ? 1 : 1 - 2 ** (-10 * p)),
  inExpo: (p) => (p <= 0 ? 0 : 2 ** (10 * p - 10)),
  outQuart: (p) => 1 - (1 - p) ** 4,
};
/** A spring from 0 to 1, `t` seconds after it starts, in closed form: no state between frames. */
export function spring(t, { freq = 1.5, damping = 0.82 } = {}) {
  if (t <= 0) return 0;
  const w = 2 * Math.PI * freq;
  if (damping >= 1) return 1 - (1 + w * t) * Math.exp(-w * t);
  const wd = w * Math.sqrt(1 - damping * damping);
  return 1 - Math.exp(-damping * w * t) * (Math.cos(wd * t) + ((damping * w) / wd) * Math.sin(wd * t));
}
export function rng(seed = 1) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let r = Math.imul(a ^ (a >>> 15), 1 | a);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

// MARK: Pictures

const index = await (await fetch("/build/frames/index.json")).json();
const cache = new Map();      // url → ImageBitmap, most recently used last
const CACHE = 28;
let missing = new Set();

/** The picture at `url`, or null when it is not loaded yet (seek loads it and draws again). */
export function picture(url) {
  const hit = cache.get(url);
  if (hit) {
    cache.delete(url);
    cache.set(url, hit);
    return hit;
  }
  missing.add(url);
  return null;
}

/** The frame of `clip` at `t` seconds into it. Past its end, its last frame. */
export function frame(clip, t) {
  const info = index[clip];
  if (!info) throw new Error(`no clip named ${clip}: run tools/prepare.py`);
  const i = clamp(Math.floor(t * FPS + 1e-6) + 1, 1, info.n);
  return picture(`/build/frames/${clip}/${String(i).padStart(5, "0")}.jpg`);
}
export const clipLength = (clip) => index[clip].n / FPS;
export const clipSize = (clip) => index[clip];

async function load(url) {
  const blob = await (await fetch(url)).blob();
  cache.set(url, await createImageBitmap(blob));
}

let drawFilm = () => {};
export function setDraw(f) { drawFilm = f; }

window.seek = async (t) => {
  for (let pass = 0; pass < 6; pass++) {
    missing = new Set();
    ctx.setTransform(SCALE, 0, 0, SCALE, 0, 0);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = "source-over";
    ctx.filter = "none";
    drawFilm(t);
    if (!missing.size) break;
    await Promise.all([...missing].map(load));
  }
  // Old frames go only after the draw, so a frame never loses a picture it just loaded.
  while (cache.size > CACHE) {
    const [url, bitmap] = cache.entries().next().value;
    bitmap.close();
    cache.delete(url);
  }
};

window.renderRange = async (lo, hi, fps) => {
  for (let i = lo; i < hi; i++) {
    await window.seek(i / fps);
    const blob = await new Promise((r) => canvas.toBlob(r, "image/jpeg", 0.97));
    await fetch(`/put?i=${i}`, { method: "POST", body: blob });
  }
};

// MARK: Drawing

/** Draws a picture so that it covers `rect` (default: the frame), scaled by `zoom` around the point (ox, oy) of the
    picture, given as fractions. `at` is where that point lands in the rect, as fractions (default: the same place). */
export function cover(img, { rect = [0, 0, W, H], zoom = 1, ox = 0.5, oy = 0.5, at, alpha = 1 } = {}) {
  if (!img) return;
  const [x, y, w, h] = rect;
  const fill = Math.max(w / img.width, h / img.height) * zoom;
  const dw = img.width * fill, dh = img.height * fill;
  const [ax, ay] = at ?? [ox, oy];
  ctx.save();
  ctx.globalAlpha *= alpha;
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(img, x + ax * w - ox * dw, y + ay * h - oy * dh, dw, dh);
  ctx.restore();
}

export function roundRect(x, y, w, h, r) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}

/** Runs `draw` clipped to a rounded rectangle. */
export function clipped(x, y, w, h, r, draw) {
  ctx.save();
  roundRect(x, y, w, h, r);
  ctx.clip();
  draw();
  ctx.restore();
}

// Film grain, against banding in dark gradients: one noise tile, moved each frame.
const grainTile = (() => {
  const c = new OffscreenCanvas(512, 512), g = c.getContext("2d"), d = g.createImageData(512, 512), r = rng(11);
  for (let i = 0; i < d.data.length; i += 4) {
    const v = 128 + (r() + r() + r() - 1.5) * 90;
    d.data[i] = d.data[i + 1] = d.data[i + 2] = v;
    d.data[i + 3] = 255;
  }
  g.putImageData(d, 0, 0);
  return c;
})();
export function grain(t, amount = 0.05) {
  const r = rng(Math.floor(t * FPS) + 3);
  ctx.save();
  ctx.globalAlpha = amount;
  ctx.globalCompositeOperation = "overlay";
  ctx.translate(-Math.floor(r() * 512), -Math.floor(r() * 512));
  ctx.fillStyle = ctx.createPattern(grainTile, "repeat");
  ctx.fillRect(0, 0, W + 512, H + 512);
  ctx.restore();
}

// MARK: Type

for (const [family, file, weight] of [["SF Pro Display", "SF-Pro-Display-Semibold.otf", 600], ["SF Pro Display", "SF-Pro-Display-Medium.otf", 500],
  ["SF Pro Display", "SF-Pro-Display-Bold.otf", 700], ["SF Mono", "SF-Mono-Medium.otf", 500], ["SF Mono", "SF-Mono-Regular.otf", 400]]) {
  const face = new FontFace(family, `url(${family === "SF Mono" ? "/assets/fonts" : "/fonts"}/${file})`, { weight: String(weight) });
  try { document.fonts.add(await face.load()); } catch { console.warn("font missing:", file); }
}
await document.fonts.ready;

export function setFont(size, { weight = 600, family = "SF Pro Display", tracking = -0.02 } = {}) {
  ctx.font = `${weight} ${size}px "${family}"`;
  ctx.letterSpacing = `${size * tracking}px`;
}
