# Lookout

Layered ridges fading into haze, pines, a flock of birds, and a fire lookout on the near ridge. The light follows the
real time of day: the sun crosses from left to right, the sky goes from dawn pink to day gold to dusk orange, and at
night the ridges turn blue, the stars come out, and the lookout's window is lit. After the Firewatch-style mountain
wallpapers that are perennial Wallpaper Engine favorites.

```lua
locky.setup({ theme = "lookout" })
```

## What it shows

- The time and date in Futura, today's sun path with sunrise and sunset, the weather, and the battery.
- The `lookout` shader draws the scene. Its colors are the dusk sky's top and its horizon, the far and near ridges,
  and the sun; day and night are worked out from them. Parameters: the hour to show (-1, the default, follows the
  clock), and how many birds (1).
