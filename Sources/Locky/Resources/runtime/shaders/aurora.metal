// Aurora: northern lights over a mountain lake at night. Locky's default background.
// Five layers, back to front: the sky, three layers of stars, the aurora's curtains, two mountain ridges,
// and a still lake that mirrors all of it with gentle ripples.
//
// Colors: 0 zenith, 1 horizon, 2 aurora core, 3 aurora base, 4 aurora tips, 5 far ridge, 6 near ridge.
// Params: 0 aurora brightness (default 1), 1 star density (1), 2 clock glow (1: soft light behind the clock
//         at the top center; 0 turns it off).

constant float AU_SHORE = 0.22;  // the lake's far shore, as a fraction of the height from the bottom

// Integer hashes: they stay stable after hours of lock time, unlike sin()-based ones.
static inline uint au_pcg(uint v) {
    uint s = v * 747796405u + 2891336453u;
    uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
    return (w >> 22u) ^ w;
}

static inline float au_h1(float x) { return float(au_pcg(uint(int(x)))) * (1.0 / 4294967296.0); }

static inline float au_h2(float2 p) {
    return float(au_pcg(uint(int(p.x)) + au_pcg(uint(int(p.y))))) * (1.0 / 4294967296.0);
}

static float au_n1(float x) {
    float i = floor(x), f = x - i;
    return mix(au_h1(i), au_h1(i + 1.0), f * f * (3.0 - 2.0 * f));
}

static float au_n2(float2 p) {
    float2 i = floor(p), f = p - i, u = f * f * (3.0 - 2.0 * f);
    return mix(mix(au_h2(i), au_h2(i + float2(1, 0)), u.x), mix(au_h2(i + float2(0, 1)), au_h2(i + float2(1, 1)), u.x), u.y);
}

static float au_fbm1(float x) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * au_n1(x); x = x * 2.07 + 13.7; a *= 0.5; }
    return v * (1.0 / 0.9375);
}

// Ridged noise for mountains: sharp peaks, soft valleys, 0..1.
static float au_ridged(float x, int octaves) {
    float v = 0.0, a = 0.5, w = 0.0;
    for (int i = 0; i < octaves; i++) {
        float n = 1.0 - abs(2.0 * au_n1(x) - 1.0);
        v += a * n * n;
        w += a;
        x = x * 2.11 + 5.3;
        a *= 0.47;
    }
    return v / w;
}

// Mountain peaks: in each cell one peak at a random place and height, with straight flanks; 0..1.
static float au_peaks(float x, float cell, float seed) {
    float i = floor(x / cell), m = 0.0;
    for (int k = -1; k <= 1; k++) {
        float c = i + float(k);
        float at = (c + 0.15 + 0.7 * au_h1(c + seed)) * cell;
        float height = 0.3 + 0.7 * au_h1(c + seed + 57.0);
        float slope = (0.8 + 0.7 * au_h1(c + seed + 91.0)) / cell;
        m = max(m, height - abs(x - at) * slope);
    }
    return m;
}

static float au_far_ridge(float x) {
    float shape = max(au_peaks(x, 0.36, 5.0), 0.55 * au_peaks(x, 0.14, 11.0) + 0.15);
    float sides = 0.8 + 0.4 * smoothstep(0.15, 0.75, abs(x));  // taller toward the edges, framing the middle
    return 0.242 + 0.095 * shape * sides + 0.022 * (au_ridged(x * 9.0 + 2.0, 4) - 0.4);
}

static float au_near_ridge(float x) {
    float h = 0.226 + 0.045 * au_ridged(x * 2.3 + 21.0, 4);
    float c = x * 120.0;  // a fringe of conifers along the crest
    return h + 0.006 * (1.0 - abs(2.0 * fract(c) - 1.0)) * au_h1(floor(c));
}

