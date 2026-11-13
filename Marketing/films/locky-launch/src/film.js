// The Locky launch film: 64 s at 120 BPM. Every frame is a function of its time. shotlist.md is the plan.
// The sections follow the score (assets/music/b-organic.mp3): quiet 0-8, groove 8-24, breakdown 24-36, build 36-40,
// groove 40-60, last chord 60-64.
import { W, H, FPS, GUIDES, ctx, clamp, lerp, span, ease, spring, frame, picture, cover, grain, setFont, setDraw } from "/src/engine.js";

const BEAT = 0.5;
// A cut shows one frame before its beat, so the new picture is on screen when the kick lands.
const EARLY = 1 / FPS;
export const DURATION = 64;

const EVENTS = await (await fetch("/src/events.json")).json();
const TRANSITIONS = await (await fetch("/src/transitions.json")).json();
/** When a recorded click or drag happened, in its clip's time, by the note the session gave it. */
/** With `answered`, when the app's picture changed for it instead (0.17 s after, where the change is too small to measure). */
function at(clip, note, nth = 0, answered = false) {
  const e = EVENTS[clip].filter((e) => e.note === note && (e.kind === "click" || e.kind === "drag"))[nth];
  return answered ? e.seen ?? e.t + 0.17 : e.t;
}
const keyAt = (clip, key, nth = 0) => EVENTS[clip].filter((e) => e.kind === "key" && e.keys[0] === key)[nth].t;

// MARK: Words

const INK = { light: "255,255,255", dark: "20,20,20" };

/** One line, bottom left. It rises in word by word and fades out. `start: null` means it is there from frame 0. */
function line(t, text, { start, end, x = 116, y = 906, size = 68, ink = "light", tone = 1, scrim = 0.3, weight = 600 }) {
  const from = start ?? -10;
  if (t < from || t > end + 0.16) return;
  const out = 1 - ease.inCubic(span(t, end, 0.16));
  setFont(size, { weight, tracking: -0.012 });
  const words = text.split(" ");
  const space = ctx.measureText(" ").width;
  const width = ctx.measureText(text).width;
  ctx.save();
  if (ink === "light" && scrim > 0) {
    // A soft dark patch under the words only, so a bright sky does not take them.
    const shown = ease.outCubic(span(t, from, 0.3)) * out;
    const cx = x + width / 2, cy = y - size * 0.34;
    ctx.save();
    ctx.translate(cx, cy);
    ctx.scale(1, (size * 2.3) / (width * 0.78));
    const g = ctx.createRadialGradient(0, 0, 0, 0, 0, width * 0.78);
    g.addColorStop(0, `rgba(0,0,0,${scrim * shown})`);
    g.addColorStop(0.55, `rgba(0,0,0,${scrim * 0.55 * shown})`);
    g.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = g;
    ctx.fillRect(-width, -width, width * 2, width * 2);
    ctx.restore();
    ctx.shadowColor = "rgba(0,0,0,0.5)";
    ctx.shadowBlur = 26;
    ctx.shadowOffsetY = 2;
  }
  let cx = x;
  words.forEach((word, i) => {
    const p = start === null ? 1 : ease.outExpo(clamp((t - from - i * 0.05) / 0.36));
    ctx.fillStyle = `rgba(${INK[ink]},${p * out * tone})`;
    ctx.fillText(word, cx, y + (1 - p) * 16);
    cx += ctx.measureText(word).width + space;
  });
  ctx.restore();
}

/** Two lines: the second quieter. */
function lines(t, first, second, { start, end, ink = "light", x = 116, y = 906, scrim = 0.3 }) {
  line(t, first, { start, end, ink, x, y: y - 80, scrim });
  line(t, second, { start: start + 0.22, end, ink, x, y, tone: 0.6, scrim });
}

/** A small label in mono capitals: the film's quiet second voice. */
function label(t, text, { start, end, x = 119, y = 742, ink = "light", align = "left", size = 27, tone = 1, full = false }) {
  if (t < start || t > end + 0.16) return;
  const a = ease.outCubic(span(t, start, 0.3)) * (1 - span(t, end, 0.16)) * tone;
  setFont(size, { family: "SF Mono", weight: 500, tracking: 0.08 });
  ctx.save();
  ctx.textAlign = align;
  if (full && ink === "light") {
    // A theme's name has to read over a neon grid: a soft dark patch under it, as under a line.
    const width = ctx.measureText(text.toUpperCase()).width;
    ctx.save();
    ctx.translate(x + width / 2, y - size * 0.36);
    ctx.scale(1, (size * 1.5) / (width * 0.8));
    const g = ctx.createRadialGradient(0, 0, 0, 0, 0, width * 0.8);
    g.addColorStop(0, `rgba(0,0,0,${0.42 * a})`);
    g.addColorStop(0.6, `rgba(0,0,0,${0.24 * a})`);
    g.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = g;
    ctx.fillRect(-width, -width, width * 2, width * 2);
    ctx.restore();
  }
  ctx.fillStyle = `rgba(${INK[ink]},${(full ? 1 : 0.78) * a})`;
  if (ink === "light") { ctx.shadowColor = `rgba(0,0,0,${full ? 0.8 : 0.6})`; ctx.shadowBlur = 14; }
  ctx.fillText(text.toUpperCase(), x, y);
  ctx.restore();
}

