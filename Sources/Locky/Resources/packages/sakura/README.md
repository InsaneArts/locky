# Sakura

A spring night under a full moon. A cherry branch in bloom reaches in from the top left, petals drift down and turn as
they fall, and a snow-capped mountain and a pagoda stand in the mist. The month's old Japanese name hangs on the right
like a scroll. After the falling-sakura wallpapers at the top of Wallpaper Engine's charts.

```lua
locky.setup({ theme = "sakura" })
```

## What it shows

- The time and date in Hiragino Mincho, the weather, and the battery.
- **Month** (`sakura.month`): this month's traditional name (神無月, Kannazuki, "month of the gods' absence"), set
  vertically, with its reading and meaning. Options: `size`, `font`, `color`, `reading` (false shows the name only).
- The `sakura` shader draws the scene. Its colors are the sky's top and its low part, the blossoms and their light
  centers, the moon, and the silhouettes. Parameters: how many petals (1), and the wind (1).
