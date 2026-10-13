// Classic: a 1-bit desktop pattern: black and white pixels in a 2×2 checker, which reads as 50% gray, at the size of
// a 1984 screen's pixels.
// Static: the theme draws it once a second.
// Colors: 0 white, 1 black. Params: 0 pixel size in points at 1440×900 (default 2).

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float cell = max(1.0, locky_param(p, 0, 2.0) * res.y / 900.0);
    float2 i = floor(uv * res / cell);
    float on = fmod(i.x + i.y, 2.0);
    return float4(mix(locky_color(p, 0), locky_color(p, 1), on), 1.0);
}