const icon = () => picture("/assets/icon.png");

/** The app's icon, its tile `size` wide, with its left edge at x and its bottom at y. */
function drawIcon(x, y, size, alpha) {
  const img = icon();
  if (!img || alpha <= 0) return;
  // The icon file has a clear margin around the tile (about 10% a side).
  const full = size / 0.8, pad = (full - size) / 2;
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.shadowColor = "rgba(0,0,0,0.35)";
  ctx.shadowBlur = 24;
  ctx.shadowOffsetY = 6;
  ctx.drawImage(img, x - pad, y - size - pad, full, full);
  // A hairline, so the icon's dark lower third keeps its shape on a dark picture.
  ctx.shadowColor = "transparent";
  ctx.beginPath();
  ctx.roundRect(x + 0.5, y - size + 0.5, size - 1, size - 1, size * 0.225);
  ctx.strokeStyle = "rgba(255,255,255,0.16)";
  ctx.lineWidth = 1;
  ctx.stroke();
  ctx.restore();
}

/** A line with the app's icon before it: the name, early. */
function named(t, words, { start, end, ink }) {
  const a = ease.outExpo(span(t, start, 0.36)) * (1 - ease.inCubic(span(t, end, 0.16)));
  drawIcon(116, 906 + 14 + (1 - a) * 16, 84, a);
  line(t, words, { start, end, ink, x: 116 + 106 });
}

// MARK: Lock screens

/** A live lock screen, full frame. The footage is the preview window's content: 1.02 hides its rounded corners. */
function lock(clip, tClip, { zoom = 1.02, ox = 0.5, oy = 0.5, alpha = 1 } = {}) {
  cover(frame(clip, tClip), { zoom, ox, oy, alpha });
}

/** A held shot: the lock screen pushes in slowly over `dur`. */
function held(clip, local, dur, { from = 1.02, to = 1.06, ox = 0.5, oy = 0.5, offset = 0.4 } = {}) {
  lock(clip, offset + local, { zoom: lerp(from, to, local / dur), ox, oy });
}

// MARK: The app's window

const WIN = { w: 1760, h: 990 };

/** A recorded window: the Themes window (1760 x 990 points) unless `size` says another. The camera looks at (fx, fy),
    in window points; zoom 1 fits the window's width. Returns the camera, for what is drawn in the window's own points. */
function win(clip, tClip, { zoom = 1, fx, fy, alpha = 1, size = WIN } = {}) {
  const k = (W / size.w) * zoom;
  // The camera never looks past the window's edge.
  const halfW = W / 2 / k, halfH = H / 2 / k;
  fx = clamp(fx ?? size.w / 2, halfW, size.w - halfW);
  fy = clamp(fy ?? size.h / 2, halfH, size.h - halfH);
  const img = frame(clip, tClip);
  if (img) {
    ctx.save();
    ctx.globalAlpha *= alpha;
    ctx.imageSmoothingQuality = "high";
    // The whole window shows with its own round corners: what is outside them in the footage (the desktop) is cut.
    ctx.beginPath();
    ctx.roundRect(W / 2 - fx * k, H / 2 - fy * k, size.w * k, size.h * k, 28 * k);
    ctx.clip();
    ctx.drawImage(img, W / 2 - fx * k, H / 2 - fy * k, size.w * k, size.h * k);
    ctx.restore();
  }
  return { k, fx, fy };
}
const toScreen = (cam, x, y) => [W / 2 + (x - cam.fx) * cam.k, H / 2 + (y - cam.fy) * cam.k];

/** The clip's time for a film time: straight lines between [film, clip] points. Two points at one film time are a cut. */
function remap(t, points) {
  let i = 0;
  // Frames sit at whole sixtieths: a hair is added, so a point one frame before a beat takes that frame.
  while (i + 1 < points.length && points[i + 1][0] <= t + 1e-6) i++;
  const [f0, c0] = points[i], next = points[i + 1];
  if (!next || next[0] === f0) return c0 + (t - f0);
  return c0 + ((t - f0) / (next[0] - f0)) * (next[1] - c0);
}

