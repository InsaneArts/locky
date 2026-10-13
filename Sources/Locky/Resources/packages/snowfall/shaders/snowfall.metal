// Snowfall: a winter night in the woods. Snow falls at every depth, the near flakes large and soft; rows of snowy
// pines fade into the blue; a cabin's windows glow warm on the snow, and smoke curls from its chimney.
// Positions are in layout points (x from the center, y down from the top).
// Colors: 0 the sky's top, 1 the sky low down, 2 the snow, 3 the pines, 4 the window light.
// Params: 0 how much snow (1), 1 the wind (1).

static float sf_sq(float x) { return x * x; }

static float sf_hash(float2 p) {
    p = fract(p * float2(271.31, 619.73));
    p += dot(p, p + 33.17);
    return fract(p.x * p.y);
}

static float sf_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(sf_hash(i), sf_hash(i + float2(1, 0)), u.x), mix(sf_hash(i + float2(0, 1)), sf_hash(i + float2(1, 1)), u.x), u.y);
}

static float sf_fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * sf_noise(p);
        p = p * 2.03 + 11.7;
        a *= 0.5;
    }
    return v;
}

// The ground line of row i (0 far .. 2 near), points from the top.
static float sf_ground(float x, int i) {
    float fi = float(i);
    return 560.0 + fi * 70.0 + 22.0 * sin(x * (0.004 + fi * 0.001) + fi * 2.0) + 12.0 * sf_noise(float2(x * 0.01, fi));
}

