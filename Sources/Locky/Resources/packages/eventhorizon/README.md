# Event Horizon

A black hole seen almost edge-on, after Interstellar's Gargantua. Its accretion disk turns, faster near the hole,
and the approaching side is brighter. Gravity bends the disk's far side into a halo over and under the shadow, and
bends the stars behind it.

```lua
locky.setup({ theme = "eventhorizon" })
```

## What it shows

- A thin clock and the date above the hole; the weather and the battery in the bottom corners.
- The `eventhorizon` shader draws the scene. Its colors are space, then the disk from its hot inner edge out.
  Parameters: the hole's center in points from the top (530), the shadow's radius (104), and the disk's speed (1).