/** Where the pointer is at a clip's time: it glides to each click before it lands, and holds through a drag. */
function pointerAt(events, tc) {
  let pos = null, press = 0;
  const pts = events.filter((e) => e.kind === "click" || e.kind === "drag");
  for (let i = 0; i < pts.length; i++) {
    const e = pts[i], prev = pts[i - 1];
    const rest = prev ? (prev.kind === "drag" ? [prev.x1, prev.y1] : [prev.x, prev.y]) : [e.x + 140, e.y + 110];
    const restAt = prev ? (prev.kind === "drag" ? prev.t + 0.72 : prev.t) : -1;
    const leave = Math.max(restAt + 0.08, e.t - 0.5), arrive = e.t - 0.05;
    if (tc < leave) { pos ??= rest; break; }
    const p = ease.inOutCubic(clamp((tc - leave) / Math.max(arrive - leave, 0.01)));
    pos = [lerp(rest[0], e.x, p), lerp(rest[1], e.y, p)];
    press = 0;
    if (e.kind === "drag") {
      // The helper drags at an even speed for about 0.62 s.
      const d = clamp((tc - e.t - 0.04) / 0.6);
      pos = [lerp(pos[0], e.x1, d), lerp(pos[1], e.y1, d)];
      if (tc >= e.t && tc <= e.t + 0.7) press = 1;
    } else if (tc >= e.t - 0.02) {
      press = 1 - clamp((tc - e.t) / 0.3);
    }
  }
  return pos && { x: pos[0], y: pos[1], press };
}

/** The pointer: the Mac's arrow, drawn by the film at the place the recorded click or drag had. */
function pointer(clip, tc, cam, alpha = 1) {
  const p = pointerAt(EVENTS[clip], tc);
  if (!p || alpha <= 0) return;
  const [sx, sy] = toScreen(cam, p.x, p.y);
  const s = 1.9 * (1 - 0.1 * p.press);
  ctx.save();
  ctx.globalAlpha = alpha;
  if (p.press > 0 && p.press < 1) {
    // A click shows as a ring that opens and fades.
    ctx.beginPath();
    ctx.arc(sx, sy, 10 + (1 - p.press) * 26, 0, Math.PI * 2);
    ctx.strokeStyle = `rgba(255,255,255,${0.75 * p.press})`;
    ctx.lineWidth = 2.5;
    ctx.stroke();
  }
  ctx.translate(sx, sy);
  ctx.scale(s, s);
  ctx.shadowColor = "rgba(0,0,0,0.45)";
  ctx.shadowBlur = 5;
  ctx.shadowOffsetY = 1.5;
  ctx.beginPath();
  for (const [i, [x, y]] of [[0, 0], [0, 16.6], [4.3, 12.9], [7.1, 19.6], [9.7, 18.5], [6.9, 11.9], [12.3, 11.9]].entries()) i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
  ctx.closePath();
  ctx.fillStyle = "#0a0a0a";
  ctx.fill();
  ctx.shadowColor = "transparent";
  ctx.lineJoin = "round";
  ctx.lineWidth = 1.3;
  ctx.strokeStyle = "#fff";
  ctx.stroke();
  ctx.restore();
}

// MARK: A. The hook (0 to 8): six held lock screens, each with its name, in the score's quiet opening

// Frames sit at whole sixtieths, and a sum such as 8.4833 + 0.0167 can fall a hair under 8.5: the hair is added back.
const EPS = 1e-6;
/** Which of a run of equal shots a time is in: each starts one frame before its beat. */
const shot = (t, start, each, count) => clamp(Math.floor((t - start + EARLY + EPS) / each), 0, count - 1);

// The six best looking of the 43, first. Two hold a bar, then four hold half a bar: the cuts quicken into the drop.
const HOOK = [["sakura", "Sakura", 0], ["synthwave", "Synthwave", 2], ["tokyonight", "Tokyo Night", 4], ["gruvbox", "Gruvbox", 5],
              ["neoncity", "Neon City", 6], ["mocha", "Mocha", 7]];
// A line holds over a cut. Gruvbox has a quote where the line sits, so no line shows over it, and Tokyo Night has
// its password field beside the line, so its line is the short one.
const HOOK_LINES = [["This is a lock screen.", null, 1.8], ["So is this.", 2.04, 3.8], ["And this.", 4.04, 4.82],
                    ["Your Mac came with one.", 6.04, 7.8]];
const NAME = { y: 818, size: 30, full: true };

function hook(t) {
  const k = HOOK.findLastIndex(([, , at]) => t >= at - EARLY - EPS);
  const [clip, name, at] = HOOK[k];
  const dur = (HOOK[k + 1]?.[2] ?? 8) - at;
  held(clip, t + EARLY - at, dur, { from: 1.02, to: 1.02 + 0.0175 * dur });
  // The name is part of the shot: it is there from the cut's first frame.
  label(t, name, { start: at - 1, end: 8, ...NAME });
  for (const [words, start, end] of HOOK_LINES) line(t, words, { start, end });
}