// One row of pines: 1 where a tree covers P; `snow` says how much of that is snow on its boughs.
static float sf_pines(float2 P, int i, thread float &snow) {
    float fi = float(i);
    float spacing = 22.0 + fi * 16.0;
    float tall = 90.0 + fi * 60.0;
    float cover = 0.0;
    snow = 0.0;
    // Each tree can lean into its neighbors' slots, so look at three.
    float id0 = floor(P.x / spacing);
    for (int k = -1; k <= 1; k++) {
        float id = id0 + k;
        float h = sf_hash(float2(id, fi * 3.0 + 1.0));
        if (h < 0.25) continue;
        float cx = (id + 0.5) * spacing + (sf_hash(float2(id, fi + 7.0)) - 0.5) * spacing * 0.6;
        // The near row leaves a clearing in front of the cabin.
        if (i == 2 && abs(cx - 260.0) < 150.0) continue;
        float base = sf_ground(cx, i) + 6.0;
        float height = tall * (0.55 + 0.6 * h);
        float dy = base - P.y;
        if (dy < 0.0 || dy > height) continue;
        // Tiers of boughs: each a triangle, wide at its foot and narrow at its top, the whole tree tapering.
        float tiers = 5.0 + floor(h * 2.0);
        float tier = fract(dy / height * tiers);
        float width = height * 0.3 * (1.0 - dy / height) * (0.35 + 0.65 * (1.0 - tier)) + 1.0;
        float edge = width - abs(P.x - cx);
        float inside = smoothstep(-0.6, 0.6, edge);
        cover = max(cover, inside);
        // Snow lies along each bough's upper edge.
        float thick = 2.0 + fi * 1.2;
        snow = max(snow, inside * smoothstep(thick, thick * 0.3, edge) * (0.7 + 0.3 * sf_hash(float2(id, floor(dy / height * tiers)))));
    }
    return cover;
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float s = min(res.x / 1440.0, res.y / 900.0);
    float2 P = float2((uv.x - 0.5) * res.x, (1.0 - uv.y) * res.y) / s;
    float px = 1.0 / s;
    float amount = locky_param(p, 0, 1.0);
    float wind = locky_param(p, 1, 1.0);
    float3 snowColor = locky_color(p, 2), pine = locky_color(p, 3), warm = locky_color(p, 4);

    // Sky: a hazy moon behind thin, drifting clouds.
    float k = clamp(P.y / 700.0, 0.0, 1.0);
    float3 col = mix(locky_color(p, 0), locky_color(p, 1), pow(k, 1.3));
    float2 moon = float2(-380.0, 170.0);
    float md = length(P - moon);
    float clouds = sf_fbm(P * float2(0.003, 0.006) + float2(t * 0.012, 0.0));
    col += snowColor * (0.25 * exp(-md / 160.0) + 0.5 * smoothstep(40.0, 37.0, md)) * (1.0 - 0.6 * smoothstep(0.45, 0.7, clouds));
    col = mix(col, locky_color(p, 1) * 1.3, smoothstep(0.45, 0.75, clouds) * 0.35 * (1.0 - k));

    // Rows of pines, far to near, the far ones lost in the falling snow.
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float fade = 1.0 - fi / 2.0;
        float g = sf_ground(P.x, i);
        float3 ground = mix(snowColor * (0.55 + fi * 0.15), locky_color(p, 1), fade * 0.5);
        float3 trees = mix(pine, locky_color(p, 1), fade * 0.6);
        float3 snowOnTrees = mix(snowColor * 0.8, locky_color(p, 1), fade * 0.5);
        float snow;
        float tree = sf_pines(P, i, snow);
        col = mix(col, mix(trees, snowOnTrees, snow), tree);
        // Snowy ground in front of the row, with a soft shadow line under the trees.
        float onGround = smoothstep(g - px, g + px, P.y);
        // Drifts: soft blue hollows in the snow.
        float drift = sf_noise(float2(P.x * 0.006, P.y * 0.02 + fi * 4.0));
        float3 shaded = ground * (0.88 + 0.16 * drift) * (1.0 - 0.15 * exp(-max(P.y - g, 0.0) / 8.0));
        col = mix(col, shaded, onGround);
        // The cabin, sitting on the middle row's ground.
        if (i == 1) {
            float cx = 260.0;
            float base = sf_ground(cx, 1) + 10.0;
            float2 q = P - float2(cx, base);
            float wall = step(abs(q.x), 64.0) * step(-62.0, q.y) * step(q.y, 0.0);
            float roofLine = -62.0 - (54.0 - abs(q.x) * 0.62);
            float roof = step(abs(q.x), 84.0) * step(roofLine, q.y) * step(q.y, -56.0);
            float chimney = step(abs(q.x - 34.0), 7.0) * step(-120.0, q.y) * step(q.y, -80.0);
            float cabin = max(max(wall, roof), chimney);
            float3 wood = pine * 1.2 + warm * 0.05;
            // Snow thick on the roof and on the chimney's cap.
            float roofSnow = roof * smoothstep(roofLine + 14.0, roofLine + 4.0, q.y);
            roofSnow = max(roofSnow, chimney * step(q.y, -116.0));
            col = mix(col, mix(wood, snowColor * 0.95, roofSnow), cabin);
            // Two windows and a door: warm, flickering faintly like a fire inside.
            float flicker = 0.9 + 0.1 * sf_noise(float2(t * 3.0, 0.0));
            float windows = 0.0;
            for (int w = 0; w < 2; w++) {
                float2 wq = q - float2(w == 0 ? -34.0 : 30.0, -34.0);
                float pane = step(abs(wq.x), 11.0) * step(abs(wq.y), 10.0);
                float bars = step(abs(wq.x), 1.0) + step(abs(wq.y), 1.0);
                windows = max(windows, pane * (1.0 - clamp(bars, 0.0, 1.0) * 0.8));
            }
            col = mix(col, warm * flicker, windows);
            // Light spilling onto the snow and the trees around.
            float spill = exp(-length((q - float2(0.0, 30.0)) / float2(160.0, 50.0))) * step(0.0, q.y - 2.0);
            col += warm * spill * 0.35 * flicker * (1.0 - cabin);
            col += warm * 0.08 * exp(-length(q - float2(0.0, -30.0)) / 140.0) * (1.0 - cabin);
            // Smoke curling up from the chimney and leaning with the wind.
            float2 sq = q - float2(34.0, -124.0);
            if (sq.y < 0.0) {
                float rise = -sq.y;
                float2 drift = float2(rise * 0.35 * wind + sin(rise * 0.03 - t * 0.8) * 10.0 * sqrt(rise * 0.02), 0.0);
                float spread = 8.0 + rise * 0.18;
                float plume = exp(-sf_sq((sq.x - drift.x) / spread)) * exp(-rise / 260.0);
                float wisps = sf_fbm(float2(sq.x * 0.03, (sq.y + t * 22.0) * 0.025));
                col = mix(col, snowColor * 0.75, plume * smoothstep(0.3, 0.7, wisps) * 0.5);
            }
        }
    }

    // Sparkles on the near snow.
    float2 sc = floor(P / 3.0);
    float sh = sf_hash(sc);
    float near = smoothstep(sf_ground(P.x, 2), sf_ground(P.x, 2) + 40.0, P.y);
    col += snowColor * step(0.996, sh) * near * (0.5 + 0.5 * sin(t * 3.0 + sh * 100.0));

    // Snowfall at four depths: far flakes small and slow, near ones large, soft, and quick.
    for (int layer = 0; layer < 4; layer++) {
        float fl = float(layer);
        float size = 34.0 + fl * 30.0;
        float speed = 22.0 + fl * 18.0;
        float2 q = P + float2(-t * speed * 0.35 * wind, -t * speed) + fl * 97.0;
        q.x += sin(q.y * 0.012 + fl) * 14.0;
        float2 id = floor(q / size);
        float h = sf_hash(id + fl * 13.0);
        if (h > 1.0 - 0.6 * amount) {
            float2 c = (float2(sf_hash(id + 1.1), sf_hash(id + 2.2)) * 0.7 + 0.15) * size;
            float r = 0.8 + fl * 1.1;
            float soft = 0.6 + fl * 1.4;
            float d = length(fract(q / size) * size - c);
            float flake = smoothstep(r + soft, r - soft * 0.3, d);
            col = mix(col, snowColor, flake * (0.55 + 0.1 * fl));
        }
    }

    float2 v = uv - 0.5;
    col *= 1.0 - 0.35 * dot(v, v) * 2.0;
    return float4(col, 1.0);
}
