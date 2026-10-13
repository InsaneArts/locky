// Mission: a console screen: near black, a faint plotting grid with brighter major lines, and a vignette.
// Static: the theme draws it once a second.
// Colors: 0 the screen, 1 the grid, 2 the vignette.

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float2 pt = uv * res;
    float minor = res.y / 30.0;
    float2 g = abs(fract(pt / minor + 0.5) - 0.5) * minor;
    float2 G = abs(fract(pt / (minor * 5.0) + 0.5) - 0.5) * minor * 5.0;
    float line = max(1.0 - smoothstep(0.0, 1.0, min(g.x, g.y)) , 0.0) * 0.35 + (1.0 - smoothstep(0.0, 1.2, min(G.x, G.y))) * 0.65;
    float3 col = mix(locky_color(p, 0), locky_color(p, 1), line);
    float2 c = uv - 0.5;
    col = mix(col, locky_color(p, 2), smoothstep(0.35, 0.95, length(c * float2(1.2, 1.0))));
    return float4(col, 1.0);
}
