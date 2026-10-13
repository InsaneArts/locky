// Sakura: a spring night. A cherry branch in bloom reaches in from the top left under a large moon; petals drift down
// and turn as they fall; a snow-capped mountain and a pagoda stand in the mist below.
// Positions are in layout points (x from the center, y down from the top).
// Colors: 0 the sky's top, 1 the sky low down, 2 the blossoms, 3 the blossoms' light centers, 4 the moon, 5 the
// silhouettes (branch, mountain, pagoda).
// Params: 0 how many petals (1), 1 the wind (1).

static float sk_sq(float x) { return x * x; }

static float sk_hash(float2 p) {
    p = fract(p * float2(213.73, 381.29));
    p += dot(p, p + 27.41);
    return fract(p.x * p.y);
}

static float sk_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(sk_hash(i), sk_hash(i + float2(1, 0)), u.x), mix(sk_hash(i + float2(0, 1)), sk_hash(i + float2(1, 1)), u.x), u.y);
}

// Distance from P to the segment a-b, and how far along it P lies (0 at a, 1 at b).
static float2 sk_segment(float2 P, float2 a, float2 b) {
    float2 pa = P - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return float2(length(pa - ba * h), h);
}

// The branch: limbs as tapered segments (start, end, width at start, width at end). Returns the distance to the
// nearest limb's edge (negative inside), and in .y the distance to its middle line, for blossoms.
constant float4 SK_LIMBS[9] = {
    float4(-780.0, 40.0, -420.0, 150.0), float4(-420.0, 150.0, -170.0, 205.0), float4(-170.0, 205.0, 40.0, 190.0),
    float4(-420.0, 150.0, -330.0, 300.0), float4(-330.0, 300.0, -250.0, 360.0), float4(-560.0, 95.0, -520.0, 10.0),
    float4(-170.0, 205.0, -110.0, 290.0), float4(-250.0, 180.0, -200.0, 110.0), float4(-600.0, 110.0, -650.0, 230.0),
};
constant float2 SK_WIDTHS[9] = {
    float2(34.0, 20.0), float2(20.0, 10.0), float2(10.0, 4.0), float2(13.0, 7.0), float2(7.0, 3.0), float2(11.0, 4.0),
    float2(7.0, 2.5), float2(7.0, 2.5), float2(10.0, 3.5),
};

static float2 sk_branch(float2 P) {
    float edge = 1e5, mid = 1e5;
    for (int i = 0; i < 9; i++) {
        float4 l = SK_LIMBS[i];
        float2 d = sk_segment(P, l.xy, l.zw);
        // A little knobbliness along the bark.
        float w = mix(SK_WIDTHS[i].x, SK_WIDTHS[i].y, d.y) * 0.5 * (1.0 + 0.15 * sin(d.y * 40.0 + i));
        edge = min(edge, d.x - w);
        mid = min(mid, d.x);
    }
    return float2(edge, mid);
}

// One five-petaled flower at its center c, radius r, turned by a: 1 inside.
static float sk_flower(float2 P, float2 c, float r, float a) {
    float2 d = P - c;
    float ang = atan2(d.y, d.x) + a;
    float petals = 0.72 + 0.28 * cos(ang * 5.0);
    return 1.0 - smoothstep(r * petals - 0.8, r * petals + 0.8, length(d));
}

