# Views

A widget's `render` returns a view built with `locky.ui`. Locky draws it natively with SwiftUI. Sizes are
in points for a 1440×900 screen; Locky scales them on bigger screens.

```lua
local ui = locky.ui
return ui.hstack {
  spacing = 10,                                   -- named fields are properties
  ui.symbol("bolt.fill", { color = "warning" }),  -- list items are children
  ui.text("Charging", { weight = "semibold" }),
  low and ui.text("low", { color = "danger" }),   -- false and nil children are skipped
  ui.each(items, function(item) return ui.text(item) end),  -- a list of views is spliced in
}
```

## Views

| Builder | Shows |
|---|---|
| `ui.vstack { ... }`, `ui.hstack { ... }`, `ui.zstack { ... }` | Children in a column, a row, or on top of each other. |
| `ui.grid { columns = 7, ... }` | Children in rows of `columns` cells. |
| `ui.text(string, props)` | Text. A number is shown as it is. |
| `ui.time(format, props)` | Live time or date text. It updates itself every second without running Lua, and its digits roll when they change (not when the format shows seconds; set `numeric` to choose). `format`: `"time"` (the system's hours and minutes, without AM/PM), `"date"` (weekday, month, day, in the system's order), a date pattern used as it is (`"HH:mm"`, `"HH"`, `"mm"`, `"EEEE"`, `"d MMMM"`, `"EEE dd.MM"`; names come in the user's language), or `"skeleton:EEEEdMMMM"` for those fields ordered and punctuated the user's way. |
| `ui.symbol(name, props)` | An [SF Symbol](https://developer.apple.com/sf-symbols/), sized by `size`. |
| `ui.image(path, props)` | An image file: absolute, `~/...`, or relative to the calling plugin's package. |
| `ui.progress(value, props)` | A bar filled to `value` (0 to 1). `size` is its height; `background` its track. |
| `ui.ring(value, props)` | A ring filled to `value` (0 to 1), from 12 o'clock clockwise. `size` is its diameter; `stroke` its track; `from` (0 to 1) starts the arc later, for gauges; `style = "butt"` gives square ends. |
| `ui.gauge(value, props)` | A gauge, as on the Lock Screen, for `value` between `min` (default 0) and `max` (default 1). `style`: `"circular"` (an open arc with a marker; default), `"capacity"` (a ring filled to the value), `"linear"` (a track with a marker), `"linear-capacity"` (a filled bar). `value_label` is the text in the middle; `icon` (an SF Symbol), or `min_label` and `max_label`, sit in the arc's gap; `label` names a linear gauge. `size` is the diameter, or a linear gauge's width. `color` tints it and takes a gradient. |
| `ui.chart(values, props)` | A chart, newest value last. `style`: `"line"` (default), `"area"`, or `"bar"`; `min`, `max`, `slots`. |
| `ui.rect(props)`, `ui.circle(props)`, `ui.capsule(props)` | A shape, filled with `color` and/or outlined with `stroke`. |
| `ui.line(props)` | A horizontal line `width` long and `stroke_width` thick. Rotate it for clock hands. |
| `ui.polygon(props)` | A closed shape through `points = { {x, y}, ... }`, each a fraction (0 to 1) of the view's `width` and `height`. Fill it with `color`, outline it with `stroke`. |
| `ui.dot(props)` | A filled circle, `size` 8 by default. |
| `ui.spacer()` | Empty space that pushes its neighbors apart in a stack. |
| `ui.divider(props)` | A thin line across a stack. |

`ui.font(name, props)` returns props for one of Apple's text styles, merged with `props`:
`ui.text("Tbilisi", ui.font("headline", { color = "muted" }))`. The styles are `large_title` (34), `title` (28),
`title2` (22), `title3` (20), `headline` (17, semibold), `body` (17), `callout` (16), `subheadline` (15),
`footnote` (13), `caption` (12), and `caption2` (11).

## Properties

Any view takes any of these. Unknown names are ignored.

**Text**

| Property | Value |
|---|---|
| `size` | Font size. |
| `weight` | `"ultralight"`, `"thin"`, `"light"`, `"regular"`, `"medium"`, `"semibold"`, `"bold"`, `"heavy"`, `"black"`. |
| `design` | `"default"`, `"rounded"`, `"serif"`, `"monospaced"`: the system font's designs. |
| `font` | A font family, such as `"Futura"`, `"Didot"`, `"Menlo"`, `"Avenir Next"`, or a PostScript name such as `"HelveticaNeue-CondensedBlack"` (which keeps its own weight unless you set `weight`). Falls back to the system font. |
| `mono` | `true`: digits all one width, so time and numbers do not jitter. |
| `tracking` | Letter spacing. |
| `italic` | `true`: the face's italic. A face without one stays upright; use `skew`. |
| `skew` | Degrees of slant (about 10 looks italic), for faces without an italic. |
| `case` | `"upper"` or `"lower"`. |
| `lines` | Most lines to show. |
| `text_align` | `"leading"`, `"center"`, `"trailing"`, for text on several lines. |
| `line_spacing` | Extra space between lines. |
| `numeric` | `true`: digits roll when the text changes, like `ui.time`. |
| `stretch` | `"compressed"`, `"condensed"`, or `"expanded"`: the system font's widths. |

Without `font` and `design`, text uses the theme's font.

**Color**

| Property | Value |
|---|---|
| `color` | The foreground: a palette role (`"fg"`, `"muted"`, `"accent"`, `"danger"`, any role the theme defines), a color name (`"white"`, `"orange"`, …), `"#rgb"`, `"#rrggbb"`, `"#rrggbbaa"`, or a gradient `{ "#ff00aa", "#00ddff", angle = 90 }` (0 points up, 90 right). Children inherit it; without any, text uses the theme's `fg`. |
| `opacity` | 0 to 1. |

**Layout**

| Property | Value |
|---|---|
| `spacing` | Space between a stack's or grid's children. |
| `align` | In stacks: how children line up (`"leading"`, `"center"`, `"trailing"`, `"top"`, `"bottom"`). In a zstack or a filled view: where content sits (`"top-leading"`, `"bottom-trailing"`, …). |
| `columns` | A grid's cells per row. |
| `padding` | One number (all sides), `{ vertical, horizontal }`, or `{ top, leading, bottom, trailing }`. |
| `width`, `height` | A fixed size. Content sits in the middle, or by `text_align`. |
| `max_width` | Wrap text at this width. Content sits at the leading edge, or by `text_align`. |
| `fill` | `true` (all the space it is given), `"width"`, or `"height"`. |
| `offset` | `{ x, y }`: move it without moving its neighbors. |
| `rotation` | Degrees, clockwise, around the view's center (after `offset`, so an offset hand turns around the center). |
| `scale` | A factor. |

**Decoration**

| Property | Value |
|---|---|
| `background` | A color or gradient behind the view, or `"glass"` for Liquid Glass. Shaped by `radius`. |
| `radius` | Corner radius for `background`, `border`, `ui.rect`, and `ui.image`. |
| `border`, `border_width` | An outline. |
| `shadow`, `shadow_color` | A drop shadow's radius and color. |
| `glow` | `true` or a radius: a shadow in the view's own color. |
| `blur` | A blur radius. |
| `blend` | How the view mixes with everything drawn behind it, other widgets and the background included: `"multiply"`, `"screen"`, `"overlay"`, `"difference"`, `"exclusion"`, `"soft-light"`, `"hard-light"`, `"color-dodge"`, `"color-burn"`, `"plus-lighter"`, `"lighten"`, `"darken"`. |
| `stroke`, `stroke_width` | A shape's outline, a ring's track, a chart's line width. |
| `dash` | A dash pattern for outlines and ring tracks, such as `{ 2, 4 }`. |
| `clip` | `true`: cut off anything outside the view's bounds (rounded by `radius`). |
| `animate` | `"smooth"`, `"spring"`, or `"linear"`: changes to this view animate. |
| `id` | A stable identity, so animations follow the right child when a list changes. |

**Animations cost CPU.** While anything moves, its view is drawn again on every frame. Rolling digits and
`animate` suit values that change now and then (a minute, a battery percent), not ones that change every
second or two: a ring that animates every 2 s keeps about 6% of a core busy. The cost also grows with size:
a 150-point clock spends about 0.4 s of CPU on each roll, so the built-in themes set `numeric = false` on
big clocks.

**Images and symbols**

| Property | Value |
|---|---|
| `fit` | `"fill"` (default) or `"fit"`. |
| `tint` | `true`: draw the image in `color`. |
| `mode` | For symbols: `"hierarchical"`, `"palette"` (with `colors = { ... }`), or `"multicolor"`. |
