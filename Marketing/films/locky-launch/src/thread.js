// The thread's clips: one short film a feature, for the replies under the launch film. THREAD.md has the posts.
// The same studio as the film: every frame is a function of its time, and a cut shows one frame before its beat.
//   node tools/render.mjs film --page thread --clip themes --out out/thread/01-themes.mp4 --audio out/thread/themes.wav
import { W, H, FPS, SCALE, ctx, clamp, lerp, span, ease, frame, picture, grain, setFont, setDraw } from "/src/engine.js";
import { BEAT, EARLY, EPS, EVENTS, TRANSITIONS, NAME, SECTIONS, line, lines, label, named, lock, held, win, remap, pointer, shot } from "/src/film.js";

const THEMES = await (await fetch("/src/thread-themes.json")).json();
const TAKES = await (await fetch("/src/thread-events.json")).json();
const WAYS = { ...TRANSITIONS, ...(await (await fetch("/src/thread-transitions.json")).json()) };
// The film's pointer finds a take's clicks by its clip's name.
Object.assign(EVENTS, TAKES);
const click = (clip, note, nth = 0) => EVENTS[clip].filter((e) => e.note === note)[nth];

// A part of the film on its own says two of its lines another way: nothing came before it.
window.SAY = { "Or start from nothing.": "Start from nothing.", "You watched this lock screen being built.": "" };

/** A part of the film, as the film draws it. */
function filmAt(t) {
  let draw = SECTIONS[0][1];
  for (const [start, f] of SECTIONS) if (t >= start - EARLY - EPS) draw = f;
  draw(t);
}

/** A name on a dark plate, with a count over it. Where a cut comes every half second, and each picture has its own
    layout, words on the picture itself land on a widget in one theme or another. */
function plate(count, name) {
  setFont(54, { weight: 600, tracking: -0.012 });
  const wide = ctx.measureText(name).width;
  setFont(24, { family: "SF Mono", weight: 500, tracking: 0.08 });
  const w = Math.max(wide, ctx.measureText(count).width) + 64, h = 130, x = 92, y = 962 - h;
  ctx.save();
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, 24);
  ctx.fillStyle = "rgba(10,10,12,0.76)";
  ctx.fill();
  ctx.strokeStyle = "rgba(255,255,255,0.12)";
  ctx.lineWidth = 1;
  ctx.stroke();
  ctx.fillStyle = "rgba(255,255,255,0.62)";
  ctx.fillText(count, x + 33, y + 44);
  setFont(54, { weight: 600, tracking: -0.012 });
  ctx.fillStyle = "#fff";
  ctx.fillText(name, x + 30, y + 104);
  ctx.restore();
}

// MARK: Themes (24.5 s): the 43, one a beat, each with its name; the score's last chord lands on the end

const END = THEMES.length * BEAT;

function themes(t) {
  if (t >= END - EARLY - EPS) {
    // Back to the first theme, held, with the name.
    lock("sakura", 0.4 + (t - END), { zoom: lerp(1.02, 1.06, span(t, END, 3)) });
    named(t, "Locky has 43.", { start: END + 0.05, end: 99, ink: "light" });
    return;
  }
  const k = shot(t, 0, BEAT, THEMES.length);
  const local = t + EARLY - k * BEAT;
  lock(`t-${THEMES[k].id}`, local, { zoom: 1.02 + 0.035 * (1 - ease.outExpo(clamp(local / 0.42))) });
  plate(`${String(k + 1).padStart(2, "0")} / ${THEMES.length}`, THEMES[k].name);
}

// MARK: Live wallpapers (16 s): five held shots

const LIVE = [["deepblue", "Deep Blue"], ["snowfall", "Snowfall"], ["eventhorizon", "Event Horizon"], ["liquid", "Liquid"], ["galaxysea", "Galaxy Sea"]];

function live(t) {
  const k = shot(t, 0, 3, LIVE.length);
  held(LIVE[k][0], t + EARLY - k * 3, 4, { from: 1.02, to: 1.075 });
  label(t, LIVE[k][1], { start: -1, end: 99, ...NAME });
  line(t, "The wallpapers are live.", { start: 0.3, end: 2.75 });
  line(t, "Shaders, drawn in Metal.", { start: 3.25, end: 5.75, scrim: 0.42 });
  line(t, "Write your own.", { start: 9.25, end: 11.75, scrim: 0.4 });
  line(t, "They stop in Low Power Mode.", { start: 12.25, end: 15.4, scrim: 0.4 });
}

// MARK: The Settings takes: the window with the helper's desktop around it

const REGION = { w: 1280, h: 720 }, MARGIN = { x: 250, y: 40 };

