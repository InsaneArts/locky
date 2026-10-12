# Liquid Glass

The lock screen of iOS 26 and macOS Tahoe, on your own wallpaper: a huge rounded clock, the date above it,
and a row of Liquid Glass gauges under it. The password field stays hidden until you press a key or move the
mouse, so the glance state shows only the time and the gauges.

```lua
locky.setup({ theme = "glass" })
```

## What it shows

- **Background:** your desktop picture, barely blurred and dimmed by 12%. Without one, the `glass` shader
  paints an homage to the Tahoe wallpaper: a sky that fades to sandy beige, crossed by one cobalt wave whose
  crest breaks into light-blue and cream streaks. It drifts slowly. A dynamic wallpaper (one that changes
  through the day) gets the scene too: Locky only receives its small thumbnail, which cannot look sharp.
- **Clock** (`glass.clock`): SF Pro Rounded, heavy, 270 points, with tight tracking and a soft shadow, at
  about a third of the screen's height. Your Mac's 12- or 24-hour setting applies. Its digits change without
  rolling: at this size the roll would cost about a second of CPU every minute.
- **Date:** SF Pro semibold above the clock, in your language.
- **Gauges** (`glass.gauges`): four glass circles, each with an open ring, a value, and a small symbol:
  battery, CPU, memory, and the [herdr](https://herdr.dev) agents that need you. The battery circle hides on
  Macs without a battery; the agents circle hides when herdr is not running.
- **Password field:** a glass pill with your picture and name, at the bottom. It darkens the background by
  25% while it shows and hides again after 20 seconds without input.

The rings take their color from your wallpaper: the theme picks its most colorful dominant color and makes
it light. Without a wallpaper they use `#8ec5ff`.

## Options

Palette roles (`locky.setup({ palette = { ... } })`):

| Role | Default | Used for |
|---|---|---|
| `fg` | `#ffffff` | the clock, values, and symbols |
| `muted` | `#ffffffb3` | the password field's placeholder and hint |
| `accent` | from the wallpaper, or `#8ec5ff` | the gauge rings |
| `track` | `#ffffff40` | the rings' tracks |
| `surface` | `#ffffff1f` | the password pill's glass tint |
| `success`, `danger`, `warning` | system colors | a charging battery, a low battery, a blocked agent |
| `sky`, `sand`, `wave`, `crest`, `cream` | `#8ec5ff`, `#ebdcc3`, `#1e4fd8`, `#bfe0ff`, `#ffe9b0` | the fallback scene |

Gauge options (`locky.setup({ widgets = { ["glass.gauges"] = { ... } } })`):

| Option | Default | |
|---|---|---|
| `size` | `64` | circle diameter |
| `spacing` | `22` | space between circles |
| `stroke` | `4.5` | ring width |
| `color`, `track` | `"accent"`, `"track"` | ring and track colors |
| `shade` | `"#0000001f"`; `"#17377a3d"` on the fallback scene | a tint inside each circle that keeps white legible on bright glass |
| `every` | `5` | seconds between CPU and memory readings |
| `agents` | `5` | seconds between herdr checks; `false` hides the agents circle |
| `low` | `20` | battery percent at or below which the ring turns red |

Clock options (`glass.clock`): `format` (`"time"`, or a template such as `"HH:mm"`), `size` (270), `weight`
(`"heavy"`), `design` (`"rounded"`), `tracking` (-8), `shadow` (24), `color` (`"fg"`).

A sharper or softer wallpaper: `locky.theme.extend("glass", { background = { blur = 0 } })`.
