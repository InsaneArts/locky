// Observatory: the night sky turning slowly around the pole, the Milky Way across it, and an observatory's dome on
// a dark hill with one warm window.
// Colors: 0 the sky overhead, 1 the sky at the horizon, 2 the glow low on the horizon, 3 the Milky Way, 4 the ground,
// 5 the window.
// Params: 0 how fast the sky turns (default 1), 1 star density (default 1).

static float observatory_hash(float2 p) {
    p = fract(p * float2(127.1, 311.7));
    p += dot(p, p + 34.123);
    return fract(p.x * p.y);
}

static float observatory_noise(float2 p) {
    float2 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
    return mix(mix(observatory_hash(i), observatory_hash(i + float2(1, 0)), u.x),
               mix(observatory_hash(i + float2(0, 1)), observatory_hash(i + float2(1, 1)), u.x), u.y);
}

static float observatory_stars(float2 r, float scale, float density, float t, float px) {
    float2 g = r * scale;
    float2 cell = floor(g), f = fract(g) - 0.5;
    float h = observatory_hash(cell);
    if (h < 1.0 - 0.09 * density) return 0.0;
    float2 at = float2(observatory_hash(cell + 1.7), observatory_hash(cell + 9.2)) - 0.5;
    float d = length(f - at * 0.7) / scale;
    float size = px * (0.8 + 1.6 * observatory_hash(cell + 4.4));
    float twinkle = 0.75 + 0.25 * sin(t * (1.5 + 3.0 * h) + h * 60.0);
    return smoothstep(size, 0.0, d) * twinkle * (0.4 + 0.6 * observatory_hash(cell + 2.9));
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float aspect = res.x / res.y;
    float2 q = float2(uv.x * aspect, uv.y);
    float px = 1.0 / res.y;

    float3 col = mix(locky_color(p, 1), locky_color(p, 0), smoothstep(0.05, 0.9, uv.y));
    col += locky_color(p, 2) * exp(-uv.y * 9.0) * 0.6;

    // The sky turns around a pole above the top of the screen.
    float a = t * 0.004 * locky_param(p, 0, 1.0);
    float2 pole = float2(0.42 * aspect, 1.15);
    float2 d = q - pole;
    float2 r = float2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a));

    // The Milky Way: a soft band of mottled light.
    float band = r.x * 0.62 + r.y * 0.78 + 0.55;
    float milky = exp(-band * band * 22.0);
    float cloud = observatory_noise(r * 6.0) * 0.55 + observatory_noise(r * 14.0) * 0.3 + observatory_noise(r * 31.0) * 0.15;
    col += locky_color(p, 3) * milky * smoothstep(0.35, 0.95, cloud) * 0.22;

    float density = locky_param(p, 1, 1.0);
    float stars = observatory_stars(r, 38.0, density, t, px * 1.6) + observatory_stars(r, 90.0, density * 1.6, t, px * 1.1)
                + observatory_stars(r + 3.1, 170.0, density * (1.0 + 2.5 * milky), t, px * 0.9) * 0.8;
    col += float3(1.0, 0.97, 0.92) * stars * smoothstep(0.08, 0.3, uv.y);

    // The hill, and the dome on it.
    float x = uv.x;
    float hill = 0.115 + 0.035 * sin(x * 3.1 + 0.4) + 0.018 * sin(x * 7.7 + 1.3) + 0.006 * sin(x * 23.0);
    float2 domeAt = float2(0.8 * aspect, 0.115 + 0.035 * sin(0.8 * 3.1 + 0.4) + 0.018 * sin(0.8 * 7.7 + 1.3) + 0.006 * sin(0.8 * 23.0));
    float2 dq = q - domeAt;
    float domeR = 0.045;
    bool dome = (length(dq) < domeR && dq.y > 0.0) || (abs(dq.x) < domeR && dq.y > -0.03 && dq.y <= 0.0);
    float3 ground = locky_color(p, 4);
    if (uv.y < hill || dome) {
        col = ground;
        // The slit in the dome, and a warm window in its wall.
        if (dome && abs(dq.x - 0.006) < 0.004 && dq.y > 0.012 && length(dq) < domeR - 0.004) col = ground * 1.6;
        if (dome && abs(dq.x + 0.018) < 0.006 && dq.y > -0.022 && dq.y < -0.01) col = locky_color(p, 5);
    }
    col += locky_color(p, 5) * exp(-length(dq - float2(-0.018, -0.016)) * 70.0) * 0.25;
    col += (observatory_hash(floor(uv * res)) - 0.5) * 0.012;
    return float4(col, 1.0);
}