/** A Settings take, large: `left` and `bottom` are the window's own points at the frame's left and bottom edges, and
    `k` is pixels a point. The window's sidebar is empty below its five rows: the words sit there. */
function desk(clip, tc, { k = 2.2, left = -24, bottom = 601 } = {}) {
  const img = frame(clip, tc);
  if (img) {
    ctx.save();
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(img, -(left + MARGIN.x) * k, H - (bottom + MARGIN.y) * k, REGION.w * k, REGION.h * k);
    ctx.restore();
  }
  return { k, fx: left + MARGIN.x + W / 2 / k, fy: bottom + MARGIN.y - H / 2 / k };
}
/** The camera comes a little closer as a take starts. */
const closer = (t) => lerp(2.06, 2.2, ease.inOutCubic(span(t, 0.1, 1.4)));

/** Words in the sidebar: a label, and two short lines. The sidebar is 215 points wide: a line has 18 letters at most. */
function side(t, about, rows, { start, end }) {
  label(t, about, { start, end, x: 102, y: 776, size: 22 });
  rows.forEach((row, i) => line(t, row, { start: start + 0.05 + i * 0.2, end, x: 100, y: 842 + i * 58, size: 46, scrim: 0, tone: i ? 0.6 : 1 }));
}

// MARK: Lock animations (18.5 s): the menu in Settings, then each of the seven, full frame, one a bar

const STYLES = [["wayfocus", "Focus"], ["wayfade", "Fade"], ["wayiris", "Iris"], ["waylift", "Lift"], ["waysweep", "Sweep"],
                ["waydissolve", "Dissolve"], ["waytiles", "Tiles"]];
const MENU = 4;

function animations(t) {
  if (t < MENU - EARLY - EPS) {
    // The take in real time: the menu opens after a second, Tiles is chosen, and the small preview plays it.
    const tc = click("set-anim", "menu").t - 1.0 + t;
    const cam = desk("set-anim", tc, { k: closer(t) });
    pointer("set-anim", tc, cam);
    side(t, "Settings  ›  Lock Screen", ["Seven ways", "to lock."], { start: 0.3, end: 3.7 });
    return;
  }
  const k = shot(t, MENU, 2, STYLES.length);
  const start = MENU + k * 2;
  const [clip, name] = STYLES[k];
  // The page under the lock shows for a quarter second, then the take's own way in plays at its own speed.
  lock(clip, WAYS[clip].desk_to / FPS - 0.25 + (t + EARLY - start), { zoom: 1.02 });
  if (t >= start + 0.75) plate(`${k + 1} / ${STYLES.length}`, name);
}

// MARK: The Touch ID button (8 s): the switch, then the lock a press shows

const PRESS = 4;

function touchid(t) {
  if (t < PRESS - EARLY - EPS) {
    // The click lands on the first cut of the score's quiet opening.
    const tc = click("set-touchid", "touch id").t - 2.0 + t;
    const cam = desk("set-touchid", tc, { k: closer(t) });
    pointer("set-touchid", tc, cam);
    side(t, "Settings  ›  General", ["Touch ID button", "locks with Locky."], { start: 0.3, end: 3.7 });
    return;
  }
  lock("wayfocus", WAYS.wayfocus.desk_to / FPS - 0.3 + (t + EARLY - PRESS), { zoom: 1.02 });
  label(t, "Off by default  ·  needs Accessibility access", { start: PRESS + 1.2, end: 7.6 });
  lines(t, "A press shows Locky's lock,", "not the macOS lock screen.", { start: PRESS + 1.0, end: 7.6, scrim: 0.4 });
}

// MARK: The photo after wrong passwords (8 s): the menu in Settings › Unlock

function photo(t) {
  // The menu opens, the pointer goes down to "After 3 wrong passwords", and the take holds there.
  const tc = Math.min(click("set-photo", "menu").t - 1.5 + t, EVENTS["set-photo"].find((e) => e.kind === "key").t - 0.15);
  // A little wider than the other takes: the open menu reaches past the window's right edge.
  const cam = desk("set-photo", tc, { k: closer(t) - 0.1, bottom: 511 });
  pointer("set-photo", tc, cam);
  side(t, "Settings  ›  Unlock", ["Wrong password?", "It takes a photo."], { start: 0.3, end: 3.7 });
  side(t, "Only you can open them", ["It keeps 20 photos", "for 30 days each."], { start: 4.05, end: 7.6 });
}

// MARK: Settings (10 s): Lock Automatically, then the other panes

const TOUR = 4.5;
const PANES = ["Lock Screen", "Unlock", "Customization", "Plugins", "General"];

