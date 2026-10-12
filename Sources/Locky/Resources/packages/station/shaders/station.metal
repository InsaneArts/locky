// Station: a warm gray wall, lit softly around the clock, with a faint plaster mottle and a fine grain.
// Static: nothing here depends on time, so the theme draws it once a second (fps 1).
// Colors: 0 the wall, 1 the light around the clock, 2 the shade in the corners.
// Params: 0 grain strength (default 0.012), 1 height of the light's center, 0 bottom to 1 top (default 0.56).

static float station_hash(float2 p) {
    p = fract(p * float2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}

static float station_noise(float2 p) {
    float2 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
    return mix(mix(station_hash(i), station_hash(i + float2(1, 0)), u.x),
               mix(station_hash(i + float2(0, 1)), station_hash(i + float2(1, 1)), u.x), u.y);
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float aspect = res.x / res.y;
    float2 q = float2((uv.x - 0.5) * aspect, uv.y - locky_param(p, 1, 0.56));
    float d = length(q * float2(0.82, 1.0));

    float3 wall = locky_color(p, 0);
    float3 light = locky_color(p, 1);
    float3 corner = locky_color(p, 2);
    float3 col = mix(light, wall, smoothstep(0.18, 0.78, d));
    col = mix(col, corner, smoothstep(0.62, 1.35, d));

    // Plaster: a slow, faint mottle, so the wall is not a flat print.
    float2 w = float2(uv.x * aspect, uv.y);
    float mottle = station_noise(w * 3.0) * 0.6 + station_noise(w * 9.0 + 7.3) * 0.4;
    col *= 1.0 + (mottle - 0.5) * 0.018;

    // Grain, one value per drawn pixel.
    col += (station_hash(floor(uv * res)) - 0.5) * locky_param(p, 0, 0.012);
    return float4(col, 1.0);
}
