// Pocket: a handheld's four-shade LCD: the lightest green, its pixel grid faintly visible, a soft gradient where the
// light from the front falls off, and a dark rim.
// Static: the theme draws it once a second.
// Colors: 0 the screen, 1 the pixel grid, 2 the rim.

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float cell = res.y / 225.0;
    float2 f = fract(uv * res / cell);
    float gridline = step(0.86, f.x) + step(0.86, f.y);
    float3 col = mix(locky_color(p, 0), locky_color(p, 1), min(gridline, 1.0) * 0.35);
    float2 c = uv - 0.5;
    col *= 1.0 - 0.18 * dot(c, c) * 2.0;
    float rim = smoothstep(0.47, 0.5, max(abs(c.x), abs(c.y) * 1.0));
    col = mix(col, locky_color(p, 2), rim * 0.8);
    return float4(col, 1.0);
}
