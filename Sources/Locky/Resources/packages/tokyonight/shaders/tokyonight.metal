// Tokyo Night: a night city's glow seen through a window. Ink blue, with soft blue and magenta neon blooms, a
// few out-of-focus lights drifting very slowly, and a fine grain.
// Colors: 0 the night, 1 the blue glow, 2 the magenta glow, 3 the lights.
// Params: 0 grain (default 0.015).

static float tokyonight_hash(float2 p) {
    p = fract(p * float2(233.34, 851.73));
    p += dot(p, p + 23.45);
    return fract(p.x * p.y);
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float aspect = res.x / res.y;
    float2 q = float2(uv.x * aspect, uv.y);
    float3 col = locky_color(p, 0);
    // Two blooms: blue high on the left, magenta low on the right.
    float blue = exp(-3.2 * length(q - float2(0.25 * aspect, 0.85)));
    float magenta = exp(-2.6 * length(q - float2(0.85 * aspect, 0.12)));
    col += locky_color(p, 1) * blue * 0.35 + locky_color(p, 2) * magenta * 0.32;
    // Bokeh: soft discs on a coarse grid, each with its own size and brightness, drifting up slowly.
    float3 lights = locky_color(p, 3);
    for (int layer = 0; layer < 2; layer++) {
        float scale = layer == 0 ? 7.0 : 11.0;
        float2 g = q * scale + float2(0.0, t * 0.01 * (layer + 1));
        float2 cell = floor(g), f = fract(g) - 0.5;
        float h = tokyonight_hash(cell + layer * 17.0);
        if (h > 0.8) {
            float2 at = float2(tokyonight_hash(cell + 3.1) - 0.5, tokyonight_hash(cell + 7.7) - 0.5) * 0.5;
            float r = 0.12 + 0.18 * tokyonight_hash(cell + 11.0);
            float disc = smoothstep(r, r * 0.6, length(f - at));
            float3 tint = mix(lights, locky_color(p, h > 0.9 ? 2 : 1), 0.75);
            col += tint * disc * (0.06 + 0.1 * h) * (layer == 0 ? 1.0 : 0.6);
        }
    }
    col += (tokyonight_hash(floor(uv * res)) - 0.5) * locky_param(p, 0, 0.015);
    return float4(col, 1.0);
}