// MARK: B. The run (8 to 11.5): the score's drop, one lock screen a beat, dark to light

const RUN = [["eventhorizon", "Event Horizon", "light"], ["matrix", "Matrix", "light"], ["liquid", "Liquid", "light"],
             ["vaporwave", "Vaporwave", "light"], ["poster", "Poster", "dark"], ["notebook", "Notebook", "dark"], ["pocket", "Pocket", "dark"]];

function run(t) {
  const k = shot(t, 8, BEAT, RUN.length);
  const local = t - (8 - EARLY) - k * BEAT;
  const [clip, name, ink] = RUN[k];
  // Each cut lands a little large and settles: the run has a pulse.
  lock(clip, 0.5 + local, { zoom: 1.02 + 0.035 * (1 - ease.outExpo(clamp(local / 0.42))) });
  label(t, name, { start: 7, end: 12, ink, ...NAME });
  named(t, "Locky has 43.", { start: 8.0, end: 11.3, ink });
}

// MARK: B2. The app (11.5 to 18): the run's last picture is the Themes window's own preview; the camera steps back

// One move down the list a beat, from 13.0. A theme's still picture shows before its live screen, for a tenth of a
// second or for most of one: the film cuts that wait out (the walk was shot at a second a step). Dot Matrix, the
// seventh move, did not draw its live screen within its second, so the film cuts that step out: the count goes
// from 08 to 10. The walk stops on Galaxy Sea, a bar before the lock comes in over it.
const WALK = [0, 1, 2, 3, 4, 5, 7, 8, 9];
const BROWSE = [[11.5, EVENTS.browseSelected[0] - 1.5], [13 - EARLY, EVENTS.browseSelected[0] - 0.02]];
WALK.forEach((step, j) => {
  const beat = 13 + j * BEAT;
  BROWSE.push([beat - EARLY, EVENTS.browseLive[step] + 0.02]);
  // Each move plays until just before the next key of the take, in the time to the film's next beat.
  BROWSE.push([(j + 1 < WALK.length ? beat + BEAT : 18) - EARLY, EVENTS.browseSelected[step + 1] - 0.04]);
});
const PREVIEW = { x: 1005, y: 346, zoom: 1.99 };       // the preview fills the frame

function app(t) {
  const back = spring(t - 12.0, { freq: 1.25, damping: 0.86 });
  const punch = t < 12 ? 0.035 * (1 - ease.outExpo(clamp((t - 11.5 + EARLY) / 0.42))) : 0;
  const cam = win("browse", remap(t, BROWSE), {
    zoom: lerp(PREVIEW.zoom, 1, back) + punch, fx: lerp(PREVIEW.x, 880, back), fy: lerp(PREVIEW.y, 495, back),
  });
  // Which of the 43, as the list moves.
  // Bauhaus is the list's second theme, and the walk's first move goes to its third.
  const k = t < 13 - EARLY - EPS ? 0 : WALK[shot(t, 13, BEAT, WALK.length)] + 1;
  const [lx, ly] = toScreen(cam, 555, 850);
  // Bauhaus and Braun are light pages. A page's color fades over in a quarter second: the words turn with it.
  const turn = (beat) => ease.inOutCubic(span(t, beat + 0.04, 0.16));
  const dark = 1 - turn(13) + turn(13.5) - turn(14);
  for (const [ink, tone] of [["light", 1 - dark], ["dark", dark]]) {
    if (tone <= 0.01) continue;
    label(t, `${String(k + 2).padStart(2, "0")} / 43`, { start: 12.7, end: 17.8, x: lx + 3, y: ly, ink, size: 30, tone });
    line(t, "Pick one.", { start: 12.75, end: 17.8, x: lx, y: ly + 88, ink, scrim: 0, tone });
  }
}

// MARK: S. Lock it your way (18 to 24): the lock's own animation, three styles, each over the app

// The first comes in over the walk's last theme, on the bar. The others cut to their page an eighth note before.
const WAYS = [["waytiles", "Tiles", "light", 18], ["waysweep", "Sweep", "light", 19.75], ["waydissolve", "Dissolve", "dark", 21.75]];

function ways(t) {
  const k = t < WAYS[1][3] - EARLY - EPS ? 0 : t < WAYS[2][3] - EARLY - EPS ? 1 : 2;
  const [clip, name, ink] = WAYS[k];
  const bar = 18 + k * 2;
  // The way in starts on the bar: the recorded take plays from there at its own speed.
  lock(clip, TRANSITIONS[clip].desk_to / FPS + (t - bar), { zoom: 1.02 });
  // The second take says what the Mac's own lock button does with Settings › General's switch on. On Braun the label
  // sits lower, clear of the clock, and has no line: Braun has its own things where a line sits.
  const about = k === 1 ? "Settings  ·  Lock with the Touch ID button" : `${name}  ·  one of 7 lock animations`;
  label(t, about, { start: bar + 0.6, end: bar + (k === 2 ? 1.85 : 1.7), ink, y: k === 2 ? 800 : 742 });
  if (k === 0) line(t, "Lock it your way.", { start: bar + 0.6, end: bar + 1.6, ink });
  if (k === 1) line(t, "The Touch ID button locks with Locky.", { start: bar + 0.6, end: bar + 1.7, ink, scrim: 0.4 });
}

