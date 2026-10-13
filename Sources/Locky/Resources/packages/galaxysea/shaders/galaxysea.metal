// Galaxy Sea: the Milky Way arching over a sea so calm it mirrors it, and a small boat with someone in it on the
// horizon. Stars twinkle, the galaxy's glow breathes, slow swells ripple the reflection, and now and then a meteor.
// Positions are in layout points (x from the center, y down from the top).
// Colors: 0 the sky's top, 1 the sky at the horizon, 2 the galaxy's violet, 3 its pink core, 4 its blue edge.
// Params: 0 the horizon, points from the top (610), 1 the boat's x from the center (300; 9999 hides it).

static float gs_hash(float2 p) {
    p = fract(p * float2(233.34, 851.73));
    p += dot(p, p + 23.45);
    return fract(p.x * p.y);
}

static float gs_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(gs_hash(i), gs_hash(i + float2(1, 0)), u.x), mix(gs_hash(i + float2(0, 1)), gs_hash(i + float2(1, 1)), u.x), u.y);
}

static float gs_fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * gs_noise(p);
        p = float2(p.x * 1.6 - p.y * 1.2, p.x * 1.2 + p.y * 1.6) + 7.3;
        a *= 0.5;
    }
    return v;
}

static float3 gs_stars(float2 P, float t, float size, float density, float bright) {
    float2 cell = floor(P / size);
    float h = gs_hash(cell);
    if (h < density) return float3(0.0);
    float2 c = (cell + 0.2 + 0.6 * float2(gs_hash(cell + 1.3), gs_hash(cell + 2.9))) * size;
    float d = length(P - c);
    float twinkle = 0.55 + 0.45 * sin(t * (0.6 + 2.0 * gs_hash(cell + 4.4)) + h * 50.0);
    float3 tint = mix(float3(1.0, 0.86, 0.8), float3(0.8, 0.9, 1.0), gs_hash(cell + 7.7));
    return tint * bright * twinkle * exp(-d * d * (size < 10.0 ? 1.4 : 0.6));
}

// The sky at point P (points), without the boat.
static float3 gs_sky(float2 P, float horizon, float t, constant LockyParams &p) {
    float k = clamp(P.y / horizon, 0.0, 1.0);
    float3 col = mix(locky_color(p, 0), locky_color(p, 1), pow(k, 1.6));

    // The galaxy: a band from the lower left to the upper right. b is the distance across it, a along it.
    float2 dir = normalize(float2(1.0, -0.62));
    float2 c = P - float2(-60.0, 330.0);
    float a = dot(c, dir), b = dot(c, float2(-dir.y, dir.x));
    float widen = 150.0 + 40.0 * sin(a * 0.004);
    float band = exp(-b * b / (widen * widen));
    float2 g = float2(a, b) * 0.006;
    float cloud = gs_fbm(g + float2(t * 0.004, 0.0));
    float fine = gs_fbm(g * 3.2 + 11.0);
    // Dust lanes: dark filaments that run along the band's middle.
    float wobble = (gs_fbm(float2(a * 0.003, 5.0)) - 0.5) * 120.0;
    float lane = exp(-pow((b - wobble) / 38.0, 2.0));
    float dust = lane * smoothstep(0.38, 0.7, gs_fbm(float2(a * 0.011, b * 0.035) + 3.0));
    float glow = band * (0.35 + 0.9 * cloud * cloud + 0.35 * fine);
    float breathe = 0.92 + 0.08 * sin(t * 0.25);
    float3 hue = mix(locky_color(p, 2), locky_color(p, 3), smoothstep(0.3, 0.75, cloud) * exp(-b * b / (90.0 * 90.0)));
    hue = mix(hue, locky_color(p, 4), smoothstep(0.6, 0.85, fine) * 0.4);
    col += hue * glow * breathe * (1.0 - 0.85 * dust);
    // A bright, nearly white core where the band is densest.
    col += float3(1.0, 0.92, 0.88) * pow(band * cloud, 3.0) * 0.55 * (1.0 - dust);

    // Stars, denser inside the band.
    col += gs_stars(P, t, 5.0, 0.9 - 0.08 * band, 0.55);
    col += gs_stars(P + 1000.0, t, 17.0, 0.93, 1.1);
    col += gs_stars(P + 3000.0, t, 47.0, 0.94, 1.6);
    // Haze along the horizon.
    col += locky_color(p, 3) * 0.12 * exp(-(horizon - P.y) / 40.0);
    return col;
}

