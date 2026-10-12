// Synthwave overlay: faint scanlines over the scene and the widgets (the password field stays above them).
// Static, so it runs at the lowest frame rate. Params: 0 line period in points (3), 1 darkness (0.18).

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    // The period in whole pixels, so every line falls on the pixel grid the same way.
    float period = max(2.0, round(locky_param(p, 0, 3.0) * min(res.x / 1440.0, res.y / 900.0)));
    float phase = fract((1.0 - uv.y) * res.y / period);
    float line = smoothstep(0.3, 0.5, phase) * (1.0 - smoothstep(0.8, 1.0, phase));
    return float4(0.0, 0.0, 0.0, line * locky_param(p, 1, 0.18));
}
