// Synthwave: a neon sunset over a perspective grid.
// Positions are in layout points (Locky lays themes out for 1440x900 and scales them to the screen), x from
// the screen's center and y down from the top, so the sun stays under the clock on every screen.
// Colors: 0 sky top, 1 sky middle, 2 horizon pink, 3 sun top, 4 mountains, 5 grid magenta, 6 grid cyan.
// Params: 0 horizon (points from the top, 560), 1 sun radius (points, 175), 2 grid speed (cells a second, 0.45)

static float sw_hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
static float sw_hash1(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

// Straight lines between random heights: a low-poly ridge.
static float sw_peaks(float x, float seed) {
    float i = floor(x);
    return mix(sw_hash1(i + seed), sw_hash1(i + 1.0 + seed), fract(x));
}

// Mountain height above the horizon, in points: low behind the sun, rising toward the sides.
static float sw_ridge(float x) {
    float side = smoothstep(90.0, 620.0, abs(x));
    return 6.0 + 14.0 * sw_peaks(x / 26.0, 19.0) + side * (50.0 + 115.0 * sw_peaks(x / 88.0, 7.0));
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float s = min(res.x / 1440.0, res.y / 900.0);                        // pixels per point
    float2 P = float2((uv.x - 0.5) * res.x, (1.0 - uv.y) * res.y) / s;   // points
    float px = 1.0 / s;                                                  // one pixel, in points
    float horizon = locky_param(p, 0, 560.0);
    float R = locky_param(p, 1, 175.0);
    float speed = locky_param(p, 2, 0.45);

    float3 skyTop = locky_color(p, 0), skyMid = locky_color(p, 1), pink = locky_color(p, 2);
    float3 sunTop = locky_color(p, 3), mountain = locky_color(p, 4);
    float3 magenta = locky_color(p, 5), cyan = locky_color(p, 6);

    // The floor's grid coordinates, worked out for every pixel so their derivatives are defined at the
    // horizon too: a grid on the ground, seen from a low camera, scrolling toward the viewer.
    float dy = P.y - horizon;
    float camera = 3.4, focal = 618.0, ground = max(dy, 0.5);
    float2 g = float2(P.x * camera / ground, focal * camera / ground + fract(t * speed));
    float2 fw = fwidth(g);

    float3 col;
    if (dy < 0.0) {
        // Sky: deep violet, turning hot pink in a band just above the horizon.
        float k = P.y / horizon;
        float3 sky = mix(skyTop, skyMid, smoothstep(0.05, 0.75, k));
        sky = mix(sky, pink, pow(smoothstep(0.74, 1.0, k), 2.0) * 0.92);

        // Stars, fading out toward the horizon.
        float2 cell = floor(P / 9.0);
        float h = sw_hash(cell);
        if (h > 0.92) {
            float2 c = (cell + 0.2 + 0.6 * float2(sw_hash(cell + 1.3), sw_hash(cell + 2.7))) * 9.0;
            float r = mix(0.45, 1.15, sw_hash(cell + 4.1));
            float star = 1.0 - smoothstep(r - px * 0.5, r + px, length(P - c));
            float twinkle = 0.6 + 0.4 * sin(t * (0.7 + 1.6 * sw_hash(cell + 5.9)) + h * 60.0);
            sky += star * twinkle * (1.0 - smoothstep(0.3, 0.72, k)) * float3(1.0, 0.92, 1.0);
        }

        // The sun: orange at the top to pink at the bottom, cut by bands that widen as they drift down. The
        // gaps are a dark violet, so the bands read down to the horizon.
        float sunY = horizon - 0.38 * R;
        float d = length(float2(P.x, P.y - sunY)) - R;
        float3 glow = mix(sunTop, pink, 0.6) * 0.5 * exp(-max(d, 0.0) / 75.0);
        float v = (P.y - sunY) / R;
        float period = 0.13;
        float q = fract(v / period - fract(t * 0.03));
        float gap = smoothstep(-0.55, 0.45, v) * 0.75;
        float aa = px / (R * period);
        float band = mix(1.0, smoothstep(gap - aa, gap + aa, q), smoothstep(0.0, 2.0 * aa, gap));
        float3 sunCol = mix(sunTop, pink, smoothstep(-0.85, 0.6, v));
        float3 disk = mix(mix(skyMid, pink, 0.3) * 0.75, sunCol, band);
        col = mix(sky + glow, disk, 1.0 - smoothstep(-px, px, d));

        // Mountains: a dark violet silhouette with a magenta rim, glowing faintly along the ridge.
        float height = sw_ridge(P.x);
        float slope = sw_ridge(P.x + 0.5) - sw_ridge(P.x - 0.5);
        float below = (P.y - (horizon - height)) / sqrt(1.0 + slope * slope);   // points under the ridge
        float3 rock = mix(mountain, mountain * 0.45, smoothstep(0.0, 1.0, (P.y - (horizon - height)) / max(height, 1.0)));
        col = mix(col, rock, smoothstep(-px, px, below));
        col += magenta * (exp(-abs(below) / 1.1) * 0.95 + exp(-max(-below, 0.0) / 9.0) * 0.18 * step(below, 0.0));
    } else {
        // The floor's grid lines. Where they crowd together toward the horizon they melt into their
        // average glow instead of shimmering.
        float2 dpx = abs(fract(g + 0.5) - 0.5) / max(fw, float2(1e-5));     // pixels from the nearest line
        float2 lines = (1.0 - smoothstep(0.35, 1.35, dpx)) + exp(-dpx * 0.5) * 0.5;
        lines = mix(lines, min(fw * 2.4, 1.0) * float2(0.2, 0.42), smoothstep(0.25, 0.7, fw));

        float fog = exp(-dy / 45.0);
        col = mix(skyTop * 0.85, mix(pink, magenta, 0.3) * 0.36, fog);
        col += pink * 0.3 * exp(-dy / 22.0);                            // haze under the horizon
        col += pink * 0.28 * exp(-abs(P.x) / 140.0) * exp(-dy / 60.0);   // the sun's reflection
        col += (cyan * lines.x * 0.85 + magenta * lines.y) * (1.0 - fog * 0.5);

        // A darker floor under the password field, so it reads over the grid.
        float2 pad = float2(P.x / 300.0, (P.y - (res.y / s - 96.0)) / 90.0);
        col *= 1.0 - 0.6 * exp(-dot(pad, pad));
    }

    // The horizon: a hot line with a haze above and below.
    float ad = abs(dy);
    col += pink * (exp(-ad / 1.4) * 0.9 + exp(-ad / 26.0) * 0.28) + float3(1.0, 0.85, 0.95) * exp(-ad / 0.8) * 0.35;

    float2 c = uv - 0.5;
    col *= 1.0 - dot(c, c) * 0.55;
    col += (sw_hash(uv * res + fract(t)) - 0.5) / 255.0;
    return float4(col, 1.0);
}
