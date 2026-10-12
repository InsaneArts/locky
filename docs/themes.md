# Themes

A theme is `themes/<name>.lua` in the runtime path: a Lua file that returns a table. It sets the palette,
the fonts, the background, the cards, the password field, and which widgets go where. A theme package is
a folder (or git repository) that ships a theme together with its own widgets, shaders, and assets:

```
locky-synthwave/
  themes/synthwave.lua      -- the theme
  plugin/synthwave.lua      -- its own widgets (locky.widget.define)
  shaders/synthwave.metal   -- its background
  assets/                   -- images, if any
```

## The table

```lua
return {
  name = "Synthwave",
  description = "A neon grid at sunset.",
  author = "you",

  -- Roles every widget can name in `color`. These defaults apply to roles you leave out:
  -- bg #000000, fg #ffffff, muted #ffffff99, accent #0a84ff, surface #ffffff1a, border #ffffff26,
  -- success #30d158, warning #ff9f0a, danger #ff453a. Add any roles you like.
  palette = { bg = "#0d0221", fg = "#f7f1ff", muted = "#f7f1ffa0", accent = "#ff2a6d", accent2 = "#05d9e8" },

  -- The default font for all text: family (any installed font), design, weight.
  font = { family = "Futura", weight = "medium" },

  background = { shader = "synthwave", colors = { "bg", "accent", "accent2" }, speed = 1, fps = 60 },

  -- Optional: drawn above the widgets and below the password field, keeping its transparency. For
  -- scanlines, film grain, or a vignette over everything. Same table as a background.
  overlay = { shader = "synthwave-scanlines", fps = 30 },

  -- Cards for widgets placed with card = true: "glass", "solid" (fill and border), "outline", or "none".
  card = { style = "solid", radius = 14, fill = "surface", border = "border" },

  -- The password field: style "pill", "underline", "box", "terminal", "minimal", or "ring" (i3lock's: a
  -- ring `width` wide that lights an arc on each key; place a clock inside it at the same anchor).
  -- reveal = "activity" hides it until a key press or mouse movement (the glance state) and again after
  -- `idle` seconds; `dim` darkens the background while it shows. Widgets hear "auth_shown"/"auth_hidden".
  -- focus is the palette role of the focused border or underline (default "accent"); font.size sets the
  -- text size (default 14); hint_align = "leading" lines the hint up with the field; glow gives the text a
  -- glow; ring = { width, fill, glow } styles the "ring" style.
  auth = { style = "underline", anchor = "bottom", offset = { 0, -80 }, width = 260, avatar = false, name = false,
           hint = true, placeholder = "password", prompt = nil, font = { family = "Menlo", size = 14 },
           focus = "accent", hint_align = "center", glow = nil, reveal = "always", idle = 20, dim = 0 },

  widgets = {
    -- { widget, anchor, offset = { x, y }, size = { w, h }, align, card, display, opts }
    { "clock", anchor = "center", offset = { 0, -60 }, opts = { size = 200, font = "Futura", color = "accent" } },
    { "date", anchor = "center", offset = { 0, 60 } },
    { "synthwave.sun", anchor = "top-right", offset = { -40, 40 }, card = true },
  },
}
```

**Placement.** `anchor` is `top`, `top-left`, `top-right`, `left`, `center`, `right`, `bottom`,
`bottom-left`, or `bottom-right`. `offset` moves the widget from there in points; y grows downwards, so a
`bottom` widget uses a negative y. Without `size`, a widget is as big as its content. With `size`,
`align` places the content inside it: `leading`, `trailing`, `top`, `bottom`, `top-leading`, `bottom-trailing`,
and so on (default center). `card = true` uses the theme's card, or name a style. `display =
"all"` repeats the widget on every display; by default widgets show on the main display only, and every
display gets the background.

**Layout size.** Lay a theme out for a 1440×900 screen. Locky scales sizes and offsets on other screens
(a 1728×1117 MacBook Pro screen scales by 1.2).

**Options.** `opts` merge into the widget's defaults; the user's `locky.setup({ widgets = { name = {...} } })`
merges on top. Options may hold functions.

## Backgrounds

| Table | Shows |
|---|---|
| `{ shader = "name", colors = { ... }, params = { ... }, speed = 1, resolution = 1, fps = 60, dim = 0 }` | A Metal shader from `shaders/name.metal`, next to the theme or in the runtime path. |
| `{ wallpaper = true, blur = 30, dim = 0.25, tint = "bg", tint_amount = 0 }` | The user's desktop picture, blurred, dimmed, and tinted. |
| `{ image = "assets/x.jpg", blur = 0, dim = 0 }` | An image file. |
| `{ video = "~/Movies/x.mp4", dim = 0 }` | A video on a silent loop. |
| `{ gradient = { "#000", "#123" }, angle = 180, noise = 0.05 }` | A linear gradient; `noise` adds film grain against banding. |
| `{ color = "bg" }` | One color. |

Colors may be palette roles. `resolution` below 1 renders a shader at that fraction of the screen's
pixels and scales it up, which saves battery for soft backgrounds; `fps` caps its frame rate, and
`fps = 0` draws a still shader once (and again only when the screen size changes).

## Overlays

`overlay` takes the same tables as `background` and draws above the widgets, under the password field. An
overlay shader's alpha is kept: return `float4(color, alpha)` with plain (not premultiplied) color, and
alpha 0 wherever the widgets should show through untouched.

## Shaders

A shader is Metal source that defines one function. Locky compiles it when the screen locks:

```metal
float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    // uv: 0…1 across the screen, y up.   t: seconds (times `speed`).   res: size in pixels.
    float3 sky = mix(locky_color(p, 0), locky_color(p, 1), uv.y);
    float glow = locky_param(p, 0, 0.5);          // params[1] from the theme, or 0.5
    return float4(sky * (0.8 + glow * 0.2), 1.0);
}
```

`locky_color(p, i)` is color `i` of the theme's `colors` list (the last one when there are fewer);
`locky_param(p, i, fallback)` is entry `i` of `params`. Up to 8 colors and 16 params. `p.clock` is the local
time in seconds since midnight, for effects that follow the real clock (a sky by time of day, a fill that
rises with the seconds); `t` only counts from when the screen locked. Prefix your helper
functions (`static float myname_noise(...)`) so they cannot clash with Locky's. A compile error appears on
the lock screen in the preview, with its line number, and in the log.

## Changing a theme from init.lua

```lua
locky.setup({ theme = "synthwave", palette = { accent = "#00ff9f" } })   -- recolor any theme
locky.theme.extend("synthwave", { background = { speed = 0.5 } })        -- merge a table (lists are replaced)
locky.theme.extend("synthwave", function(theme)                           -- or change it in code
  table.insert(theme.widgets, { "battery", anchor = "top-left", offset = { 24, 24 } })
end)
```
