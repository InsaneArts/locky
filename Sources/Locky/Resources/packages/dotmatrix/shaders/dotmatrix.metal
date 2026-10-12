// Dot Matrix: faint dots on black, like the unlit pixels of a dot-matrix panel. The columns line up with
// the screen's center and the rows with the top edge, so the clock's 24-point dots sit on every other one.
// Colors: 0 background, 1 dots. Params: 0 pitch in points (12), 1 dot diameter in points (1.5), 2 opacity (0.04).

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    // Pixels per layout point: Locky lays themes out for 1440x900 points and scales them to the screen.
    float scale = min(res.x / 1440.0, res.y / 900.0);
    float pitch = locky_param(p, 0, 12.0) * scale;
    float radius = locky_param(p, 1, 1.5) * scale * 0.5;
    float opacity = locky_param(p, 2, 0.04);

    // Grid units: x from the screen's center, y from the top edge with dot centers half a pitch down.
    float2 grid = float2(uv.x * res.x - res.x * 0.5, (1.0 - uv.y) * res.y) / pitch - float2(0.0, 0.5);
    float d = length((grid - round(grid)) * pitch);
    float mask = 1.0 - smoothstep(radius - 0.5, radius + 0.5, d);
    return float4(mix(locky_color(p, 0), locky_color(p, 1), mask * opacity), 1.0);
}
