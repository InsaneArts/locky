# Pocket

A handheld game's four-shade green screen. The battery is your lives, the uptime your score, the day of the year the
level, and the game is Conway's Life.

```lua
locky.setup({ theme = "pocket" })
```

## What it shows

- `pocket.hud`: five hearts (one for each fifth of the battery), SCORE (minutes since the Mac started), and LV (the day
  of the year).
- `pocket.clock`: the time in a 5×7 pixel font, each pixel a square (`opts.pixel`, default 14).
- The date, and the `life` widget on a framed board: Conway's Game of Life, starting again when it settles.
- The password field says PRESS START.

The `pocket` shader draws the LCD: its pixel grid, the light falling off toward the dark rim.
