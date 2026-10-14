# Mocha

The r/unixporn classic: [Catppuccin](https://catppuccin.com) Mocha with an
[i3lock-color](https://github.com/Raymo111/i3lock-color) ring. The password field is the ring, and the time
sits inside it.

```lua
locky.setup({ theme = "mocha" })
```

## What it shows

- The background: your desktop picture, blurred and tinted with Catppuccin's base color, so any wallpaper
  keeps the palette. Without a desktop picture, a quiet base-to-mantle gradient.
- The center: the ring, 320 points wide. Each key you type lights a green arc at a random place; backspace
  lights a rosewater one. The ring turns green while the password is checked and maroon when it is wrong.
  Inside, on a dark disc: the time, the date, and the keyboard layout. With Touch ID, the Touch ID symbol
  shows near the bottom of the ring while Touch ID listens.
- Top left: `user@host`. Top right: battery and uptime (no battery on a desktop Mac).
- Bottom left: one dot per [herdr](https://herdr.dev) agent that needs you or is working (blocked peach,
  done green, working blue) and their counts. Hidden when herdr is not running.
- Bottom right: a small `mocha`.

Everything is set in SF Mono. The time follows your Mac's 12- or 24-hour setting, and the date is in your
language.

## Options

Palette roles (`locky.setup({ palette = { ... } })`). The ring uses `border` (idle), `accent` (a key),
`warning` (backspace), and `danger` (wrong). The widgets use Catppuccin's names: `base`, `mantle`, `crust`,
`text` (also `fg`), `subtext0` (also `muted`), `overlay0`, `surface0`, `surface1`, `mauve`, `green`,
`rosewater`, `blue`, `maroon`, `peach`, `yellow`, `red`, `lavender`; `disc` is the fill inside the ring.
Another Catppuccin flavor is a palette away; for Macchiato's ring and disc:

```lua
locky.setup({ theme = "mocha", palette = { bg = "#24273a", mantle = "#1e2030", border = "#363a4f", disc = "#1e2030cc" } })
```

Widget options (`locky.setup({ widgets = { ["mocha.center"] = { ... } } })`):

| Widget | Option | Default | |
|---|---|---|---|
| `mocha.center` | `size` | `56` | the time's font size |
| | `disc` | `300` | the disc's diameter; `false` for none |
| | `keyboard` | `true` | `false` hides the keyboard layout |
| `mocha.user` | `size` | `14` | |
| `mocha.status` | `low` | `20` | battery percent at or below which its icon turns red |
| `mocha.agents` | `max` | `16` | most dots shown |
| | `every` | `5` | seconds between herdr checks |
| `mocha.label` | `text` | `"mocha"` | the word in the bottom-right corner |

The background's blur, dim, and tint are in the theme's `background` table:
`locky.theme.extend("mocha", { background = { blur = 40, tint_amount = 0.7 } })`.

Catppuccin's colors are MIT licensed.
