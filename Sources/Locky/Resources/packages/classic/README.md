# Classic

A 1-bit desktop from the mid-1980s: a gray dither pattern, a menu bar, windows with striped title bars and hard
shadows, and a dialog that asks for your password. Set in Silom and Geneva.

```lua
locky.setup({ theme = "classic" })
```

## What it shows

- `classic.menubar`: a padlock where the menu would be, File, Edit, View, Special, and the time.
- `classic.about`: About This Computer: the macOS version, the chip, and the memory with a bar of what is in use.
- `classic.clock`: the alarm clock desk accessory, ticking each second, with the date.
- `classic.icons`: the disk, a folder, and the trash down the right side.
- `classic.dialog`: "This computer is locked." The password field sits in it.

The `classic` shader draws the desktop pattern, a 2×2 checker of black and white pixels (`params = { 2 }` sets the pixel
size).