// MARK: C. A live wallpaper (24 to 26): the score's breakdown

function live(t) {
  held("snowfall", t - (24 - EARLY), 2, { from: 1.02, to: 1.07, ox: 0.5, oy: 0.55 });
  lines(t, "Live wallpapers,", "drawn in Metal.", { start: 24.3, end: 25.8, scrim: 0.42 });
}

// MARK: D. Time (26 to 32): Lookout through the day, and the schedule

const LAPSE = { from: 10.5, to: 22.75, n: 360 };

const DAY = 26, PLAN = 30;      // when the day starts to run, and when the schedule shows

function lapse(t) {
  const hour = lerp(10.6, 22.6, ease.inOutCubic(span(t, DAY + 1.3, 2.45)));
  const zoom = lerp(1.02, 1.075, span(t, DAY, 4));
  const fade = span(t, DAY + 1.0, 0.5);
  if (fade < 1) lock("lookout", 0.4 + (t - DAY), { zoom });
  if (fade > 0) {
    // The widgets go, as they do after 20 s without input, and the scene's hour runs.
    const i = Math.round(((hour - LAPSE.from) / (LAPSE.to - LAPSE.from)) * (LAPSE.n - 1));
    cover(frame("lapse", i / FPS), { zoom, alpha: ease.inOutCubic(fade) });
  }
  const hh = Math.floor(hour), mm = Math.floor((hour - hh) * 6) * 10;
  label(t, `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}`, { start: DAY + 1.3, end: DAY + 3.75, size: 34 });
  lines(t, "It follows", "the real time of day.", { start: DAY + 0.25, end: DAY + 3.75 });
}

function schedule(t) {
  // The popover opens on the half bar, a frame early.
  const tc = at("schedule", "schedule", 0, true) + (t - (PLAN + 0.5) + EARLY);
  const push = ease.inOutCubic(span(t, PLAN + 0.35, 0.9));
  const cam = win("schedule", tc, { zoom: lerp(1.3, 1.95, push), fx: lerp(1380, 1500, push), fy: lerp(330, 200, push) });
  pointer("schedule", tc, cam, 1 - span(t, PLAN + 1.0, 0.3));
  lines(t, "One theme by day.", "One by night.", { start: PLAN + 0.2, end: PLAN + 1.82 });
}

// MARK: P. Plugins (32 to 36): Settings installs a package from a git repository, and its theme locks the screen

const SETTINGS = { w: 780, h: 580 };
// [film, clip]: the sheet opens on the beat, the repository is typed, Install is clicked on the next, and the film
// cuts to the plugin in the list: the clone and the sheet's way out (0.7 s) are left out.
const SHEET = at("plugins", "Install Plugin…", 0, true), TYPED = EVENTS.plugins.find((e) => e.kind === "type").t, INSTALL = at("plugins", "install");
const PLUGINS = [
  [32.0, SHEET - 0.5], [32.5 - EARLY, SHEET - 0.02], [32.9, SHEET + 0.4],
  [32.9, TYPED - 0.08], [33.25, TYPED + 0.27],
  [33.25, INSTALL - 0.22], [33.5 - EARLY, INSTALL + 0.02],
  [33.5 - EARLY, EVENTS.pluginInstalled + 0.03], [34.0, EVENTS.pluginInstalled + 0.55],
];

function plugins(t) {
  const tc = remap(t, PLUGINS);
  // The window's width fills the frame: the camera looks at its upper part, where the sheet and the list are.
  const cam = win("plugins", tc, { size: SETTINGS, fy: 262 });
  pointer("plugins", tc, cam, t < 33.5 - EARLY ? 1 : 0);
  label(t, "From any git repository", { start: 32.25, end: 33.85, y: 1010 });
}

function installed(t) {
  held("harbor", t - (34 - EARLY), 2, { from: 1.02, to: 1.05 });
  label(t, "A theme from a plugin", { start: 34.2, end: 35.82 });
  lines(t, "Install themes and widgets", "other people share.", { start: 34.15, end: 35.82, scrim: 0.36 });
}

// MARK: E. Make it yours (36 to 46): Customize, in the real editor

