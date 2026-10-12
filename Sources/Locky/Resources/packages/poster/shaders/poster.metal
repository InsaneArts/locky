// Poster: uncoated paper. A warm off-white with a fine static grain, a coarser fiber, and a faint
// unevenness in tone. Nothing here depends on time, so the theme draws it once a second (fps 1).
// Colors: 0 the paper. Params: 0 grain strength (default 0.035).

static float poster_hash(float2 p) {
    p = fract(p * float2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}

static float poster_noise(float2 p) {
    float2 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
    return mix(mix(poster_hash(i), poster_hash(i + float2(1, 0)), u.x),
               mix(poster_hash(i + float2(0, 1)), poster_hash(i + float2(1, 1)), u.x), u.y);
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float3 paper = locky_color(p, 0);
    float grain = locky_param(p, 0, 0.035);
    float2 px = floor(uv * res);
    float aspect = res.x / res.y;
    float2 q = float2(uv.x * aspect, uv.y);

    // Fine grain per pixel, a coarser fiber over 3-pixel cells, and a slow unevenness in tone.
    float fine = poster_hash(px) - 0.5;
    float fiber = poster_hash(floor(px / 3.0) + 31.0) - 0.5;
    float tone = poster_noise(q * 2.2) * 0.65 + poster_noise(q * 7.0 + 3.7) * 0.35 - 0.5;
    float3 col = paper * (1.0 + fine * grain + fiber * grain * 0.45 + tone * 0.022);

    // The light falls off a little toward the corners, as on a poster on a wall.
    float2 c = uv - 0.5;
    col *= 1.0 - dot(c, c) * 0.07;
    return float4(col, 1.0);
}
