# Matrix

Digital rain behind a glowing green clock. The messages that woke Neo type themselves out in the corner, and the Mac's
busiest processes show at the bottom.

```lua
locky.setup({ theme = "matrix" })
```

## What it shows

- The time and the date, in the dark middle of the rain.
- `matrix.whisper`: "Wake up, Neo…", "The Matrix has you…", "Follow the white rabbit.", and "Knock, knock, Neo.",
  typed one letter at a time with a blinking cursor, then a minute of quiet. It uses your first name, or "Neo" in
  privacy mode. Options: `name`, `hold`, `rest`.
- The top processes, CPU and memory, and the network speed.
- The `matrix` shader draws the rain. Its glyphs are random strokes on a small grid, so they read as an unknown script.
  Its colors are the background, the rain, and the bright heads. Parameter 1 sets how many streams fall (default 1);
  parameter 2 how much the middle darkens (default 0.6).