// A falling petal: an oval with a notch, turning about its center.
static float sk_petal(float2 P, float2 c, float size, float a, float flip) {
    float2 d = P - c;
    float2 q = float2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a));
    q.x /= max(abs(flip), 0.25);
    float oval = length(q / float2(size * 0.6, size));
    float notch = length(q - float2(0.0, -size * 1.05)) - size * 0.28;
    return (1.0 - smoothstep(0.85, 1.0, oval)) * smoothstep(-0.5, 0.5, notch);
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float s = min(res.x / 1440.0, res.y / 900.0);
    float2 P = float2((uv.x - 0.5) * res.x, (1.0 - uv.y) * res.y) / s;
    float many = locky_param(p, 0, 1.0);
    float wind = locky_param(p, 1, 1.0);
    float3 blossom = locky_color(p, 2), light = locky_color(p, 3), shadow = locky_color(p, 5);

    // Sky, with a faint drifting cloud bank.
    float k = clamp(P.y / 900.0, 0.0, 1.0);
    float3 col = mix(locky_color(p, 0), locky_color(p, 1), smoothstep(0.1, 1.0, k));
    float cloud = sk_noise(P * float2(0.004, 0.012) + float2(t * 0.01, 0.0)) * sk_noise(P * 0.009 + 4.0);
    col += locky_color(p, 1) * 0.25 * smoothstep(0.2, 0.6, cloud);

    // The moon, with a halo and soft maria.
    float2 moon = float2(400.0, 230.0);
    float mr = 92.0, md = length(P - moon);
    col += locky_color(p, 4) * 0.35 * exp(-max(md - mr, 0.0) / 70.0);
    float maria = sk_noise((P - moon) * 0.022 + 1.0) * 0.6 + sk_noise((P - moon) * 0.06 + 3.0) * 0.4;
    float3 face = locky_color(p, 4) * (0.95 - 0.08 * smoothstep(0.4, 0.8, maria));
    col = mix(col, face, 1.0 - smoothstep(mr - 1.0, mr + 1.0, md));

    // A snow-capped mountain in the mist, and in front of it a hill with a pagoda.
    float mx = P.x + 20.0;
    float peak = 545.0 + abs(mx) * 0.58 - 22.0 * exp(-mx * mx / 1200.0) + 5.0 * sk_noise(float2(P.x * 0.03, 0.0));
    // Snow on the summit, its lower edge running down in streaks.
    float snowLine = 596.0 + 34.0 * sk_noise(float2(P.x * 0.05, 3.0)) + 14.0 * sk_noise(float2(P.x * 0.16, 8.0));
    float snow = smoothstep(snowLine + 4.0, snowLine - 4.0, P.y);
    float3 rock = shadow * 1.8 + locky_color(p, 1) * 0.35;
    float lit = 0.75 + 0.25 * smoothstep(-40.0, 40.0, mx);   // the moon lights the right slope
    float3 mountain = mix(rock, locky_color(p, 4) * 0.62 * lit, snow);
    col = mix(col, mountain, smoothstep(peak - 1.0, peak + 1.0, P.y));
    float hill = 790.0 - 60.0 * exp(-sk_sq((P.x - 400.0) / 260.0)) + 8.0 * sk_noise(float2(P.x * 0.02, 1.0));
    float pagoda = 0.0;
    float2 g = P - float2(400.0, 730.0);
    for (int i = 0; i < 5; i++) {
        float y0 = -i * 34.0;
        float w = 58.0 - i * 8.0;
        // Each tier: a roof with upturned eaves over a narrow body.
        float roofY = g.y - (y0 - 26.0);
        float eave = w + 10.0 - roofY * 1.4 + 4.0 * smoothstep(w * 0.7, w + 10.0, abs(g.x));
        pagoda = max(pagoda, step(abs(g.x), eave) * step(0.0, roofY) * step(roofY, 7.0));
        pagoda = max(pagoda, step(abs(g.x), w * 0.6) * step(y0 - 26.0, g.y) * step(g.y, y0));
    }
    pagoda = max(pagoda, step(abs(g.x), 1.5) * step(-215.0, g.y) * step(g.y, -160.0));
    float near = max(smoothstep(hill - 1.0, hill + 1.0, P.y), pagoda);
    col = mix(col, shadow * 1.2, near);
    // A lantern glows in the pagoda.
    col += float3(1.0, 0.7, 0.4) * exp(-length(g - float2(0.0, -10.0)) / 6.0) * 0.8;
    // Mist low over the ground.
    col += locky_color(p, 1) * 0.35 * smoothstep(620.0, 860.0, P.y) * (0.6 + 0.4 * sk_noise(float2(P.x * 0.004 + t * 0.02, 2.0)));

    // The branch, its bark lit faintly by the moon, and blossoms crowded along it.
    float2 b = sk_branch(P);
    col = mix(col, shadow * 0.9 + locky_color(p, 4) * 0.03, smoothstep(1.0, -1.0, b.x));
    // A soft pink glow where the blossoms crowd, so the clusters read as masses, not dots.
    col += blossom * 0.22 * exp(-max(b.y - 10.0, 0.0) / 26.0);
    float2 cell = floor(P / 13.0);
    for (int j = 0; j < 9; j++) {
        float2 c = cell + float2(j % 3 - 1, j / 3 - 1);
        float h = sk_hash(c);
        float2 at = (c + 0.5 + 0.8 * (float2(sk_hash(c + 1.7), sk_hash(c + 3.3)) - 0.5)) * 13.0;
        float near = sk_branch(at).y;
        if (near < 44.0 && h > 0.15 + near / 70.0) {
            float r = 8.0 + 6.0 * sk_hash(c + 5.1);
            float f = sk_flower(P, at, r, h * 6.28);
            float center = exp(-sk_sq(length(P - at) / (r * 0.3)));
            // Flowers further from the branch are lighter, as if lit by the moon.
            float3 tone = mix(blossom * (0.7 + 0.4 * sk_hash(c + 8.2)), light, center * 0.85 + 0.15 * smoothstep(10.0, 40.0, near));
            col = mix(col, tone, f);
        }
    }

    // Falling petals in three depths: far ones small and slow, near ones large, soft, and quick.
    for (int layer = 0; layer < 3; layer++) {
        float size = 70.0 + layer * 55.0;
        float fall = (22.0 + layer * 16.0);
        float2 drift = float2(-wind * fall * 0.8, -fall) * t;
        float2 q = P + drift + float2(layer * 333.0, layer * 177.0);
        float2 id = floor(q / size);
        float h = sk_hash(id + layer * 7.0);
        if (h > 1.0 - 0.55 * many) {
            float2 c = (id + 0.5) * size - drift - float2(layer * 333.0, layer * 177.0);
            c += float2(sin(t * (0.6 + h) + h * 20.0) * 18.0, cos(t * 0.7 + h * 9.0) * 6.0);
            float ps = 4.0 + layer * 2.6;
            float spin = t * (0.8 + h * 1.5) + h * 30.0;
            float petal = sk_petal(P, c, ps, spin, cos(t * (1.2 + h) + h * 11.0));
            float3 tone = mix(blossom, light, 0.45 + 0.3 * sin(spin));
            col = mix(col, tone, petal * (layer == 2 ? 0.75 : 0.9));
        }
    }

    // Vignette.
    float2 v = uv - 0.5;
    col *= 1.0 - 0.35 * dot(v, v) * 2.0;
    return float4(col, 1.0);
}
