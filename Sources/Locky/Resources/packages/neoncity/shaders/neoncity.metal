// Neon City: a city at 2 AM in the rain, seen from high up. Three rows of towers drift slowly past, the far ones lost
// in haze; windows glow and now and then go dark, neon signs buzz on the near towers, red lights blink on the roofs,
// flying cars cross, and rain streaks over all of it.
// Positions are in layout points (x from the center, y down from the top).
// Colors: 0 the sky's top, 1 the haze, 2 warm windows, 3 neon pink, 4 neon cyan, 5 the towers.
// Params: 0 how fast the city drifts (1), 1 how much rain (1).

static float nc_hash(float2 p) {
    p = fract(p * float2(127.619, 157.231));
    p += dot(p, p + 41.87);
    return fract(p.x * p.y);
}

static float nc_hash1(float n) { return fract(sin(n * 78.233) * 43758.5453); }

struct NCLayer {
    float width;     // a tower's slot, in points
    float lo, hi;    // tower heights, points above the bottom
    float shift;     // how far it has drifted
    float seed;
    float haze;      // 0 near .. 1 lost in the haze
    float window;    // window size, points
};

// A tower's neon sign, if it has one: where it is (its center and half its size) and its color. Near rows have more.
static bool nc_sign(float slot, NCLayer L, float top, float inset, thread float2 &center, thread float2 &extent, thread float3 &neon,
                    constant LockyParams &p) {
    if (L.haze > 0.6 || nc_hash1(slot + 21.0 + L.seed) < (L.haze < 0.2 ? 0.4 : 0.65)) return false;
    neon = nc_hash1(slot + 33.0 + L.seed) > 0.5 ? locky_color(p, 3) : locky_color(p, 4);
    float scale = L.haze < 0.2 ? 1.0 : 0.6;
    if (nc_hash1(slot + 66.0 + L.seed) > 0.5) {
        // A tall sign hanging on the face.
        extent = float2(L.width * 0.05 + 2.0, (60.0 + 45.0 * nc_hash1(slot + 55.0)) * scale);
        center = float2(inset + L.width * 0.2, top + 40.0 * scale + extent.y + 50.0 * nc_hash1(slot + 44.0));
    } else {
        // A wide sign across the face, below the roof.
        extent = float2(L.width * 0.5 - inset - 6.0, 9.0 * scale + 4.0);
        center = float2(L.width * 0.5, top + 24.0 + 30.0 * nc_hash1(slot + 77.0));
    }
    return true;
}

