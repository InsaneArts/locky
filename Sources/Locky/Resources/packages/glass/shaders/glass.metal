// Glass: the Liquid Glass theme's scene when there is no desktop picture. An homage to macOS Tahoe's
// wallpaper: a sky that fades to sandy beige, crossed by one cobalt wave whose crest breaks into streaks of
// light blue and cream. Everything drifts slowly.
// Colors: 0 sky, 1 sand, 2 wave, 3 crest streaks (cool), 4 crest streaks (warm).

static inline uint gl_pcg(uint v) {
    uint s = v * 747796405u + 2891336453u;
    uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
    return (w >> 22u) ^ w;
}

static inline float gl_h1(float x) { return float(gl_pcg(uint(int(x)))) * (1.0 / 4294967296.0); }

static float gl_n1(float x) {
    float i = floor(x), f = x - i;
    return mix(gl_h1(i), gl_h1(i + 1.0), f * f * (3.0 - 2.0 * f));
}

// The wave's crest line: a long rise to the right with slow swells.
static float gl_crest(float x, float t) {
    return 0.25 + 0.12 * x + 0.035 * sin(x * 2.3 + 0.7 + t * 0.09) + 0.01 * sin(x * 6.1 - t * 0.16);
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float x = (uv.x - 0.5) * res.x / res.y;
    float y = uv.y;
    float px = 1.0 / res.y;
    float3 sky = locky_color(p, 0), sand = locky_color(p, 1), wave = locky_color(p, 2);
    float3 cool = locky_color(p, 3), warm = locky_color(p, 4);

    // Sky to sand: blue at the top, beige from about 70% of the way down, a little deeper at the very bottom.
    float3 col = mix(sand, sky, smoothstep(0.3, 0.97, y));
    col = mix(col, sky * 0.9, smoothstep(0.75, 1.0, y) * 0.45);
    col = mix(col, sand * 0.9, smoothstep(0.2, 0.0, y) * 0.6);

    float crest = gl_crest(x, t);
    col = mix(col, warm, 0.22 * exp(-max(y - crest, 0.0) / 0.09));  // warm light over the wave and the sand
    float depth = 0.2 + 0.03 * x + 0.02 * sin(x * 1.4 + 2.0 + t * 0.05);  // deep enough to hold the password field
    float d = crest - y;  // distance below the crest

    // Streaks breaking off the crest: each one peels off the lip at its own point and trails back to the
    // left, rising and tapering. Each casts a faint shadow, so they sit on the sky like layers of glass.
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float start = -0.62 + 0.21 * fi + 0.05 * sin(t * 0.07 + fi * 2.1);   // where it leaves the crest
        float back = start - x;                                                // distance trailed so far
        float span = 0.42 + 0.3 * gl_h1(fi + 3.0);
        float run = smoothstep(-0.02, 0.06, back) * smoothstep(span, span * 0.45, back);
        float rise = (0.15 + 0.12 * gl_h1(fi + 11.0)) * pow(max(back, 0.0), 1.3);
        float width = (0.0038 + 0.0026 * gl_h1(fi + 7.0)) * run;
        float center = crest + 0.0015 + rise;
        float s = (y - center) / max(width, 1e-4);
        col *= 1.0 - 0.06 * run * exp(-max(-s - 1.0, 0.0) * 0.7) * step(s, -1.0) * step(-7.0, s);
        float ink = smoothstep(1.0 + px / max(width, 1e-4), 1.0 - px / max(width, 1e-4), abs(s)) * run;
        float3 tone = (i % 2 == 0) ? cool : warm;
        col = mix(col, tone, ink);
    }

    // The wave body: luminous under the crest, deep cobalt toward its foot, with a crisp foot on the sand.
    float below = d - depth;  // > 0 under the wave's foot
    col *= 1.0 - 0.09 * exp(-max(below, 0.0) / 0.035) * smoothstep(-px, px * 2.0, below);  // its soft shadow
    col = mix(col, warm, exp(-pow((below - px * 2.5) / (px * 1.6), 2.0)) * 0.85);       // a line of foam
    float inside = smoothstep(-px * 1.2, px * 1.2, d) * smoothstep(px * 1.2, -px * 1.2, below);
    float k = saturate(d / depth);
    float3 body = mix(wave * 1.3 + float3(0.06, 0.1, 0.12), wave * 0.95, smoothstep(0.0, 0.45, k));
    body = mix(body, wave * 0.6, smoothstep(0.45, 1.0, k));
    body = mix(body, cool, exp(-d / 0.012) * 0.5);  // glassy light just under the lip
    col = mix(col, body, inside);
    col = mix(col, mix(cool, float3(1.0), 0.35), exp(-pow(d / (px * 2.2), 2.0)) * 0.95);  // the bright lip

    col += (float(gl_pcg(uint(uv.x * res.x) * 7919u + uint(uv.y * res.y))) / 4294967296.0 - 0.5) / 255.0;
    return float4(col, 1.0);
}
