// Notebook: a page of a ruled notebook. Blue rules under a wider top margin, a red margin line, three punched holes
// showing the desk, a coffee ring, and the grain of the paper.
// Colors: 0 the paper, 1 the rules, 2 the margin, 3 the desk, 4 the coffee.
// Params: 0 rules per screen height (default 30), 1 the margin's distance from the left, as a fraction of the width
// (default 0.11).

static float notebook_hash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

static float notebook_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(notebook_hash(i), notebook_hash(i + float2(1, 0)), f.x),
               mix(notebook_hash(i + float2(0, 1)), notebook_hash(i + float2(1, 1)), f.x), f.y);
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float2 px = float2(uv.x, 1.0 - uv.y) * res;  // from the top-left, in pixels
    float unit = res.y / 1000.0;
    float spacing = res.y / locky_param(p, 0, 30.0);
    float3 col = locky_color(p, 0);

    // Paper: fibers and grain, a little darker toward the edges.
    col *= 0.985 + 0.015 * notebook_noise(px / unit * float2(0.05, 0.2));
    col += (notebook_hash(px) - 0.5) * 0.02;

    // The rules, below a top margin of three.
    float row = px.y / spacing;
    if (row > 3.0) {
        float d = abs(fract(row + 0.5) - 0.5) * spacing;
        col = mix(col, locky_color(p, 1), (1.0 - smoothstep(0.6 * unit, 1.6 * unit, d)) * 0.55);
    }
    // The margin: two thin red lines.
    float m = res.x * locky_param(p, 1, 0.11);
    float dm = min(abs(px.x - m), abs(px.x - m - 5.0 * unit));
    col = mix(col, locky_color(p, 2), (1.0 - smoothstep(0.6 * unit, 1.6 * unit, dm)) * 0.6);

    // A coffee ring: an uneven brown edge and a faint stain inside.
    float2 cup = float2(0.84 * res.x, 0.8 * res.y);
    float2 dc = px - cup;
    float angle = atan2(dc.y, dc.x);
    float radius = 92.0 * unit * (1.0 + 0.03 * sin(angle * 3.0) + 0.02 * notebook_noise(float2(angle * 4.0, 1.0)));
    float ring = exp(-pow((length(dc) - radius) / (4.0 * unit), 2.0)) * (0.5 + 0.5 * notebook_noise(float2(angle * 6.0, 3.0)));
    float stain = (1.0 - smoothstep(radius - 6.0 * unit, radius, length(dc))) * 0.08;
    col = mix(col, locky_color(p, 4), clamp(ring * 0.45 + stain * 1.5, 0.0, 1.0));

    // Three punched holes, with a shadow on their upper edge.
    float holeX = res.x * 0.035;
    for (int i = 0; i < 3; i++) {
        float2 h = px - float2(holeX, res.y * (0.18 + 0.32 * float(i)));
        float r = 15.0 * unit;
        float inside = 1.0 - smoothstep(r - 1.0, r + 1.0, length(h));
        float shade = smoothstep(-r, r, h.y) * 0.5 + 0.5;
        col = mix(col, locky_color(p, 3) * shade, inside);
        col *= 1.0 - 0.15 * exp(-pow((length(h) - r) / (2.0 * unit), 2.0));
    }

    float2 c = uv - 0.5;
    col *= 1.0 - 0.18 * dot(c, c);
    return float4(col, 1.0);
}