// [film, clip]: the recorded session with its waits taken out. Each answer of the app shows a frame before its beat,
// as a cut does.
const C = (note, nth = 0) => at("customize", note, nth, true);
const DRAG = (note) => at("customize", note);
const SCROLL = EVENTS.customize.find((e) => e.kind === "scroll").t;
const CUSTOMIZE = [
  // The editor opens a frame before the half beat. It shows a still picture of the theme for a fifth of a second
  // before its live screen: the film cuts that wait out.
  [36.0, C("Customize…") - 0.5], [36.5 - EARLY, C("Customize…") - 0.02],
  [36.5 - EARLY, EVENTS.editorLive + 0.02], [36.95, EVENTS.editorLive + 0.48],
  [36.95, DRAG("clock") - 0.35], [38.0, DRAG("clock") + 0.7],
  [38.0, DRAG("date") - 0.3], [39.05, DRAG("date") + 0.75],
  // Add Widget opens on the bar. Its pictures take a second to draw: the film skips the wait.
  [39.05, C("add") - 0.95], [40 - EARLY, C("add")], [40.25, C("add") + 0.25],
  [40.25, C("add") + 0.95], [40.45, C("add") + 1.15],
  [40.45, SCROLL - 0.03], [40.8, SCROLL + 1.67],
  // Three sizes, one a beat, then the click that adds the widget.
  [40.8, C("medium") - 0.4], [41 - EARLY, C("medium")], [41.5 - EARLY, C("large")], [42 - EARLY, C("medium", 1)],
  [42.5 - EARLY, C("add calendar")], [43.0, C("add calendar") + 0.75],
  [43.0, DRAG("calendar") - 0.17], [43.7, DRAG("calendar") + 0.83],
  // Four skies, one a beat.
  [43.7, C("animated") - 0.3], [44.0, C("animated") + 0.15],
  [44.0, C("galaxysea") - 0.6], [44.25 - EARLY, C("galaxysea")], [44.75 - EARLY, C("deepblue")],
  [45.25 - EARLY, C("synthwave")], [45.75 - EARLY, C("sakura")], [46.0, C("sakura") + 0.45],
];

function customize(t) {
  const tc = remap(t, CUSTOMIZE);
  // The camera goes to the sheet while it is open, and back for the drag. The sheet sits right of the words.
  const toSheet = ease.inOutCubic(span(t, 40.0, 0.45)) * (1 - ease.inOutCubic(span(t, 42.55, 0.45)));
  const cam = win("customize", tc, { zoom: lerp(1, 1.42, toSheet), fx: lerp(880, 719, toSheet), fy: lerp(495, 500, toSheet) });
  pointer("customize", tc, cam);
  line(t, "Make it yours.", { start: 36.12, end: 37.8 });
  line(t, "Drag anything.", { start: 38.0, end: 39.75 });
  if (t >= 40 && t < 43.2) {
    label(t, "27 widgets  ·  6 sizes", { start: 40.2, end: 42.85 });
    line(t, "Add widgets.", { start: 40.2, end: 42.85 });
  }
  line(t, "Change the sky.", { start: 43.95, end: 45.82 });
}

// MARK: F. Build (46 to 54): a theme from nothing, its Lua, and the widget an agent wrote

// Eight states of the recorded session, one a beat: blank, sky, a Text widget, its word, its size, its weight, the
// line, the line in its place. Each plays 0.8 s of the session in half a second.
// Each starts where its change shows, so the change is on the beat.
const NEW_STATES = [at("new", "new theme") + 1.47, at("new", "galaxysea", 0, true) + 0.02, at("new", "add text") + 0.47, keyAt("new", "return", 1) + 0.1,
  at("new", "huge", 0, true), at("new", "semibold") + 0.25, keyAt("new", "return", 2) + 0.1, at("new", "line") - 0.02];
const NEW = NEW_STATES.flatMap((c, i) => [[46 + i * BEAT, c], [46.5 + i * BEAT, c + 0.8]]);

function build(t) {
  const tc = remap(t, NEW);
  const cam = win("new", tc);
  pointer("new", tc, cam);
  line(t, "Or start from nothing.", { start: 46.1, end: 49.8 });
}

const LUA = `-- themes/launch.lua
return {
  name = "Launch Day",
  background = {
    shader = "galaxysea", params = { 610, 330 },
    colors = { "#070418", "#26174a", "#5d3fa3",
               "#e27fa4", "#7fcfff" },
  },
  auth = { style = "pill", anchor = "bottom",
           offset = { 0, -60 } },
  widgets = {
    { "date",  anchor = "top", offset = { 0, 110 },
      opts = { size = 22, weight = "semibold" } },
    { "clock", anchor = "top", offset = { 0, 130 },
      opts = { size = 140 } },
    { "text",  anchor = "center",
      opts = { text = "Locky", size = "huge",
               weight = "semibold" } },
    { "text",  anchor = "center", offset = { 0, 86 },
      opts = { color = "muted", text =
        "The lock screen you build yourself." } },
  },
}`.split("\n");

