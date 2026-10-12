// Phosphor's overlay: scanlines, a light vignette, and a faint flicker over everything, text included.
// It only darkens, and only a little, so the text stays crisp.
// Params: 0 scanlines across the screen's height (300), 1 scanline strength (0.16), 2 vignette strength
// (0.4), 3 flicker strength (1).

static float pho_hash(float x) {
    return fract(sin(x * 91.3458) * 47453.5453);
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    // A whole number of pixels per scanline, so the lines never beat against the display's pixels.
    float pitch = max(2.0, round(res.y / locky_param(p, 0, 300.0)));
    float phase = fract(uv.y * res.y / pitch);
    float gap = smoothstep(0.25, 0.5, abs(phase - 0.5));
    float alpha = gap * locky_param(p, 1, 0.16);

    // The vignette: the corners of the tube fall off.
    float2 c = uv * 2.0 - 1.0;
    float v = smoothstep(0.75, 1.7, length(c * float2(1.0, 1.1)));
    alpha = alpha + (1.0 - alpha) * v * locky_param(p, 2, 0.4);

    // The flicker: the tube's brightness wavers by a few percent, at random, several times a second.
    float flicker = (pho_hash(floor(t * 12.0)) - 0.5) * locky_param(p, 3, 1.0);
    alpha = clamp(alpha * (1.0 + flicker * 0.12) + max(flicker, 0.0) * 0.012, 0.0, 1.0);
    return float4(0.02, 0.008, 0.0, alpha);
}
