// Phosphor: the glass of an amber CRT, after cool-retro-term. A curved screen in a dark bezel, a warm
// center fading to the edges, faint static, and a soft bright band that rolls down the screen.
// Colors: 0 glass center, 1 glass edge, 2 phosphor (the band and the static).
// Params: 0 seconds per band pass (6), 1 band strength (1), 2 static strength (1), 3 curvature (1).

static float ph_hash(float2 p) {
    float3 q = fract(float3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float aspect = res.x / res.y;
    float3 center = locky_color(p, 0), edge = locky_color(p, 1), phosphor = locky_color(p, 2);

    // The curved glass: a barrel bulge, so the screen's corners round off into the bezel.
    float2 c = uv * 2.0 - 1.0;
    float curve = 0.045 * locky_param(p, 3, 1.0);
    float2 d = c * (1.0 + curve * c.yx * c.yx);
    // Distance inside the screen's rounded edge, in units of the screen's height.
    float2 box = (1.0 - abs(d)) * float2(aspect, 1.0) * 0.5;
    float radius = 0.035;
    float2 corner = max(radius - box, 0.0);
    float inside = min(box.x, box.y) < radius ? radius - length(corner) : min(box.x, box.y);
    float screen = smoothstep(0.0, 0.004, inside);

    // The glass: warm in the middle, darker toward the curved edge.
    float r = length(d * float2(1.0, 0.85));
    float3 col = mix(center, edge, smoothstep(0.15, 1.25, r));
    col *= mix(0.55, 1.0, smoothstep(0.0, 0.09, inside));

    // The band: a soft glow that rolls from top to bottom, with a dimmer trail above it.
    float period = max(locky_param(p, 0, 6.0), 0.5);
    float y = 1.2 - fract(t / period) * 1.4;
    float dy = d.y * 0.5 + 0.5 - y;
    float band = exp(-dy * dy * 140.0) + 0.3 * exp(-dy * 7.0) * step(0.0, dy);
    col += phosphor * band * 0.04 * locky_param(p, 1, 1.0);

    // Static: fine grain that changes every frame, tinted by the phosphor.
    float grain = ph_hash(floor(uv * res) + floor(t * 30.0) * float2(17.0, 59.0)) - 0.5;
    col += phosphor * grain * 0.018 * locky_param(p, 2, 1.0);

    // The bezel: near black, with the glass's glow reflected on its inner lip.
    float3 bezel = edge * 0.25 + phosphor * 0.045 * exp(-max(-inside, 0.0) * 70.0);
    col = mix(bezel, col, screen);
    return float4(max(col, 0.0), 1.0);
}