const CODE = { comment: "rgba(255,255,255,0.42)", string: "#f4a6c4", number: "#8fd4ff", word: "#c9b2ff", plain: "rgba(255,255,255,0.86)" };

/** One line of Lua in the theme's own colors. */
function code(text, x, y, alpha) {
  const parts = text.trimStart().startsWith("--") ? [[text, "comment"]]
    : [...text.matchAll(/("[^"]*")|(-?\b\d+(?:\.\d+)?\b)|(\b[a-z_]+\b(?=\s*=)|\breturn\b)|([^"\d\w]+|\w+)/g)]
      .map((m) => [m[0], m[1] ? "string" : m[2] ? "number" : m[3] ? "word" : "plain"]);
  let cx = x;
  ctx.save();
  ctx.globalAlpha = alpha;
  for (const [s, kind] of parts) {
    ctx.fillStyle = CODE[kind];
    ctx.fillText(s, cx, y);
    cx += ctx.measureText(s).width;
  }
  ctx.restore();
}

const PANEL = 860;       // the code's column
const CANVAS = { x: 730, y: 521, h: 882 };     // the editor's canvas in the window: its middle, its height

function lua(t) {
  const open = spring(t - 50.0, { freq: 1.5, damping: 0.9 });
  const panel = PANEL * open;
  // The editor's canvas grows to the frame's height and moves right, as the file comes in on the left.
  const k = lerp(W / WIN.w, H / CANVAS.h, open);
  const fx = lerp(880, CANVAS.x - panel / 2 / k, open), fy = lerp(495, CANVAS.y, open);
  const img = frame("new", at("new", "deselect") + 0.67 + (t - 50) * 0.4);
  if (img) {
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(img, W / 2 - fx * k, H / 2 - fy * k, WIN.w * k, WIN.h * k);
  }
  ctx.fillStyle = "#0a0816";
  ctx.fillRect(0, 0, panel, H);
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, 0, panel, H);
  ctx.clip();
  setFont(22, { family: "SF Mono", weight: 500, tracking: 0 });
  LUA.forEach((text, i) => {
    const p = ease.outExpo(clamp((t - 50.12 - i * 0.022) / 0.4));
    code(text, 118 - (1 - p) * 18, 98 + i * 28.6, p);
  });
  ctx.restore();
  label(t, "Write as many as you want", { start: 50.3, end: 51.82, y: 58 });
  lines(t, "Themes and widgets", "are Lua files.", { start: 50.25, end: 51.82 });
}

// The agent's session, cause before effect: the words go to the agent over the editor; then Add Widget has the
// agent's widget; a click puts it on the screen; it goes to its corner. It ends on the frame the lock comes in over.
const ADD = at("agent", "add"), ADDED = at("agent", "add vacation"), PINNED = at("agent", "pin top right"), PLACED = keyAt("agent", "return");
const AGENT = [[52.0, ADD - 0.62], [52.5 - EARLY, ADD - 0.12], [52.5 - EARLY, ADDED - 0.75], [53.0, ADDED + 0.25], [53.3, ADDED + 0.9],
  [53.3, PINNED - 0.1], [53.6, PINNED + 0.5], [53.6, PLACED - 0.03], [53.75, PLACED + 0.3],
  [53.75, EVENTS.agentDesk - 0.25], [54.0, EVENTS.agentDesk]];
const PROMPT = ["Make a Locky widget that shows", "the days until my vacation."];

function agent(t) {
  const tc = remap(t, AGENT);
  // The camera is at the sheet while it is open: the sheet sits right of the words.
  const toSheet = ease.inOutCubic(span(t, 52.3, 0.2)) * (1 - ease.inOutCubic(span(t, 52.98, 0.36)));
  const cam = win("agent", tc, { zoom: lerp(1, 1.3, toSheet), fx: lerp(880, 500, toSheet), fy: 495 });
  // The pointer goes once the widget is in its corner: its last move would cross the words.
  pointer("agent", tc, cam, 1 - span(t, 53.5, 0.12));
  // The words given to the agent, typed out before anything answers.
  const all = PROMPT.join("\n"), shown = all.slice(0, Math.round(all.length * span(t, 52.04, 0.42))).split("\n");
  const a = 1 - span(t, 53.78, 0.16);
  if (a > 0) {
    setFont(25, { family: "SF Mono", weight: 500, tracking: 0 });
    ctx.save();
    ctx.shadowColor = "rgba(0,0,0,0.75)";
    ctx.shadowBlur = 16;
    ctx.fillStyle = `rgba(255,255,255,${0.5 * a})`;
    ctx.fillText("›", 118, 714);
    ctx.fillStyle = `rgba(255,255,255,${0.94 * a})`;
    shown.forEach((text, i) => ctx.fillText(text + (i === shown.length - 1 && t < 52.5 ? "▍" : ""), 146, 714 + i * 34));
    ctx.restore();
  }
  // Top left, under the window's title bar: the lock screen's own words are in the middle.
  label(t, "Locky ships its own agent skill", { start: 52.2, end: 53.78, y: 104 });
  lines(t, "Or ask", "your coding agent.", { start: 52.12, end: 53.78 });
}

