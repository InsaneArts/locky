// Lookout: layered ridges fading into haze, a fire lookout on the near ridge, pines, and birds crossing. The light
// follows the real time of day: the sun rises at six and sets at six, the sky goes from dawn pink to day gold to
// dusk orange, and at night the ridges turn blue, stars come out, and the lookout's window is lit.
// Positions are in layout points (x from the center, y down from the top).
// Colors: 0 the sky's top at dusk, 1 the sky at the horizon, 2 the far ridges, 3 the near ridges, 4 the sun.
// Params: 0 the hour to show (-1, the default: the real time), 1 how many birds (1).

static float lo_sq(float x) { return x * x; }

static float lo_hash(float2 p) {
    p = fract(p * float2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

static float lo_noise1(float x) {
    float i = floor(x), f = fract(x);
    float u = f * f * (3.0 - 2.0 * f);
    return mix(lo_hash(float2(i, 0.0)), lo_hash(float2(i + 1.0, 0.0)), u);
}

// A ridge line: y (points from the top) at x, for layer i of 6 (0 the farthest).
static float lo_ridge(float x, int i) {
    float fi = float(i);
    float base = 470.0 + fi * 58.0;
    float scale = 260.0 - fi * 22.0;
    float h = 0.0, a = 1.0, f = 1.0 / scale;
    for (int o = 0; o < 4; o++) {
        h += a * (lo_noise1(x * f + fi * 17.3 + o * 5.1) - 0.5);
        a *= 0.45;
        f *= 2.3;
    }
    return base - h * (90.0 + fi * 10.0);
}

// The day's light: 0 night, 1 full day, and a warmth that peaks at sunrise and sunset.
static float2 lo_light(float hour) {
    float day = smoothstep(5.0, 7.5, hour) * (1.0 - smoothstep(17.0, 19.5, hour));
    float warm = exp(-lo_sq((hour - 6.6) / 1.1)) + exp(-lo_sq((hour - 18.2) / 1.2));
    return float2(day, clamp(warm, 0.0, 1.0));
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float s = min(res.x / 1440.0, res.y / 900.0);
    float2 P = float2((uv.x - 0.5) * res.x, (1.0 - uv.y) * res.y) / s;
    float px = 1.0 / s;
    float fixedHour = locky_param(p, 0, -1.0);
    float hour = fixedHour >= 0.0 ? fixedHour : p.clock / 3600.0;
    float birds = locky_param(p, 1, 1.0);
    float2 light = lo_light(hour);
    float day = light.x, warm = light.y;

    float3 duskTop = locky_color(p, 0), duskLow = locky_color(p, 1);
    float3 far = locky_color(p, 2), near = locky_color(p, 3), sunColor = locky_color(p, 4);
    // The palette is dusk's; day and night are worked out from it.
    float3 nightTop = float3(0.02, 0.03, 0.08), nightLow = float3(0.08, 0.1, 0.2);
    float3 dayTop = float3(0.36, 0.56, 0.78), dayLow = float3(0.98, 0.86, 0.66);
    float3 top = mix(mix(nightTop, dayTop, day), duskTop, warm * 0.85);
    float3 low = mix(mix(nightLow, dayLow, day), duskLow, warm * 0.9);

    // The sun's arc: from the left at six to the right at six, highest at noon.
    float arc = clamp((hour - 6.0) / 12.0, -0.1, 1.1);
    float2 sun = float2(mix(-560.0, 560.0, arc), 500.0 - sin(clamp(arc, 0.0, 1.0) * 3.14159) * 360.0 + max(-arc, arc - 1.0) * 600.0);
    float k = clamp(P.y / 620.0, 0.0, 1.0);
    float3 col = mix(top, low, pow(k, 1.4));
    float sd = length(P - sun);
    col += sunColor * (0.55 * exp(-sd / 160.0) + 0.25 * exp(-sd / 520.0)) * max(day, warm);
    col = mix(col, mix(sunColor, float3(1.0, 0.99, 0.95), 0.4 + 0.5 * day * (1.0 - warm)), smoothstep(46.0, 44.0, sd) * max(day, warm));

    // Stars and the moon at night.
    float night = 1.0 - max(day, warm * 0.8);
    float2 cell = floor(P / 6.0);
    float h = lo_hash(cell);
    float2 c = (cell + 0.3 + 0.4 * float2(lo_hash(cell + 1.0), lo_hash(cell + 2.0))) * 6.0;
    col += float3(0.9, 0.92, 1.0) * step(0.965, h) * 1.3 * exp(-length(P - c) * length(P - c) * 1.5) * night * (1.0 - k)
         * (0.6 + 0.4 * sin(t * (1.0 + h * 2.0) + h * 30.0));
    float2 moon = float2(140.0, 150.0);
    float md = length(P - moon);
    col += float3(0.85, 0.9, 1.0) * (smoothstep(26.0, 24.5, md) * 0.85 + 0.12 * exp(-md / 90.0)) * night * night * night;

    // Birds: a loose flock crossing slowly, wings beating.
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        if (fi >= birds * 7.0) break;
        float cycle = 70.0;
        float x = -800.0 + fract((t + fi * 1.7) / cycle) * 1700.0 + lo_hash(float2(fi, 4.0)) * 120.0;
        float y = 260.0 + lo_hash(float2(fi, 9.0)) * 90.0 + sin(t * 0.4 + fi) * 6.0;
        float2 b = P - float2(x, y);
        float flap = sin(t * 7.0 + fi * 2.0) * 0.6;
        float wing = abs(b.y + abs(b.x) * (0.45 - flap * 0.5)) - 0.8;
        float bird = smoothstep(px, -px, wing) * step(abs(b.x), 6.0 + fi * 0.2);
        col = mix(col, near * 0.6, bird * 0.9);
    }

    // Ridges, far to near: each darker and less hazy; the light from the sun's side rims the far ones.
    float3 hazeTint = mix(low, sunColor, 0.25 * max(day, warm));
    float3 nightRidge = float3(0.03, 0.05, 0.11);
    for (int i = 0; i < 6; i++) {
        float y = lo_ridge(P.x, i);
        float f = float(i) / 5.0;
        // Dusk's ridges are the palette's; by day they are blue-green in the haze, by night deep blue.
        float3 dusk = mix(far, near, pow(f, 0.8));
        float3 noon = mix(float3(0.52, 0.66, 0.74), float3(0.05, 0.15, 0.13), pow(f, 0.7));
        float3 dark = nightRidge * (1.0 + (1.0 - f) * 1.5);
        float3 layer = mix(mix(dark, noon, day), dusk, warm * 0.9);
        layer = mix(layer, hazeTint, (1.0 - f) * 0.3);
        // Haze in the valley below each ridge.
        float valley = exp(-max(P.y - y, 0.0) / 60.0) * (1.0 - f) * 0.25;
        float3 shaded = mix(layer, hazeTint, valley);
        float cover = smoothstep(y - px, y + px, P.y);
        col = mix(col, shaded, cover);

        // Pines on the two nearest ridges.
        if (i >= 4) {
            float spacing = i == 5 ? 26.0 : 16.0;
            float id = floor(P.x / spacing);
            float hh = lo_hash(float2(id, float(i)));
            if (hh > 0.35) {
                float cx = (id + 0.5) * spacing + (lo_hash(float2(id, 7.0)) - 0.5) * spacing * 0.5;
                float base = lo_ridge(cx, i) + 4.0;
                float height = (i == 5 ? 70.0 : 38.0) * (0.6 + 0.6 * hh);
                float dy = base - P.y;
                float spread = height * 0.22 * (1.0 - dy / height) * (0.85 + 0.15 * sin(dy * 0.6));
                float tree = step(0.0, dy) * step(dy, height) * smoothstep(spread + px, spread - px, abs(P.x - cx));
                col = mix(col, shaded * 0.85, tree);
            }
        }

        // The lookout on the second-nearest ridge: four legs, a cabin, a roof, and a lit window at night.
        if (i == 4) {
            float lx = 420.0;
            float ground = lo_ridge(lx, 4);
            float2 q = P - float2(lx, ground);
            float legs = 0.0;
            for (int l = 0; l < 2; l++) {
                float side = l == 0 ? -1.0 : 1.0;
                float xl = side * mix(26.0, 14.0, clamp(-q.y / 110.0, 0.0, 1.0));
                legs = max(legs, step(abs(q.x - xl), 1.6) * step(-110.0, q.y) * step(q.y, 4.0));
            }
            // Cross braces.
            for (int b = 0; b < 3; b++) {
                float y0 = -20.0 - b * 30.0;
                float w = mix(26.0, 14.0, clamp(-y0 / 110.0, 0.0, 1.0));
                float d1 = abs((q.y - y0) - (q.x / w) * 15.0);
                legs = max(legs, step(d1, 0.9) * step(abs(q.x), w) * step(abs(q.y - y0), 15.0));
            }
            float cabin = step(abs(q.x), 20.0) * step(-136.0, q.y) * step(q.y, -108.0);
            float roof = step(abs(q.x), 26.0 - (-(q.y + 136.0)) * 1.2) * step(-148.0, q.y) * step(q.y, -136.0);
            float tower = max(legs, max(cabin, roof));
            col = mix(col, near * 0.7, tower);
            float window = step(abs(q.x), 15.0) * step(-131.0, q.y) * step(q.y, -116.0) * step(0.18, fract((q.x + 15.0) / 10.0));
            col = mix(col, float3(1.0, 0.72, 0.38), window * night * 0.95);
            col += float3(1.0, 0.6, 0.25) * exp(-length(q - float2(0.0, -123.0)) / 26.0) * 0.35 * night;
        }
    }

    float2 v = uv - 0.5;
    col *= 1.0 - 0.3 * dot(v, v) * 2.0;
    return float4(col, 1.0);
}
