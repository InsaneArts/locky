// The Rex theme, 10 s: one take of the live lock screen (the locky-rex pack), with the wallpaper's clock four times as
// fast, so its 36 s loop takes 9 s and each split opens on a beat of the score. The film adds only a tag.
import { W, H, FPS, ctx, clamp, span, ease, frame, picture, setFont, setDraw, grain } from "/src/engine.js";

const DURATION = 10;
const WALL = "#10120f";

function film(t) {
  // The take is a preview window's content, whose lower corners are round: the wall's own color is under them.
  ctx.fillStyle = WALL;
  ctx.fillRect(0, 0, W, H);
  const img = frame("rexclip", t);
  if (img) {
    ctx.save();
    ctx.beginPath();
    ctx.roundRect(0, 0, W, H, [0, 0, 34, 34]);
    ctx.clip();
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(img, 0, 0, W, H);
    ctx.restore();
  }
  // The tag, top left, where superlogical.com has its own name: there from the first frame, which is the poster.
  const icon = picture("/assets/icon.png");
  if (icon) {
    const size = 46, full = size / 0.8, pad = (full - size) / 2;
    ctx.drawImage(icon, 76 - pad, 66 - pad, full, full);
    ctx.beginPath();
    ctx.roundRect(76.5, 66.5, size - 1, size - 1, size * 0.225);
    ctx.strokeStyle = "rgba(255,255,255,0.16)";
    ctx.lineWidth = 1;
    ctx.stroke();
  }
  setFont(27, { weight: 600, tracking: -0.01 });
  ctx.fillStyle = "rgba(243,241,236,0.96)";
  ctx.fillText("A Rex theme for Locky", 138, 99);
}

// Every sound's time, for tools/rex_score.py: when each split opens, moves, and closes.
window.CUES = { length: DURATION, music: 8, open: [1.0, 2.5], move: [4.0, 5.5], close: [6.75, 8.0] };

setDraw(film);
window.FILM = { duration: DURATION, fps: FPS };
window.READY = true;