// MARK: G. Lock (54 to 60) and H. the end card (60 to 64)

// One take at its own speed, from 54 s to the end: the way in over the editor's last frame, the typing, and the hold.
const lockTime = (t) => TRANSITIONS.lockin.desk_to / FPS + (t - 54);
// The push toward the password field stops where the date and the corner widget are still whole.
const PUSH = { zoom: 1.085, oy: 0.63 };

function locked(t) {
  const push = ease.inOutCubic(span(t, 56.0, 3.6));
  lock("lockin", lockTime(t), { zoom: lerp(1.02, PUSH.zoom, push), ox: 0.5, oy: lerp(0.5, PUSH.oy, push) });
  // What a Locky lock is: its own windows over a session that stays unlocked behind them (docs/security.md).
  label(t, "macOS keeps running behind Locky's lock", { start: 55.1, end: 56.9 });
  lines(t, "Lock your MacBook.", "Your agents keep working.", { start: 54.6, end: 56.9 });
  lines(t, "A real lock.", "Touch ID or your password.", { start: 57.2, end: 59.55 });
}

function endCard(t) {
  // The same take, whole again: the theme built at 46 s is the film's last frame.
  const back = spring(t - 60.0, { freq: 1.1, damping: 0.9 });
  lock("lockin", lockTime(t), { zoom: lerp(PUSH.zoom, 1.02, back) + 0.018 * span(t, 60, 4), ox: 0.5, oy: lerp(PUSH.oy, 0.5, back) });
  const a = ease.outExpo(span(t, 60.7, 0.5));
  drawIcon(116, 906 + 22 + (1 - a) * 16, 100, a);
  line(t, "Locky for macOS", { start: 60.7, end: 70, x: 240, y: 878, size: 52, scrim: 0.22 });
  line(t, "by InsaneArts", { start: 60.9, end: 70, x: 241, y: 925, size: 36, tone: 0.62, scrim: 0 });
  label(t, "You watched this lock screen being built.", { start: 61.5, end: 70, y: 772, size: 26 });
}

// MARK: The film

const SECTIONS = [
  [0, hook], [8, run], [11.5, app], [18, ways], [24, live], [DAY, lapse], [PLAN, schedule], [32, plugins], [34, installed], [36, customize], [46, build],
  [50, lua], [52, agent], [54, locked], [60, endCard],
];

function film(t) {
  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, W, H);
  let draw = SECTIONS[0][1];
  for (const [start, f] of SECTIONS) if (t >= start - EARLY - EPS) draw = f;
  draw(t);
  grain(t, 0.04);
  if (GUIDES) {
    ctx.save();
    ctx.setLineDash([12, 10]);
    ctx.strokeStyle = "rgba(255,0,80,.9)";
    ctx.lineWidth = 2;
    ctx.strokeRect(W * 0.06, H * 0.06, W * 0.88, H * 0.88);
    setFont(30, { family: "SF Mono", weight: 500, tracking: 0 });
    ctx.fillStyle = "rgba(255,0,80,.95)";
    ctx.fillText(t.toFixed(2) + " s", 24, H - 22);
    ctx.restore();
  }
}

// Every sound's time, for tools/score.py: the film and its sound share this table.
window.CUES = {
  length: DURATION,
  cuts: [2, 4, 5, 6, 7],
  run: [8, 8.5, 9, 9.5, 10, 10.5, 11, 11.5],
  stepBack: 12,
  list: WALK.map((_, j) => 13 + j * BEAT),
  ways: [18, 20, 22],
  live: [24, 26, 30, 32, 34],
  lapse: [DAY + 1.3, DAY + 3.75],
  popover: PLAN + 0.5,
  plugin: [32.5, 33.0, 33.5],
  editor: 36.5,
  drags: [37.3, 38.3, 43.17],
  sheet: 40,
  sizes: [41, 41.5, 42],
  add: 42.5,
  skies: [44.25, 44.75, 45.25, 45.75],
  states: Array.from({ length: 8 }, (_, i) => 46 + i * BEAT),
  panel: 50,
  agent: [52.5, 53.0, 53.3],
  lock: 54,
  // A dot shows 0.16 s after its key was sent: the sound is on the dot.
  keys: EVENTS.lockinKeys.map((k) => 54 + k + 0.16 - TRANSITIONS.lockin.desk_to / FPS),
  end: 60,
  icon: 60.7,
};

setDraw(film);
window.FILM = { duration: DURATION, fps: FPS };
window.READY = true;