// One row of towers: the color it paints at P, and how much of it covers P (0 or 1, anti-aliased). Where it does not
// cover P, the color is light to add: neon glow and the blinking lights on the masts.
static float4 nc_towers(float2 P, NCLayer L, float t, float px, constant LockyParams &p) {
    float x = P.x + L.shift;
    float slot = floor(x / L.width);
    float h1 = nc_hash1(slot * 1.37 + L.seed);
    float top = 900.0 - mix(L.lo, L.hi, h1 * h1);
    // Towers are narrower than their slot, so the row is not a wall.
    float inset = L.width * (0.06 + 0.16 * nc_hash1(slot + L.seed * 3.1));
    float fx = x - slot * L.width;
    float inside = smoothstep(inset - px, inset + px, fx) * smoothstep(L.width - inset + px, L.width - inset - px, fx);
    // A setback: the top fifth steps in on one side.
    float ledge = top + (900.0 - top) * 0.2;
    float stepIn = nc_hash1(slot + 9.0 + L.seed) > 0.5 ? L.width * 0.2 : 0.0;
    inside *= (P.y > ledge || (fx > inset + stepIn && fx < L.width - inset)) ? 1.0 : 0.0;
    float roof = (fx > inset + stepIn) ? top : ledge;
    inside *= smoothstep(roof - px, roof + px, P.y);

    float2 center, extent;
    float3 neon;
    bool sign = nc_sign(slot, L, top, inset, center, extent, neon, p);
    float buzz = 1.0 - 0.6 * step(0.93, nc_hash1(floor(t * 8.0) + slot * 3.0)) * step(0.7, nc_hash1(slot + 88.0));
    float3 glow = float3(0.0);
    float inSign = 0.0;
    if (sign) {
        float2 d2 = abs(float2(fx, P.y) - center) - extent;
        float d = length(max(d2, 0.0)) + min(max(d2.x, d2.y), 0.0);
        inSign = smoothstep(px, -px, d);
        glow = neon * exp(-max(d, 0.0) / 14.0) * 0.55 * buzz * (1.0 - L.haze * 0.5);
    }

    if (inside <= 0.0) {
        // A blinking red light on the masts of tall towers.
        float tall = h1 > 0.6 ? 1.0 : 0.0;
        float2 tip = float2(slot * L.width + L.width * 0.5 - L.shift, top - 22.0);
        float blink = fract(t * 0.5 + h1 * 7.0) > 0.5 ? 1.0 : 0.0;
        float d = length(P - tip);
        float mast = tall * (abs(P.x - tip.x) < 0.9 && P.y > tip.y && P.y < top ? 1.0 : 0.0);
        float3 light = float3(1.0, 0.15, 0.1) * exp(-d * d / 7.0) * tall * blink * (1.0 - L.haze * 0.6);
        return float4(light + glow * 0.7, mast * (1.0 - L.haze * 0.6));
    }

    float3 col = locky_color(p, 5) * (1.0 + 0.4 * h1) + locky_color(p, 1) * 0.05;
    // Windows: a grid in floors; whole floors stay dark, a few windows go dark and light up again.
    float2 w = float2(fx - inset, P.y - top) / L.window;
    float2 cell = floor(w);
    float2 f = fract(w);
    float floorLit = nc_hash(float2(cell.y, slot + L.seed)) > 0.3 ? 1.0 : 0.0;
    float lit = nc_hash(cell + slot * 17.0 + L.seed);
    float flick = nc_hash(cell + floor(t * 0.3 + lit * 10.0) + slot) > 0.99 ? 1.0 : 0.0;
    float on = (lit > 0.62 ? 1.0 : 0.0) * floorLit * (1.0 - flick);
    float pane = smoothstep(0.12, 0.22, f.x) * smoothstep(0.88, 0.78, f.x) * smoothstep(0.2, 0.3, f.y) * smoothstep(0.8, 0.7, f.y);
    float3 light = mix(locky_color(p, 2), float3(0.7, 0.88, 1.0), nc_hash(cell + 3.3 + slot) > 0.8 ? 1.0 : 0.0);
    col += light * pane * on * (0.35 + 0.5 * nc_hash(cell + 5.5)) * (1.0 - L.haze * 0.7);

    // The neon sign: bright letters on a darker panel, and its light on the face around it.
    if (sign) {
        // Letters: each a 3 by 5 grid of random bits, read across a wide sign or down a tall one.
        float2 local = float2(fx, P.y) - center + extent;
        bool tall = extent.y > extent.x;
        float2 size = tall ? float2(extent.x * 2.0, 20.0) : float2(14.0, extent.y * 2.0);
        float2 inChar = tall ? float2(local.x / size.x, fract(local.y / size.y)) : float2(fract(local.x / size.x), local.y / size.y);
        float index = tall ? floor(local.y / size.y) : floor(local.x / size.x);
        float2 bit = floor((inChar - float2(0.12, 0.12)) / float2(0.76, 0.76) * float2(3.0, 5.0));
        float inside = all(bit >= 0.0) && all(bit < float2(3.0, 5.0)) ? 1.0 : 0.0;
        float letters = inside * (nc_hash(bit + index * 7.0 + slot * 13.0) > 0.45 ? 1.0 : 0.0);
        col = mix(col, neon * (0.25 + 1.1 * letters) * buzz, inSign);
        col += glow * (1.0 - inSign);
    }
    // Haze: far rows fade into the city's glow.
    col = mix(col, locky_color(p, 1) * 0.9, L.haze * 0.72);
    return float4(col, inside);
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float s = min(res.x / 1440.0, res.y / 900.0);
    float2 P = float2((uv.x - 0.5) * res.x, (1.0 - uv.y) * res.y) / s;
    float px = 1.0 / s;
    float drift = locky_param(p, 0, 1.0);
    float rain = locky_param(p, 1, 1.0);
    float bottom = res.y / s;      // the screen's height in points; towers stand on it
    P.y += 900.0 - bottom;         // keep the skyline on the bottom edge on tall screens

    // Sky: dark at the top, the city's pink-violet glow near the ground.
    float k = clamp(P.y / 900.0, 0.0, 1.0);
    float3 col = mix(locky_color(p, 0), locky_color(p, 1), pow(k, 1.8));
    col += locky_color(p, 3) * 0.10 * pow(k, 3.0);
    // Two searchlights sweeping slowly from the streets.
    for (int i = 0; i < 2; i++) {
        float2 base = float2(i == 0 ? -420.0 : 380.0, 900.0);
        float angle = (i == 0 ? 0.25 : -0.3) + 0.22 * sin(t * (i == 0 ? 0.11 : 0.08) + i * 2.0);
        float2 dir = float2(sin(angle), -cos(angle));
        float2 d = P - base;
        float along = dot(d, dir), across = abs(dot(d, float2(-dir.y, dir.x)));
        float beam = exp(-across / (6.0 + along * 0.05)) * smoothstep(0.0, 200.0, along) * exp(-along / 700.0);
        col += mix(locky_color(p, 4), float3(1.0), 0.4) * beam * 0.13;
    }

    NCLayer layers[3] = {
        { 48.0, 250.0, 560.0, t * 3.0 * drift, 1.0, 0.85, 7.0 },
        { 78.0, 170.0, 640.0, t * 6.0 * drift + 400.0, 2.0, 0.45, 9.0 },
        { 130.0, 90.0, 470.0, t * 11.0 * drift + 900.0, 3.0, 0.0, 12.0 },
    };
    for (int i = 0; i < 3; i++) {
        float4 tower = nc_towers(P, layers[i], t, px, p);
        col = mix(col, tower.rgb, tower.a);
        if (tower.a == 0.0) col += tower.rgb;
        // Mist between rows.
        col = mix(col, locky_color(p, 1), 0.08 * smoothstep(0.55, 1.0, k));
    }

    // Flying cars: lights in lanes, crossing both ways, with a short trail.
    for (int lane = 0; lane < 4; lane++) {
        float y = 300.0 + lane * 70.0 + 20.0 * nc_hash1(lane);
        float dir = lane % 2 == 0 ? 1.0 : -1.0;
        float speed = 90.0 + 50.0 * nc_hash1(lane + 7.0);
        float spacing = 900.0;
        float x = fract((P.x * dir + t * speed) / spacing) * spacing;
        float d = length(float2(min(x, spacing - x) < 0.0 ? 0.0 : x - spacing * 0.5, P.y - y));
        float trail = smoothstep(0.0, 80.0, spacing * 0.5 - x) * step(x, spacing * 0.5) * exp(-pow((P.y - y) / 1.2, 2.0));
        float3 tint = lane % 2 == 0 ? float3(1.0, 0.85, 0.7) : float3(1.0, 0.25, 0.3);
        col += tint * (exp(-d * d / 5.0) * 1.2 + trail * 0.25 * smoothstep(spacing * 0.5 - 90.0, spacing * 0.5, x));
    }

    // Rain: thin streaks falling at a slant, in two depths.
    for (int layer = 0; layer < 2; layer++) {
        float size = layer == 0 ? 9.0 : 15.0;
        float2 r = float2(P.x + P.y * 0.18, P.y);
        float2 g = float2(r.x / size, r.y / (size * 9.0) - t * (layer == 0 ? 3.2 : 4.5));
        float2 cell = floor(g);
        float2 f = fract(g);
        float h = nc_hash(cell + layer * 19.0);
        float show = step(1.0 - 0.18 * rain, h);
        float streak = exp(-pow((f.x - 0.5) * size / 0.6, 2.0)) * smoothstep(0.0, 0.3, f.y) * smoothstep(1.0, 0.5, f.y);
        col += float3(0.7, 0.75, 0.95) * streak * show * (layer == 0 ? 0.12 : 0.22);
    }

    // Vignette, and a little grain so the dark sky does not band.
    float2 c = uv - 0.5;
    col *= 1.0 - 0.5 * dot(c, c);
    col += (nc_hash(P * 0.7 + fract(t)) - 0.5) * 0.015;
    return float4(max(col, 0.0), 1.0);
}
