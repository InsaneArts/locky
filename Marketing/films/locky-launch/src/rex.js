// The Rex theme, 13 s: one take of the live lock screen (the locky-rex pack) over made-up Rex sessions whose programs
// report real statuses while the camera runs (tools/rex_shoot.py). The film adds only a tag.
import { FPS, ctx, frame, picture, cover, setFont, setDraw } from "/src/engine.js";

const DURATION = 13;
const TIMING = await (await fetch("/src/rex-timing.json")).json();

function film(t) {
  // The take is a preview window's content: a little larger than the frame, so the window's round lower corners and
  // the line under its title bar are outside it.
  cover(frame("rexclip", t), { zoom: 1.02 });
  // The tag, top left: there from the first frame, which is the poster.
  const icon = picture("/assets/icon.png");
  if (icon) {
    const size = 46, full = size / 0.8, pad = (full - size) / 2;
    ctx.save();
    ctx.shadowColor = "rgba(0,0,0,0.3)";
    ctx.shadowBlur = 16;
    ctx.shadowOffsetY = 4;
    ctx.drawImage(icon, 80 - pad, 70 - pad, full, full);
    ctx.restore();
    ctx.beginPath();
    ctx.roundRect(80.5, 70.5, size - 1, size - 1, size * 0.225);
    ctx.strokeStyle = "rgba(255,255,255,0.18)";
    ctx.lineWidth = 1;
    ctx.stroke();
  }
  setFont(27, { weight: 600, tracking: -0.01 });
  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,0.45)";
  ctx.shadowBlur = 14;
  ctx.fillStyle = "rgba(255,255,255,0.97)";
  ctx.fillText("A Rex theme for Locky", 142, 103);
  ctx.restore();
}

// Every sound's time, for tools/rex_score.py: where the track starts, and when a program first needs the user.
window.CUES = { length: DURATION, music: 8, needs: TIMING.needs };

setDraw(film);
window.FILM = { duration: DURATION, fps: FPS };
window.READY = true;
