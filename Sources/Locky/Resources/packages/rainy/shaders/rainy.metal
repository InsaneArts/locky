// Rainy: a window on a rainy night. Behind the glass, a city's lights out of focus; on it, drops that slide down and
// bend the light behind them, and a fine mist of small beads.
// Colors: 0 the sky, 1 the street below, 2 warm lights, 3 cool lights.
// Params: 0 how much rain (default 1).

static float rainy_hash(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

// The city behind the glass, out of focus.
static float3 rainy_city(float2 q, float aspect, constant LockyParams &p) {
    float3 col = mix(locky_color(p, 1), locky_color(p, 0), smoothstep(0.0, 0.85, q.y));
    for (int layer = 0; layer < 3; layer++) {
        float scale = 5.0 + layer * 3.0;
        float2 g = q * scale + float2(layer * 3.7, 0.0);
        float2 cell = floor(g), f = fract(g) - 0.5;
        float h = rainy_hash(cell + layer * 11.0);
        if (h > 0.55) {
            // Kept inside the cell: offset plus radius stays under half a cell, so no disc is cut off.
            float2 at = (float2(rainy_hash(cell + 2.3), rainy_hash(cell + 5.1)) - 0.5) * 0.4;
            float r = 0.14 + 0.14 * rainy_hash(cell + 8.0);
            float disc = smoothstep(r, r * 0.25, length(f - at));
            float3 light = h > 0.8 ? locky_color(p, 3) : locky_color(p, 2);
            float fade = 1.0 - smoothstep(0.35, 0.9, q.y);
            col += light * disc * (0.25 + 0.25 * h) * fade;
        }
    }
    return col;
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float aspect = res.x / res.y;
    float2 q = float2(uv.x * aspect, uv.y);
    float amount = locky_param(p, 0, 1.0);
    float2 bend = float2(0.0);
    float wet = 0.0;

    // Sliding drops: one per column cell, falling with a sawtooth, leaving a trail.
    float2 grid = float2(14.0, 3.0);
    float2 g = q * grid;
    float column = floor(g.x);
    float speed = 0.06 + 0.06 * rainy_hash(float2(column, 1.0));
    float2 st = float2(g.x, g.y + t * speed * grid.y);
    float2 cell = floor(st), f = fract(st) - 0.5;
    float n = rainy_hash(cell + column * 7.1);
    if (n < 0.5 * amount + 0.15) {
        float y = fract(t * 0.05 + n * 6.0);
        float fall = -(y * y * 0.9 - 0.45);
        float wiggle = sin(cell.y * 3.0 + t * 0.5) * 0.08;
        // In cell widths: a cell is grid.x / grid.y times taller than it is wide.
        float tall = grid.x / grid.y / aspect;
        float2 d = (f - float2(wiggle, fall)) * float2(1.0, tall);
        float drop = smoothstep(0.2, 0.12, length(d));
        bend += d * drop * 0.5;
        wet += drop;
        // The trail above it: beads that shrink with distance.
        float above = f.y - fall;
        float2 b = float2(f.x - wiggle, (fract(above * tall * 2.5) - 0.5) / (tall * 2.5)) * float2(1.0, tall);
        float bead = smoothstep(0.07, 0.03, length(b)) * step(0.05, above) * smoothstep(0.5, 0.1, above);
        bend += b * bead * 0.3;
        wet += bead * 0.7;
    }

    // Mist: tiny still beads all over the glass.
    float2 m = q * 60.0;
    float2 mc = floor(m), mf = fract(m) - 0.5;
    float mh = rainy_hash(mc);
    float bead = smoothstep(0.12, 0.05, length(mf - (float2(rainy_hash(mc + 1.0), rainy_hash(mc + 2.0)) - 0.5) * 0.6)) * step(0.55, mh);
    bend += mf * bead * 0.02;
    wet += bead * 0.3;

    float3 col = rainy_city(q + bend * 0.25, aspect, p);
    // Drops catch light on top and darken at the rim.
    col += wet * 0.08 + max(bend.y, 0.0) * 0.6;
    // A soft vignette, darker at the bottom where the sill would be.
    float2 c = uv - 0.5;
    col *= 1.0 - 0.45 * dot(c, c);
    col += (rainy_hash(floor(uv * res)) - 0.5) * 0.02;
    return float4(col, 1.0);
}
