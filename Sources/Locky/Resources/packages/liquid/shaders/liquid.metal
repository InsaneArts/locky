// Liquid: color poured into color, folding over itself like silk. Noise warps noise that warps noise, so the flow
// never repeats; the folds catch a soft light, as if the surface had a sheen.
// Colors: 0 to 3, the paints from deepest to brightest. 4 the sheen.
// Params: 0 how fast it flows (1), 1 how large the folds are (1), 2 how much sheen (1).

static float lq_hash(float2 p) {
    p = fract(p * float2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}

static float lq_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(mix(lq_hash(i), lq_hash(i + float2(1, 0)), u.x), mix(lq_hash(i + float2(0, 1)), lq_hash(i + float2(1, 1)), u.x), u.y);
}

static float lq_fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * lq_noise(p);
        p = float2(p.x * 1.7 - p.y * 1.1, p.x * 1.1 + p.y * 1.7) + 3.1;
        a *= 0.42;
    }
    return v;
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float speed = locky_param(p, 0, 1.0);
    float scale = locky_param(p, 1, 1.0);
    float sheen = locky_param(p, 2, 1.0);
    float aspect = res.x / res.y;
    float2 P = float2(uv.x * aspect, uv.y) * 0.85 / scale;
    float T = t * 0.045 * speed;

    // Each layer pushes the next one around.
    float2 q = float2(lq_fbm(P + float2(0.0, T)), lq_fbm(P + float2(5.2, 1.3) - T * 0.7));
    float2 r = float2(lq_fbm(P + 3.0 * q + float2(1.7, 9.2) + T * 0.6), lq_fbm(P + 3.0 * q + float2(8.3, 2.8) - T * 0.4));
    float h = lq_fbm(P + 3.2 * r);

    // Paint: the field picks a place along the palette, and the warp vectors tint it.
    float3 col = mix(locky_color(p, 0), locky_color(p, 1), smoothstep(0.2, 0.5, h));
    col = mix(col, locky_color(p, 2), smoothstep(0.35, 0.65, q.y) * smoothstep(0.3, 0.6, h));
    col = mix(col, locky_color(p, 3), smoothstep(0.38, 0.62, r.x) * smoothstep(0.3, 0.6, h));
    col *= 0.6 + 0.7 * h;

    // A sheen on the folds: the field's slope as a surface normal, lit from the upper left.
    float2 grad = float2(dfdx(h), dfdy(h)) * res.y * 0.12 * scale;
    float3 n = normalize(float3(-grad, 1.0));
    float3 light = normalize(float3(-0.5, 0.6, 0.8));
    float3 halfway = normalize(light + float3(0.0, 0.0, 1.0));
    float spec = pow(max(dot(n, halfway), 0.0), 28.0);
    float diffuse = max(dot(n, light), 0.0);
    col *= 0.75 + 0.35 * diffuse;
    col += locky_color(p, 4) * spec * 0.45 * sheen;

    // A vignette keeps the edges deep, so text in the corners stays readable.
    float2 c = uv - 0.5;
    col *= 1.0 - 0.45 * dot(c, c) * 2.0;
    return float4(col, 1.0);
}
