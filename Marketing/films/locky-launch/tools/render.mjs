#!/usr/bin/env node
// Renders the film (src/film.html) frame by frame in headless Chrome. Every frame is seek(t): any frame renders alone.
//   node tools/render.mjs sheet 0.5,2,4.1 [--name hook] [--scale 1]   stills + a contact sheet in reviews/
//   --page rex draws another composition of the same studio: src/rex.html (default: film)
//   node tools/render.mjs film [--from 0 --to 64] [--scale 1] [--workers 6] [--out out/draft.mp4] [--audio out/score.wav]
// The page posts each frame to this script as a JPEG; ffmpeg encodes the numbered frames.
import { spawn, spawnSync } from "node:child_process";
import { createReadStream, existsSync, mkdirSync, mkdtempSync, rmSync, statSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const film = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const mode = args[0];
const opt = (k, d) => (args.includes(`--${k}`) ? args[args.indexOf(`--${k}`) + 1] : d);
const scale = Number(opt("scale", 1));
const pageName = opt("page", "film");
const W = 1920 * scale, H = 1080 * scale, FPS = 60;
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

const types = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".png": "image/png", ".jpg": "image/jpeg",
  ".svg": "image/svg+xml", ".otf": "font/otf", ".ttf": "font/ttf", ".css": "text/css" };
let sink = null;       // (index, buffer) => void, set while frames are wanted
const server = createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  const path = decodeURIComponent(url.pathname);
  if (req.method === "POST" && path === "/put") {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => { sink?.(Number(url.searchParams.get("i")), Buffer.concat(chunks)); res.writeHead(200).end("ok"); });
    return;
  }
  const file = path.startsWith("/fonts/") ? join("/Library/Fonts", path.slice(7)) : join(film, path === "/" ? `src/${pageName}.html` : path.slice(1));
  if (!existsSync(file) || !statSync(file).isFile()) return res.writeHead(404).end();
  res.writeHead(200, { "content-type": types[extname(file)] || "application/octet-stream", "cache-control": "no-store" });
  createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const profile = mkdtempSync(join(tmpdir(), "locky-film-"));
const chrome = spawn(CHROME, ["--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`, "--hide-scrollbars", "--mute-audio",
  "--force-color-profile=srgb", "--disable-background-timer-throttling", "--disable-renderer-backgrounding", "about:blank"], { stdio: ["ignore", "ignore", "pipe"] });
const wsBrowser = await new Promise((ok, fail) => {
  let log = "";
  chrome.stderr.on("data", (d) => { log += d; const m = log.match(/DevTools listening on (ws:\/\/\S+)/); if (m) ok(m[1]); });
  chrome.on("exit", () => fail(new Error("Chrome exited:\n" + log)));
});
const cdpPort = new URL(wsBrowser).port;

async function page() {
  const target = await (await fetch(`http://127.0.0.1:${cdpPort}/json/new?about:blank`, { method: "PUT" })).json();
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener("open", r, { once: true }));
  let id = 0;
  const pending = new Map();
  ws.addEventListener("message", (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) pending.get(m.id)(m), pending.delete(m.id);
    if (m.method === "Runtime.exceptionThrown") console.error("film error:", m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text);
  });
  const send = (method, params = {}) => new Promise((r) => { pending.set(++id, r); ws.send(JSON.stringify({ id, method, params })); });
  const evaluate = async (expression) => {
    const m = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
    if (m.result?.exceptionDetails) throw new Error(m.result.exceptionDetails.exception?.description ?? JSON.stringify(m.result.exceptionDetails));
    return m.result?.result?.value;
  };
  await send("Runtime.enable");
  await send("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: 1, mobile: false });
  await send("Page.navigate", { url: `http://127.0.0.1:${port}/?scale=${scale}${args.includes("--guides") ? "&guides=1" : ""}` });
  for (let i = 0; i < 400; i++) {
    const state = await evaluate("window.READY ? JSON.stringify(window.FILM) : null").catch(() => null);
    if (state) return { evaluate, meta: JSON.parse(state), close: () => ws.close() };
    await new Promise((r) => setTimeout(r, 50));
  }
  throw new Error("the film page did not load");
}

const ffmpeg = (a) => { const r = spawnSync("ffmpeg", ["-loglevel", "error", "-y", ...a], { stdio: "inherit" }); if (r.status) throw new Error("ffmpeg failed"); };

