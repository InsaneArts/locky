# Mission

The lock screen as a flight controller's console. The big clock counts mission elapsed time from the moment the screen
locked, and around it the Mac reports like a spacecraft.

```lua
locky.setup({ theme = "mission" })
```

## What it shows

- `mission.header`: the console's title bar and its status, SECURED.
- `mission.met`: T+ hours, minutes, and seconds since the lock, with the local time under it.
- `mission.clocks`: UTC, local time, Unix time, and the day of the year, each second.
- `mission.telemetry`: CPU, memory, disk, and battery as 20-segment bars, each with a status word: NOMINAL, CAUTION
  (65% used, or 30% battery), or ALARM (85% used, or 15% battery).
- The day, week, month, and year as progress rings; a binary clock as the time code; the network as the downlink; and
  the days to New Year.

The `mission` shader draws a plotting grid; it is still, so it costs nothing after the first frame.