// One layer of stars on a jittered grid. p is in units of the screen's height; radius too.
static float3 au_stars(float2 p, float cells, float chance, float radius, float bright, float rate, float t, float seed) {
    float2 g = p * cells;
    float2 id = floor(g);
    float h = au_h2(id + seed);
    if (h > chance) return float3(0.0);
    float2 at = float2(au_h2(id + seed + 17.0), au_h2(id + seed + 41.0)) * 0.5 + 0.25;
    float2 d = (g - id - at) / cells;
    float core = exp(-dot(d, d) / (radius * radius));
    float k = au_h2(id + seed + 73.0);
    float twinkle = 0.62 + 0.38 * sin(t * rate * (0.7 + 0.6 * k) + k * 50.0);
    float3 tint = k < 0.12 ? float3(1.0, 0.851, 0.659) : k > 0.88 ? float3(0.659, 0.784, 1.0) : float3(1.0);
    return tint * (bright * (0.35 + 0.65 * h / chance) * twinkle * core);
}

// The lower border of a curtain: a slow sweep across the sky (tilt, and a wave of height `bow`) plus folds
// from fBm (amp, freq), all drifting.
static float au_edge(float x, float t, float base, float tilt, float bow, float wave, float amp, float freq, float seed) {
    float folds = au_fbm1(x * freq + seed * 7.0 + t * 0.011) * 2.0 - 1.0;
    float kinks = au_n1(x * freq * 6.0 + seed - t * 0.03) - 0.5;
    return base + tilt * x + bow * sin(x * wave + seed + t * 0.017) + amp * folds + amp * 0.25 * kinks;
}

// One curtain above its lower border `edge`: fine vertical rays, colored by height (base, core, tips).
static float3 au_curtain(float x, float y, float t, float edge, float slope, float reach, float seed, float3 core, float3 low, float3 tips) {
    float h = y - edge;
    float along = smoothstep(0.25, 0.72, 0.55 * au_n1(x * 2.2 + seed * 3.1 + t * 0.035) + 0.45 * au_n1(x * 6.1 + seed - t * 0.05));
    float3 haze = mix(core, tips, 0.5) * (exp(-abs(h - 0.03) / 0.07) * along * 0.06);
    if (h < -0.03) return haze;
    float close = 0.55 + 0.55 * saturate((edge - AU_SHORE) / 0.25);  // lower borders are farther away: shorter, dimmer
    float rx = x * 85.0 + edge * 40.0 + seed * 31.0 + 4.0 * au_n1(x * 9.0 + seed - t * 0.02);  // uneven spacing
    float ray = 0.5 * au_n1(rx + t * 0.2) + 0.3 * au_n1(rx * 2.3 + 5.0 - t * 0.33) + 0.2 * au_n1(rx * 5.3 + 11.0 + t * 0.55);
    float top = reach * close * (0.7 + 0.6 * ray) * (0.6 + 0.7 * au_n1(x * 3.0 + seed + t * 0.04));
    float hp = max(h, 0.0);
    float body = smoothstep(-0.01, 0.0, h)
               * (exp(-hp / top) * mix(0.85 + 0.3 * ray, 0.55 + 0.7 * ray, smoothstep(0.0, 0.05, hp)) + 0.26 * (0.4 + ray) * exp(-hp / 0.01));
    float fringe = exp(-pow((h + 0.006) / 0.009, 2.0)) * (0.4 + ray);
    float3 c = mix(core, tips, smoothstep(0.025, 0.14, hp));
    float fold = 1.0 + 0.35 * smoothstep(0.15, 0.9, abs(slope));  // folds seen edge-on look brighter
    return (c * body + low * fringe * 0.5) * (along * fold * close) + haze;
}

