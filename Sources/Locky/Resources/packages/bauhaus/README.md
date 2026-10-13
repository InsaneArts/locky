# Bauhaus

The lock screen as a poster from the 1923 Weimar exhibition: primary colors in circle, square, and triangle on cream
paper, overprinted like inks, and the time set large in Futura.

```lua
locky.setup({ theme = "bauhaus" })
```

## What it shows

- The time, the weekday in red, the date, and the weather in blue, set flush right.
- `bauhaus.title`: a word set vertically in the corner (`opts.text`, default LOCKY).
- The `bauhaus` shader draws the composition. A notch in the red circle sweeps around once a minute with the real
  seconds, so the poster is also a clock.
