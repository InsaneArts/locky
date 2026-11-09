// Kanagawa: a stylized Great Wave — flat indigo bands with white foam, scrolling under a calm ink sky.
// Woodblock-flat, not photoreal. Colors: 0 sky (sumiInk), 1 wave back, 2 wave mid, 3 wave front/crest, 4 foam.
// Params: 0 waterline (points from top, 320), 1 speed (1.0).
static float kw_n(float2 p) { return fract(sin(dot(p, float2(41.3, 289.1))) * 43758.5453); }
static float kw_crest(float x, float t, float amp, float freq, float sp, float ph) {
    return amp * (0.62 * sin(x * freq + t * sp + ph) + 0.38 * sin(x * freq * 2.3 + t * sp * 1.3 + ph * 2.0 + 1.0));
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float s = min(res.x / 1440.0, res.y / 900.0);
    float2 P = float2((uv.x - 0.5) * res.x, (1.0 - uv.y) * res.y) / s;   // points, x from center, y down from top
    float px = 1.0 / s;
    float wl = locky_param(p, 0, 320.0);
    float spd = locky_param(p, 1, 1.0);
    float3 sky = locky_color(p, 0), c1 = locky_color(p, 1), c2 = locky_color(p, 2), c3 = locky_color(p, 3), foam = locky_color(p, 4);

    // Sky: a touch lighter at the top, a faint ink speckle.
    float3 col = mix(sky * 1.16, sky * 0.97, smoothstep(0.0, wl, P.y));
    float2 cell = floor(P / 7.0);
    if (kw_n(cell) > 0.985) col += foam * 0.12 * (1.0 - smoothstep(0.0, wl * 0.8, P.y));

    // Four wave layers, back (near the waterline) to front (down the screen).
    float amps[4]  = { 9.0, 14.0, 19.0, 25.0 };
    float offs[4]  = { 0.0, 60.0, 140.0, 236.0 };
    float freqs[4] = { 0.030, 0.024, 0.019, 0.0155 };
    float sps[4]   = { 0.45, 0.65, 0.9, 1.15 };
    float phs[4]   = { 0.0, 1.7, 3.1, 4.6 };
    float3 cols[4];
    cols[0] = mix(c1, sky, 0.30); cols[1] = c1; cols[2] = c2; cols[3] = c3;

    for (int i = 0; i < 4; i++) {
        float crest = wl + offs[i] + kw_crest(P.x, t * spd, amps[i], freqs[i], sps[i], phs[i]);
        float below = P.y - crest;                                  // > 0 under this wave's surface
        col = mix(col, cols[i], smoothstep(-px, px, below));        // flat fill
        // A foam line riding the crest, and a few curl dots just under it.
        col += foam * (1.0 - smoothstep(0.0, 3.0 * px + 2.0, abs(below))) * 0.95;
        float curl = step(0.0, below) * step(below, 16.0) * step(0.88, kw_n(floor(float2(P.x / 12.0, float(i)))));
        col = mix(col, foam, curl * (1.0 - smoothstep(0.0, 5.0, abs(below - 8.0))) * 0.8);
    }

    float2 cc = uv - 0.5;
    col *= 1.0 - dot(cc, cc) * 0.5;                                  // vignette
    col += (kw_n(uv * res + fract(t)) - 0.5) / 255.0;               // dither
    return float4(col, 1.0);
}