function settings(t) {
  if (t < TOUR - EARLY - EPS) {
    // The take at 1.6 times its speed: the menu, 5 minutes, and the two switches, one a second.
    const at = (note) => click("set-autolock", note).t;
    const tc = remap(t, [[0, at("menu") - 0.75], [0.75, at("menu")], [1.75, at("For 5 minutes")], [2.75, at("display")], [3.5, at("sleep")],
                         [TOUR, at("sleep") + 1.0]]);
    const cam = desk("set-autolock", tc, { k: closer(t) });
    pointer("set-autolock", tc, cam);
    side(t, "Settings  ›  General", ["Locks by itself", "after 5 minutes."], { start: 0.3, end: 4.2 });
    return;
  }
  // The five panes, one a second: the take's waits are cut.
  const points = [];
  PANES.forEach((pane, i) => {
    const seen = click("set-tour", pane).seen ?? click("set-tour", pane).t + 0.15;
    points.push([TOUR + i - (i ? EARLY : 0), seen + 0.05], [TOUR + i + 1 - EARLY, seen + 1.0]);
  });
  desk("set-tour", remap(t, points));
  side(t, "settings.json", ["Every switch is", "also a JSON key."], { start: TOUR + 0.35, end: 9.6 });
}

// MARK: Plugins (9.5 s): Settings installs a package from a git repository, and its theme locks the screen

const HARBOR = 6;

function plugins(t) {
  if (t < HARBOR - EARLY - EPS) {
    // The take in real time, from just before the sheet opens. A half second after it opens, macOS shows an empty
    // completion list under the field for a few frames: the film cuts that half second out, where nothing else moves.
    const opened = click("plugins", "Install Plugin…").t;
    const tc = remap(t, [[0, opened - 0.9], [1.25, opened + 0.35], [1.25, opened + 0.9], [HARBOR, opened + 0.9 + HARBOR - 1.25]]);
    const cam = win("plugins", tc, { size: { w: 780, h: 580 }, fy: 262 });
    pointer("plugins", tc, cam);
    label(t, "Settings  ›  Plugins  ·  from any git repository", { start: 0.3, end: 5.7, y: 1010 });
    return;
  }
  lock("harbor", t + EARLY - HARBOR, { zoom: lerp(1.02, 1.05, span(t, HARBOR, 3.5)) });
  label(t, "A theme from a plugin", { start: HARBOR + 0.2, end: 9.2 });
  lines(t, "Themes and widgets", "other people share.", { start: HARBOR + 0.15, end: 9.2, scrim: 0.36 });
}

// MARK: Stills

function privacy() {
  const cam = click("set-tour", "Lock Screen");
  desk("set-tour", (cam.seen ?? cam.t) + 1.0, { bottom: 541 });
  side(9, "Settings  ›  Lock Screen", ["Hide your name", "when it locks."], { start: 0, end: 99 });
}

function safety() {
  // The Welcome's last page, over the lock screen it is about.
  ctx.save();
  ctx.filter = `blur(${28 * SCALE}px) brightness(0.5)`;
  lock("sakura", 1.0, { zoom: 1.12 });
  ctx.restore();
  const img = picture("/assets/thread/welcome-3.png");
  if (img) {
    const k = 1.72, w = 560 * k, h = 544 * k, x = W - w - 112, y = (H - h) / 2;
    ctx.save();
    ctx.beginPath();
    ctx.roundRect(x, y, w, h, 26 * k / 1.72);
    ctx.shadowColor = "rgba(0,0,0,0.55)";
    ctx.shadowBlur = 70;
    ctx.shadowOffsetY = 26;
    ctx.fillStyle = "#1e1e1e";
    ctx.fill();
    ctx.shadowColor = "transparent";
    ctx.clip();
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(img, x, y, w, h);
    ctx.restore();
  }
  label(9, "A second process watches every lock", { start: 0, end: 99 });
  lines(9, "If Locky crashes,", "macOS locks your Mac.", { start: 0, end: 99, scrim: 0 });
}

// MARK: The clips: each one's length and its picture. A part of the film plays at the film's own times.

const part = (from) => (t) => filmAt(t + from);
const CLIPS = {
  themes: [END + 3, themes], live: [16, live], time: [6, part(26)], animations: [MENU + STYLES.length * 2 + 0.5, animations],
  touchid: [8, touchid], customize: [10, part(36)], build: [8, part(46)], plugins: [9.5, plugins], photo: [8, photo],
  settings: [10, settings], agents: [10, part(54)], privacy: [1, privacy], safety: [1, safety],
};
const name = new URLSearchParams(location.search).get("clip") || "themes";
const [DURATION, clip] = CLIPS[name];

setDraw((t) => {
  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, W, H);
  clip(t);
  grain(t, 0.04);
});
window.FILM = { duration: DURATION, fps: FPS };
window.READY = true;
