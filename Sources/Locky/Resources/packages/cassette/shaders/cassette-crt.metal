// CRT overlay for Cassette Futurism: scanlines, a soft vignette, a faint mains flicker, and a slow bright
// scan sweeping down the tube. Drawn over the widgets (not the password field): returns black with a varying
// alpha, so it only darkens — alpha 0 leaves the widget untouched.
float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    // Scanlines: darken the gaps between lines. One line every ~3 screen pixels.
    float s = min(res.x / 1440.0, res.y / 900.0);
    float phase = uv.y * res.y / (3.0 * s);
    float scan = 0.5 + 0.5 * sin(phase * 6.28318);
    float darken = (1.0 - scan) * 0.26;

    // A faint vertical aperture-grille shimmer.
    float grille = 0.06 * (0.5 + 0.5 * sin(uv.x * res.x / (3.0 * s) * 6.28318));

    // Vignette toward the tube's corners (a little curvature implied).
    float2 c = (uv - 0.5) * float2(1.06, 1.0);
    float vig = smoothstep(0.30, 0.75, dot(c, c)) * 0.55;

    // Mains flicker and a slow bright band rolling down.
    float flick = 0.015 * sin(t * 48.0);
    float roll = smoothstep(0.06, 0.0, abs(fract(uv.y + t * 0.08) - 0.5)) * -0.05;

    float a = clamp(darken + grille + vig + flick + roll, 0.0, 0.62);
    return float4(float3(0.0, 0.015, 0.0), a);   // the blacks carry a trace of green
}
