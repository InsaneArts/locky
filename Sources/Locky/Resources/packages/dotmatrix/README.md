# Dot Matrix

A lock screen made of dots: a 5×7 dot-matrix clock on a faint dot grid, in black, white, and gray, with
one red dot in the colon that pulses once a second. Inspired by the dot-matrix graphics of modern
minimalist hardware and the character LCDs they come from.

```lua
locky.setup({ theme = "dotmatrix" })
```

## What it shows

- **Clock** (`dotmatrix.clock`): HH:MM in 5×7 glyphs, with the unlit dots of each character cell. It
  follows the system's 12/24-hour setting; in 12-hour time a single-digit hour leaves its first cell dark.
- **Pulse** (`dotmatrix.pulse`): the red dot in the colon. It lights at each new second and dims half a
  second later.
- **Word** (`dotmatrix.word`): "LOCKED" in small dot letters, above the clock on the left.
- **Agents** (`dotmatrix.agents`): one square per [herdr](https://herdr.dev) agent, above the clock on the
  right: blocked red, done white, working gray, idle as an outline. Hidden when herdr is not running.
- **Info** (`dotmatrix.info`): the date at the left under the clock ("MON 12 OCT"), the battery at the
  right ("BAT 56%", "CHG 56%" while charging, red at 20% or less), and uptime between them. On a Mac
  without a battery, uptime moves to the right.
- **Background**: a ghost grid of 1.5-point dots, 12 points apart, at 4% white. It lines up with the
  clock, so every clock dot sits on a grid dot.
- **Password**: an outlined box at the bottom, "PASSWORD" in SF Mono.

## Palette roles

| Role | Default | Used for |
|---|---|---|
| `bg` | `#000000` | background |
| `fg` | `#ffffff` | lit clock dots, done agents |
| `dim` | `#121212` | unlit clock dots (7% white on black; keep it opaque) |
| `signal` | `#d71921` | the pulsing colon dot, blocked agents |
| `muted` | `#8a8a8e` | labels, the word, working agents |
| `accent` | `#ffffff80` | the password box's border while it has focus (it always has focus) |
| `border` | `#ffffff4d` | the password box's border without focus |
| `danger` | `#d71921` | low battery, a wrong password |

```lua
locky.setup({ theme = "dotmatrix", palette = { signal = "#ff5a00", fg = "#f2f2f2" } })
```

If you change `bg`, change `dim` with it: `dim` is the unlit dot color, mixed by hand for black.

## Widget options

```lua
locky.setup({
  widgets = {
    ["dotmatrix.clock"] = { hour24 = true },        -- force 24-hour (or false: 12-hour)
    ["dotmatrix.word"] = { text = "AWAY" },          -- A-Z, 0-9, "-", ".", and space
    ["dotmatrix.info"] = { format = "EEE dd.MM" },   -- any date template
    ["dotmatrix.agents"] = { label = false },        -- squares only
  },
})
```

| Widget | Options |
|---|---|
| `dotmatrix.clock` | `pitch` (24, distance between dots), `dot` (0.8, dot size as a fraction of the pitch), `hour24` |
| `dotmatrix.pulse` | `pitch`, `dot`: keep them equal to the clock's |
| `dotmatrix.word` | `text` ("LOCKED"), `pitch` (4), `dot` (0.75), `color` ("muted") |
| `dotmatrix.info` | `format` ("EEE d MMM"), `width` (596), `size` (12), `tracking` (1.5), `low` (20) |
| `dotmatrix.agents` | `size` (9), `gap` (5), `max` (30), `label` ("AGENTS", or false) |

`dotmatrix.pulse` is its own widget so that the clock's dots are not laid out again twice a second.
Place it with the same anchor and offset as `dotmatrix.clock`; if you move or resize the clock, move or
resize the pulse with it. The background grid's dots line up with a clock of pitch 24 at its default
place; other pitches and places work, without that alignment.
