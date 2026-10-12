# Synthwave

A neon sunset over a perspective grid, after the 1980s outrun look: a striped sun sinking behind violet
mountains, a magenta and cyan grid scrolling toward you, and a chrome clock in the sky.

```lua
locky.setup({ theme = "synthwave" })
```

## What it shows

- **Background** (`shaders/synthwave.metal`): a sky from deep violet to hot pink at the horizon, twinkling
  stars, a big sun from orange to pink cut by bands that widen and drift down, low-poly mountains with a
  magenta rim, and a grid floor that scrolls toward you and melts into a pink haze at the horizon. It
  renders at 0.75 resolution and 30 frames a second. The scene is laid out in the same points as the
  widgets, so the sun stays under the clock on any screen.
- **Overlay** (`shaders/synthwave-overlay.metal`): faint scanlines over everything except the password
  field. It is static and draws once a second.
- **Clock** (`synthwave.clock`): the time in Futura Condensed ExtraBold, 200 points, with a chrome
  gradient (white, cyan, pink) and a pink glow. It follows the system's 12/24-hour setting.
- **Date** (`synthwave.date`): tracked neon cyan capitals under the clock, in your language.
- **Battery** (`synthwave.battery`): top right, percent and symbol in cyan; red at 20% or less. Hidden on
  a Mac without a battery.
- **Agents** (`synthwave.agents`): top left, one neon dot per [herdr](https://herdr.dev) agent: blocked
  pink, done cyan, working orange, idle dim. Hidden when herdr is not running.
- **Password**: a dark translucent box with a neon border at the bottom. The floor is darker behind it.

## Palette roles

| Role | Default | Used for |
|---|---|---|
| `bg` | `#0d0221` | the sky's top, the floor |
| `sky` | `#2a0845` | the sky's middle |
| `accent` | `#ff2a6d` | hot pink: the horizon, the sun's bottom, glows, blocked agents, the focused password border |
| `sun` | `#ff9e00` | the sun's top, working agents |
| `mountain` | `#3d0a52` | the mountains |
| `magenta` | `#ff2bd6` | the grid's cross lines, the mountains' rim |
| `accent2` | `#05d9e8` | cyan: the grid's long lines, the date, battery, done agents |
| `chrome1`, `chrome2`, `chrome3` | `#ffffff`, `#8be9fd`, `#ff79c6` | the clock's gradient, top to bottom |
| `fg`, `muted` | `#f7f1ff`, `#f7f1ffa0` | text, labels, the password placeholder |
| `surface`, `border` | `#0d0221cc`, `#05d9e8` | the password box's fill and its border without focus |
| `danger` | `#ff3864` | low battery, a wrong password |

```lua
locky.setup({ theme = "synthwave", palette = { accent2 = "#00ff9f", sun = "#ffd319" } })
```

## Options

```lua
locky.setup({
  widgets = {
    ["synthwave.clock"] = { size = 180, format = "HH:mm" },
    ["synthwave.date"] = { format = "EEE d MMM" },
    ["synthwave.agents"] = { label = false },
  },
})
locky.theme.extend("synthwave", { background = { params = { 560, 175, 0.25 } } })  -- a slower grid
locky.theme.extend("synthwave", function(theme) theme.overlay = nil end)          -- no scanlines
```

| Widget | Options |
|---|---|
| `synthwave.clock` | `format` ("time"), `size` (200), `font` ("Futura-CondensedExtraBold"), `tracking` (3), `glow` (24) |
| `synthwave.date` | `format` ("EEEE d MMMM"), `size` (17), `tracking` (6), `color` ("accent2"), `glow` (10) |
| `synthwave.battery` | `size` (15), `color` ("accent2"), `low` (20) |
| `synthwave.agents` | `size` (8), `gap` (7), `max` (24), `label` ("AGENTS", or false), `every` (3 seconds) |

Background params: horizon (points from the top, 560), sun radius (points, 175), grid speed (cells a
second, 0.45). Overlay params: scanline period (points, 3), darkness (0.18).