try {
  if (mode === "sheet") {
    const times = args[1].split(",").map(Number);
    const name = opt("name", "sheet");
    const dir = join(film, "reviews", name);
    mkdirSync(dir, { recursive: true });
    const p = await page();
    const files = [];
    for (const t of times) {
      const f = join(dir, `t${t.toFixed(2).padStart(6, "0")}.png`);
      const data = await p.evaluate(`seek(${t}).then(() => document.getElementById("c").toDataURL("image/png"))`);
      writeFileSync(f, Buffer.from(data.split(",")[1], "base64"));
      files.push(f);
    }
    const cols = Math.min(files.length, Number(opt("cols", 3))), tile = Number(opt("tile", 800)), th = Math.round(tile * 9 / 16);
    const sheet = join(film, "reviews", `${name}.png`);
    if (files.length === 1) ffmpeg(["-i", files[0], "-vf", `scale=${tile * 2}:-2`, sheet]);
    else ffmpeg([...files.flatMap((f) => ["-i", f]), "-filter_complex",
      `${files.map((_, i) => `[${i}]scale=${tile}:${th}[s${i}]`).join(";")};${files.map((_, i) => `[s${i}]`).join("")}xstack=inputs=${files.length}:layout=${files.map((_, i) => `${(i % cols) * (tile + 6)}_${Math.floor(i / cols) * (th + 6)}`).join("|")}:fill=0x202020`,
      "-frames:v", "1", sheet]);
    console.log(`stills → ${dir}\nsheet  → ${sheet}`);
    p.close();
  } else if (mode === "cues") {
    // Every sound's time, as the page has it: tools/score.py reads this.
    const p = await page();
    const out = resolve(film, pageName === "film" ? "out/cues.json" : `out/cues-${pageName}.json`);
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, await p.evaluate("JSON.stringify(window.CUES, null, 1)"));
    console.log(`cues → ${out}`);
    p.close();
  } else if (mode === "film") {
    const first = await page();
    const from = Number(opt("from", 0)), to = Number(opt("to", first.meta.duration));
    const a = Math.round(from * FPS), b = Math.round(to * FPS), n = b - a;
    const workers = Number(opt("workers", 6));
    const frames = mkdtempSync(join(film, "build", "render-"));
    let done = 0;
    sink = (i, buffer) => { writeFileSync(join(frames, `${String(i - a + 1).padStart(6, "0")}.jpg`), buffer); done++; };
    const started = Date.now();
    const pages = [first, ...(await Promise.all(Array.from({ length: workers - 1 }, page)))];
    const timer = setInterval(() => console.log(`frame ${done}/${n}  ${(done / ((Date.now() - started) / 1000)).toFixed(1)} fps`), 30000);
    // Each worker takes a contiguous run of frames, so its image cache stays warm.
    await Promise.all(pages.map((p, k) => {
      const lo = a + Math.floor((n * k) / workers), hi = a + Math.floor((n * (k + 1)) / workers);
      return p.evaluate(`renderRange(${lo}, ${hi}, ${FPS})`);
    }));
    clearInterval(timer);
    sink = null;
    pages.forEach((p) => p.close());
    const out = resolve(film, opt("out", "out/draft.mp4"));
    mkdirSync(dirname(out), { recursive: true });
    const audio = opt("audio");
    const audioIn = audio ? ["-ss", String(from), "-t", String(to - from), "-i", resolve(film, audio)] : [];
    ffmpeg(["-framerate", String(FPS), "-i", join(frames, "%06d.jpg"), ...audioIn,
      "-vf", "scale=in_range=pc:out_range=tv:out_color_matrix=bt709:flags=accurate_rnd+full_chroma_int,format=yuv420p",
      "-c:v", "libx264", "-preset", "slow", "-crf", opt("crf", "15"), "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
      "-color_range", "tv", ...(audio ? ["-c:a", "aac", "-b:a", "256k", "-shortest"] : []), "-movflags", "+faststart", out]);
    rmSync(frames, { recursive: true, force: true });
    console.log(`\rvideo → ${out}  (${n} frames in ${((Date.now() - started) / 1000).toFixed(0)} s)`);
  } else {
    console.error("usage: render.mjs sheet t1,t2 [--name n] | render.mjs film [--from a --to b] [--out file] [--audio wav]");
  }
} finally {
  server.close();
  const exited = new Promise((r) => chrome.once("exit", r));
  chrome.kill();
  await exited;
  rmSync(profile, { recursive: true, force: true, maxRetries: 5 });
}
