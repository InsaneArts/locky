// Vaporwave: a dreamy pastel sky with a soft banded sun, a faint perspective floor grid, and gentle VHS
// scanlines. Softer and more faded than synthwave. Colors: 0 sky top, 1 sky low, 2 floor, 3 sun, 4 grid.
// Params: 0 horizon (points from top, 580), 1 grid speed (0.22).
static float vw_n(float2 p) { return fract(sin(dot(p, float2(12.99, 78.23))) * 43758.5453); }

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float s = min(res.x / 1440.0, res.y / 900.0);
    float2 P = float2((uv.x - 0.5) * res.x, (1.0 - uv.y) * res.y) / s;
    float px = 1.0 / s;
    float horizon = locky_param(p, 0, 580.0);
    float speed = locky_param(p, 1, 0.22);
    float3 top = locky_color(p, 0), low = locky_color(p, 1), floorc = locky_color(p, 2), sun = locky_color(p, 3), grid = locky_color(p, 4);

    float dy = P.y - horizon;
    float3 col;
    if (dy < 0.0) {
        float k = clamp(P.y / horizon, 0.0, 1.0);
        col = mix(top, low, smoothstep(0.0, 1.0, k));                 // soft pastel sky
        // A soft banded sun sitting on the horizon.
        float sunY = horizon - 110.0, R = 155.0;
        float d = length(float2(P.x, P.y - sunY));
        float disc = smoothstep(R, R - 50.0, d);
        float v = (P.y - sunY) / R;                                  // -1 top .. 1 bottom of sun
        float band = smoothstep(0.0, 1.0, fract(v * 7.0));           // horizontal gaps, widening low
        float gaps = smoothstep(-0.2, 0.9, v);
        float3 sunc = mix(sun, mix(sun, low, 0.7), band * gaps);
        col = mix(col, sunc, disc);
        col += sun * 0.22 * exp(-max(d - R, 0.0) / 130.0);           // glow
    } else {
        col = mix(floorc, low, exp(-dy / 150.0));
        float camera = 3.0, focal = 600.0, ground = max(dy, 0.5);
        float2 g = float2(P.x * camera / ground, focal * camera / ground + fract(t * speed));
        float2 fw = fwidth(g);
        float2 dpx = abs(fract(g + 0.5) - 0.5) / max(fw, float2(1e-5));
        float2 lines = 1.0 - smoothstep(0.5, 1.8, dpx);
        float fog = exp(-dy / 90.0);
        col += grid * (lines.x + lines.y) * 0.22 * (1.0 - fog * 0.4);
    }

    // The horizon glow.
    col += sun * exp(-abs(dy) / 24.0) * 0.18;
    // Gentle VHS scanlines and a faint chroma bleed at the sides.
    col *= 0.92 + 0.08 * sin(P.y / (2.2 * px) * 6.28318);
    float ch = abs(uv.x - 0.5) * 0.02;
    col.r += ch; col.b += ch * 0.6;
    // Vignette + dither.
    float2 cc = uv - 0.5;
    col *= 1.0 - dot(cc, cc) * 0.42;
    col += (vw_n(uv * res + fract(t)) - 0.5) / 255.0;
    return float4(col, 1.0);
}
