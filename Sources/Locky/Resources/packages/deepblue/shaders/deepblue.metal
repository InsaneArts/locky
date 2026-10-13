// Deep Blue: under the sea, looking up. Light falls in shifting rays from a rippling surface, caustics play near the
// top, specks drift up through the water, and every couple of minutes a whale glides slowly across, far off.
// Positions are in layout points (x from the center, y down from the top).
// Colors: 0 the deep, 1 the water higher up, 2 the light at the surface, 3 the whale.
// Params: 0 seconds between the whale's passes (150), 1 how bright the rays are (1).

static float db_hash(float2 p) {
    p = fract(p * float2(331.73, 173.91));
    p += dot(p, p + 17.13);
    return fract(p.x * p.y);
}

static float db_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(db_hash(i), db_hash(i + float2(1, 0)), u.x), mix(db_hash(i + float2(0, 1)), db_hash(i + float2(1, 1)), u.x), u.y);
}

// Caustics: the bright web light makes through a moving surface, from the minimum of a few warped cell distances.
static float db_caustics(float2 p, float t) {
    float2 q = p;
    float c = 0.0;
    for (int i = 0; i < 3; i++) {
        q += float2(sin(q.y * 1.3 + t * 0.6 + i), cos(q.x * 1.1 - t * 0.5 + i * 2.0)) * 0.35;
        float2 g = fract(q) - 0.5;
        c += 1.0 - smoothstep(0.0, 0.5, length(g) * (1.0 + 0.2 * sin(t + i)));
        q *= 1.6;
    }
    return pow(c / 3.0, 3.0);
}

// Distance to a tapered limb from a (width wa) to b (width wb).
static float db_limb(float2 q, float2 a, float2 b, float wa, float wb) {
    float2 pa = q - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - mix(wa, wb, h);
}

// A humpback seen from below, in its own frame: x along the body (nose at +0.5), y across, in body lengths. Returns
// the distance to its outline (negative inside). `beat` is the stroke: the fins flex, the flukes fold up and down.
static float db_whale(float2 q, float beat) {
    float x = q.x;
    float u = clamp((x - 0.04) / 0.5, -1.0, 1.0);
    // A blunt head, the widest point a third of the way back, a long taper to the tail stock.
    float w = 0.115 * pow(max(1.0 - u * u, 0.0), 0.38) * mix(0.16, 1.0, smoothstep(-0.5, 0.0, x));
    float body = max(abs(q.y) - w, max(-0.47 - x, x - 0.54));
    float y = abs(q.y);
    // The long pectoral fins of a humpback, bending back, with a bumpy leading edge; their tips lift with the stroke.
    float2 f = float2(x, y);
    float tip = beat * 0.015;
    float fin = min(db_limb(f, float2(0.2, 0.08), float2(0.13, 0.2), 0.04, 0.026),
                    db_limb(f, float2(0.13, 0.2), float2(-0.01, 0.3 + tip), 0.026, 0.006));
    fin += 0.0022 * sin(y * 120.0) * step(0.1, y);
    // The flukes: a wide crescent, the tips swept back; the span shrinks as they fold with the stroke.
    float span = 0.9 + 0.1 * beat;
    float flukes = min(db_limb(f, float2(-0.45, 0.0), float2(-0.52, 0.09 * span), 0.035, 0.028),
                       db_limb(f, float2(-0.52, 0.09 * span), float2(-0.6, 0.18 * span), 0.028, 0.005));
    return min(body, min(fin, flukes));
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float s = min(res.x / 1440.0, res.y / 900.0);
    float2 P = float2((uv.x - 0.5) * res.x, (1.0 - uv.y) * res.y) / s;
    float period = locky_param(p, 0, 150.0);
    float rays = locky_param(p, 1, 1.0);
    float3 deep = locky_color(p, 0), water = locky_color(p, 1), surface = locky_color(p, 2);

    // Water: lighter toward the surface, the brightest spot where the sun is.
    float k = clamp(P.y / 900.0, 0.0, 1.0);
    float3 col = mix(water, deep, smoothstep(0.0, 1.0, k));
    float2 sun = float2(-180.0, -260.0);
    col += surface * 0.35 * exp(-length(P - sun) / 380.0);

    // Rays: bands fanning down from the sun, shimmering as the surface moves.
    float2 d = P - sun;
    float a = atan2(d.x, d.y);
    float bands = db_noise(float2(a * 9.0, t * 0.15)) * 0.6 + db_noise(float2(a * 23.0, t * 0.3 + 4.0)) * 0.4;
    float shaft = smoothstep(0.45, 0.85, bands) * exp(-length(d) / 900.0) * smoothstep(0.0, 300.0, length(d));
    col += surface * shaft * 0.4 * rays;

    // Caustics near the top, fading with depth.
    float c = db_caustics(P * 0.006 + float2(0.0, t * 0.02), t * 0.8);
    col += surface * c * 0.2 * (1.0 - smoothstep(0.0, 0.4, k));

    // The whale: a silhouette between you and the light, gliding from left to right with a slow stroke.
    // It starts in view, so a lock shows it at once.
    float phase = fract(t / period + 0.52);
    float span = 2600.0;
    float2 at = float2(-span * 0.5 + phase * span, 540.0 + 30.0 * sin(phase * 6.28));
    float size = 560.0;
    float2 q = (P - at) / size;
    q.y += q.x * 0.1;  // heading a little upward across the screen
    float dist = db_whale(q, sin(t * 0.7)) * size;
    float whale = smoothstep(1.5, -1.5, dist);
    float3 body = mix(col, locky_color(p, 3), 0.82);
    // Faint grooves along the throat and belly.
    float grooves = step(0.1, q.x) * smoothstep(0.08, 0.02, abs(q.y)) * (0.5 + 0.5 * sin(q.y * 260.0));
    body += surface * 0.025 * grooves;
    // Light wraps faintly around its edge.
    col += surface * 0.12 * exp(-max(dist, 0.0) / 6.0) * (1.0 - whale);
    col = mix(col, body, whale);

    // Specks of plankton drifting upward, some catching the light.
    for (int layer = 0; layer < 3; layer++) {
        float size = 26.0 + layer * 22.0;
        float2 g = P / size + float2(0.0, t * (0.08 + layer * 0.05));
        g.x += sin(g.y * 0.7 + layer) * 0.3;
        float2 id = floor(g);
        float h = db_hash(id + layer * 5.0);
        if (h > 0.82) {
            float2 cpos = float2(db_hash(id + 1.3), db_hash(id + 2.9)) * 0.6 + 0.2;
            float dd = length((fract(g) - cpos) * size);
            float r = 0.6 + layer * 0.5;
            col += mix(surface, float3(1.0), 0.3) * exp(-dd * dd / (r * r)) * (0.18 + 0.2 * layer) * (1.0 - k * 0.6)
                 * (0.6 + 0.4 * sin(t * 2.0 + h * 40.0));
        }
    }

    // Grain and a vignette, so the deep blue does not band.
    float2 v = uv - 0.5;
    col *= 1.0 - 0.4 * dot(v, v) * 2.0;
    col += (db_hash(P + fract(t * 0.37)) - 0.5) * 0.012;
    return float4(max(col, 0.0), 1.0);
}