// A meteor every few seconds, somewhere in the upper sky.
static float3 gs_meteor(float2 P, float t) {
    float period = 9.0;
    float n = floor(t / period), local = t - n * period;
    if (local > 0.9) return float3(0.0);
    float2 start = float2((gs_hash(float2(n, 1.0)) - 0.5) * 1100.0, 60.0 + gs_hash(float2(n, 2.0)) * 220.0);
    float2 dir = normalize(float2(gs_hash(float2(n, 3.0)) > 0.5 ? 1.0 : -1.0, 0.45));
    float2 head = start + dir * local * 520.0;
    float2 d = P - head;
    float along = dot(d, -dir), across = dot(d, float2(-dir.y, dir.x));
    if (along < 0.0 || along > 140.0) return float3(0.0);
    float fade = sin(local / 0.9 * 3.14159);
    return float3(0.9, 0.95, 1.0) * exp(-across * across / 0.8) * (1.0 - along / 140.0) * fade * 1.4;
}

// The boat and its passenger as a silhouette: > 0 inside.
static float gs_boat(float2 P, float2 at) {
    float2 q = P - at;
    // The hull: a shallow crescent, wider at the top.
    float hull = (abs(q.x) < 46.0 - max(q.y, 0.0) * 1.6 && q.y > -3.0 && q.y < 10.0) ? 1.0 : 0.0;
    hull *= step(q.y, 10.0 - pow(abs(q.x) / 46.0, 6.0) * 10.0);
    // Someone sitting, looking up: a torso and a head.
    float torso = step(length((q - float2(6.0, -13.0)) / float2(7.0, 11.0)), 1.0);
    float head = step(length(q - float2(4.0, -29.0)), 5.5);
    // An oar resting across the boat.
    float2 o = q - float2(-8.0, -4.0);
    float oar = step(abs(o.y + o.x * 0.32), 1.1) * step(abs(o.x), 34.0);
    return max(max(hull, torso), max(head, oar));
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float s = min(res.x / 1440.0, res.y / 900.0);
    float2 P = float2((uv.x - 0.5) * res.x, (1.0 - uv.y) * res.y) / s;
    float horizon = locky_param(p, 0, 610.0);
    float2 boat = float2(locky_param(p, 1, 300.0), horizon - 2.0);

    float3 col;
    if (P.y < horizon) {
        col = gs_sky(P, horizon, t, p) + gs_meteor(P, t);
        col = mix(col, locky_color(p, 0) * 0.25, gs_boat(P, boat));
    } else {
        // The sea: the sky mirrored, rippled by swells that grow finer toward the horizon.
        float depth = P.y - horizon;
        float persp = 1.0 / (depth * 0.02 + 0.25);
        float w = sin(P.x * 0.018 * persp + t * 0.7 + depth * 0.05) * 0.6 + sin(P.x * 0.041 * persp - t * 0.9 + depth * 0.11) * 0.4;
        float swell = sin(depth * 0.9 * persp * 0.25 - t * 1.1) * 0.5 + 0.5;
        float2 m = float2(P.x + w * depth * 0.06, horizon - depth * (1.0 + 0.04 * w) - 2.0);
        col = gs_sky(m, horizon, t, p) * 0.72 + gs_meteor(m, t) * 0.5;
        col = mix(col, locky_color(p, 0) * 0.25, gs_boat(m, boat) * 0.9);
        // Glints along the swells' crests, and the water darker toward the viewer.
        col += locky_color(p, 4) * pow(swell, 12.0) * 0.06 * exp(-depth / 160.0);
        col *= mix(1.0, 0.55, smoothstep(0.0, 300.0, depth));
        // A soft line where sea meets sky.
        col += locky_color(p, 3) * 0.08 * exp(-depth / 6.0);
    }
    return float4(col, 1.0);
}
