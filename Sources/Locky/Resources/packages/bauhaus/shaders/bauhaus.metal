// Bauhaus: a poster composition on cream paper: a red circle, a blue half disc, a yellow triangle, black bars, and a
// thin circle, after the 1923 exhibition posters. The red circle turns its notch once a minute with the real clock.
// Colors: 0 the paper, 1 red, 2 blue, 3 yellow, 4 black.

static float bauhaus_hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float aspect = res.x / res.y;
    float2 q = float2(uv.x * aspect, uv.y);
    float px = 1.5 / res.y;
    float3 col = locky_color(p, 0);

    // Blue half disc on the bottom edge.
    float2 b = q - float2(0.2 * aspect, 0.0);
    float blue = smoothstep(px, -px, length(b) - 0.36) * step(0.0, b.y);
    col = mix(col, locky_color(p, 2), blue);

    // Yellow triangle, point up.
    float2 a = float2(0.10 * aspect, 0.52), c = float2(0.40 * aspect, 0.52), top = float2(0.25 * aspect, 0.93);
    float2 e0 = c - a, e1 = top - c, e2 = a - top;
    float s0 = (q.x - a.x) * e0.y - (q.y - a.y) * e0.x;
    float s1 = (q.x - c.x) * e1.y - (q.y - c.y) * e1.x;
    float s2 = (q.x - top.x) * e2.y - (q.y - top.y) * e2.x;
    float yellow = (s0 <= 0.0 && s1 <= 0.0 && s2 <= 0.0) ? 1.0 : 0.0;
    col = mix(col, locky_color(p, 3), yellow);

    // Red circle, overprinting: where it meets the blue it darkens, as inks do.
    float2 r = q - float2(0.33 * aspect, 0.42);
    float red = smoothstep(px, -px, length(r) - 0.2);
    float3 ink = locky_color(p, 1) * mix(float3(1.0), locky_color(p, 2) * 1.4, blue * 0.6);
    col = mix(col, ink, red * 0.94);

    // A notch in the red circle that sweeps once a minute, like a second hand.
    float angle = -p.clock / 60.0 * 6.2831853 + 1.5707963;
    float2 dir = float2(cos(angle), sin(angle));
    float along = dot(r, dir), across = abs(r.x * dir.y - r.y * dir.x);
    col = mix(col, locky_color(p, 0), red * step(0.0, along) * step(along, 0.2) * smoothstep(0.012 + px, 0.012, across));

    // Black bars: one long horizontal, one diagonal.
    float bar = step(abs(q.y - 0.18), 0.012) * step(0.05 * aspect, q.x) * step(q.x, 0.55 * aspect);
    float2 d = q - float2(0.47 * aspect, 0.62);
    float diag = step(abs(d.x * 0.5 + d.y * 0.866), 0.009) * step(abs(d.x * 0.866 - d.y * 0.5), 0.22);
    col = mix(col, locky_color(p, 4), max(bar, diag));

    // A thin circle outline.
    float2 o = q - float2(0.12 * aspect, 0.25);
    col = mix(col, locky_color(p, 4), smoothstep(px * 1.5, 0.0, abs(length(o) - 0.07) - 0.003));

    // Paper grain.
    col += (bauhaus_hash(floor(uv * res)) - 0.5) * 0.03;
    return float4(col, 1.0);
}