// Everything above the lake at (x, y): sky, stars, aurora, ridges. x is centered and in units of the height.
static float3 au_scene(float x, float y, float t, constant LockyParams &p, float px) {
    float sh = saturate((y - AU_SHORE) / (1.0 - AU_SHORE));
    float3 col = mix(locky_color(p, 1), locky_color(p, 0), smoothstep(0.0, 1.0, pow(sh, 0.7)));

    // The ridges never reach above 0.4, so the sky above skips them.
    float far = y > 0.4 ? 0.0 : au_far_ridge(x), near = y > 0.4 ? 0.0 : au_near_ridge(x);
    float inFar = smoothstep(far + px, far - px, y);
    float inNear = smoothstep(near + px, near - px, y);

    if (inFar < 1.0) {
        float density = locky_param(p, 1, 1.0);
        float2 sp = float2(x, y);
        float3 stars = au_stars(sp, 220.0, 0.06 * density, 0.0007, 0.45, 1.7, t, 0.0)
                     + au_stars(sp, 80.0, 0.10 * density, 0.0011, 0.80, 1.1, t, 101.0)
                     + au_stars(sp, 26.0, 0.06 * density, 0.0016, 1.30, 0.6, t, 211.0);
        col += stars * smoothstep(far, far + 0.12, y);

        float3 core = locky_color(p, 2), low = locky_color(p, 3), tips = locky_color(p, 4);
        float e1 = au_edge(x, t, 0.44, 0.09, 0.05, 3.6, 0.12, 1.7, 1.0);
        float s1 = (au_edge(x + 0.004, t, 0.44, 0.09, 0.05, 3.6, 0.12, 1.7, 1.0) - e1) / 0.004;
        float e2 = au_edge(x, t, 0.59, -0.05, 0.035, 4.4, 0.13, 2.1, 5.0);
        float e3 = au_edge(x, t, 0.30, 0.02, 0.015, 4.0, 0.05, 2.4, 9.0);
        float3 aurora = au_curtain(x, y, t, e1, s1, 0.08, 1.0, core, low, tips) * 0.9
                      + au_curtain(x, y, t, e2, 0.0, 0.07, 5.0, core, low, tips) * (0.5 * smoothstep(0.28, 0.6, abs(x)))
                      + au_curtain(x, y, t, e3, 0.0, 0.05, 9.0, core, low, tips) * 0.6;
        col += aurora * locky_param(p, 0, 1.0);

        // A soft glow behind the clock at the top center.
        float dy = y - 0.76;
        col += core * (0.11 * locky_param(p, 2, 1.0) * exp(-(x * x / 0.055 + dy * dy / 0.006)));
    }

    float3 farColor = mix(locky_color(p, 5), locky_color(p, 1), 0.3 * (1.0 - smoothstep(AU_SHORE, 0.28, y)));
    col = mix(col, farColor, inFar);
    col = mix(col, locky_color(p, 6), inNear);
    return col;
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float px = 1.0 / res.y;
    float x = (uv.x - 0.5) * res.x / res.y;
    float3 col;

    if (uv.y >= AU_SHORE) {
        col = au_scene(x, uv.y, t, p, px);
    } else {
        // The lake: a mirror of the scene, darker and a little squeezed so the aurora shows in it, with ripples
        // that crowd together toward the far shore.
        float d = AU_SHORE - uv.y;
        float k = d / AU_SHORE;
        float z = 0.55 / (d + 0.03);
        float2 wp = float2(x * z * 1.4, z * 7.0);
        float w = 0.65 * au_n2(wp + float2(0.0, t * 0.4)) + 0.35 * au_n2(wp * 2.2 + float2(t * 0.15, -t * 0.3) + 9.0) - 0.5;
        float amp = 0.004 * k + 0.004 * k * k;
        float3 mirror = au_scene(x + w * amp * 0.3, AU_SHORE + d * 1.35 + w * amp, t, p, px);
        float reflectance = mix(0.55, 0.3, k);
        col = mirror * reflectance * (1.0 + w * 0.25 * k) + locky_color(p, 0) * 0.25;
    }

    // Keep the brightest aurora from clipping, then a soft vignette and dither against banding.
    col = select(col, 0.78 + 0.22 * tanh((col - 0.78) / 0.22), col > 0.78);
    float2 c = (uv - 0.5) * float2(1.0, 0.85);
    col *= 1.0 - 0.45 * dot(c, c);
    col += (au_h2(floor(uv * res)) - 0.5) / 255.0;
    return float4(col, 1.0);
}
