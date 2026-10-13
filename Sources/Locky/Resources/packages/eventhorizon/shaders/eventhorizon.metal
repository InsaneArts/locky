// Event Horizon: a black hole seen almost edge-on, after Interstellar's Gargantua. A thin accretion disk crosses in
// front of the shadow; gravity bends the disk's far side into a halo around the top and bottom of the shadow, and
// bends the stars behind it. The disk turns, faster near the hole, and its approaching side is brighter.
// Positions are in layout points from the hole's center (y down), so it keeps its shape on every screen.
// Colors: 0 space, 1 the disk's hot inner edge, 2 its middle, 3 its cool outer edge.
// Params: 0 the hole's center, points from the top (470), 1 the shadow's radius (80), 2 how fast the disk turns (1).

static float eh_sq(float x) { return x * x; }

static float eh_hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float eh_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(eh_hash(i), eh_hash(i + float2(1, 0)), u.x), mix(eh_hash(i + float2(0, 1)), eh_hash(i + float2(1, 1)), u.x), u.y);
}

// Streaks along the orbit: noise stretched about five times along the angle, so gas reads as lanes circling the
// hole. The angle runs around a circle in noise space, so there is no seam.
static float eh_lanes(float rho, float phi) {
    float2 around = float2(cos(phi), sin(phi));
    float v = 0.0, a = 0.6, f = 1.0;
    for (int i = 0; i < 3; i++) {
        v += a * eh_noise(float2(rho / 30.0 * f, 0.0) + around * (1.6 * f) + float2(i * 5.3, i * 9.1));
        a *= 0.5;
        f *= 2.3;
    }
    return v / 1.05;
}

// The disk's light at radius rho (points, in the disk's plane) and angle phi: hot and white inside, red outside,
// in lanes that turn with Kepler's law. `side` is -1..1 across the view, for the approaching side's boost.
static float3 eh_disk(float rho, float phi, float side, float Rs, float t, float speed, constant LockyParams &p) {
    float rin = Rs * 1.4, rout = Rs * 4.9;
    if (rho < rin * 0.85 || rho > rout * 1.1) return float3(0.0);
    float x = (rho - rin) / (rout - rin);                          // 0 inside .. 1 outside
    float omega = speed * 0.9 * pow(rin / max(rho, rin * 0.85), 1.5);
    float lanes = eh_lanes(rho, phi - t * omega);
    float body = smoothstep(-0.06, 0.04, x) * (1.0 - smoothstep(0.55, 1.05, x));
    float heat = pow(1.0 - clamp(x, 0.0, 1.0), 1.6);
    float3 col = mix(locky_color(p, 3), locky_color(p, 2), smoothstep(0.15, 0.6, heat));
    col = mix(col, locky_color(p, 1), smoothstep(0.6, 0.95, heat));
    float doppler = 1.0 + 0.55 * side;
    return col * body * (0.25 + 1.6 * lanes * lanes) * (0.5 + 1.6 * heat) * doppler;
}

static float3 eh_stars(float2 q) {
    float3 col = float3(0.0);
    for (int layer = 0; layer < 2; layer++) {
        float size = layer == 0 ? 7.0 : 19.0;
        float2 cell = floor(q / size + layer * 13.0);
        float h = eh_hash(cell);
        if (h > (layer == 0 ? 0.93 : 0.975)) {
            float2 c = (cell - layer * 13.0 + 0.25 + 0.5 * float2(eh_hash(cell + 1.7), eh_hash(cell + 3.1))) * size;
            float d = length(q - c);
            float b = layer == 0 ? 0.55 : 1.0;
            col += b * exp(-d * d / (layer == 0 ? 0.35 : 0.9)) * mix(float3(1.0, 0.85, 0.7), float3(0.75, 0.85, 1.0), eh_hash(cell + 9.0));
        }
    }
    return col;
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float s = min(res.x / 1440.0, res.y / 900.0);
    float centerY = locky_param(p, 0, 470.0);
    float Rs = locky_param(p, 1, 80.0);
    float speed = locky_param(p, 2, 1.0);
    float2 q = float2((uv.x - 0.5) * res.x, (1.0 - uv.y) * res.y) / s - float2(0.0, centerY);
    float px = 1.0 / s;
    float r = length(q);
    float theta = atan2(q.y, q.x);

    // The disk is tilted a few degrees from edge-on, and a little rolled, as in the film.
    float roll = -0.06;
    float2 qr = float2(q.x * cos(roll) - q.y * sin(roll), q.x * sin(roll) + q.y * cos(roll));
    float tilt = 0.13;

    // Stars behind, pulled outward around the hole (an Einstein ring at 1.9 Rs).
    float re = Rs * 1.9;
    float2 src = q * (1.0 - re * re / max(r * r, 1.0));
    // Stars right at the ring would stretch into a dotted circle: they fade there.
    float3 col = locky_color(p, 0) + eh_stars(src) * smoothstep(Rs * 1.05, Rs * 1.6, r) * smoothstep(Rs * 0.1, Rs * 0.5, abs(r - re));
    // A faint blue haze of the galaxy behind, also bent.
    col += float3(0.05, 0.06, 0.1) * eh_noise(src * 0.004 + 3.0) * smoothstep(Rs, Rs * 3.0, r);

    // The far side of the disk, bent up over the shadow and under it: a halo hugging the shadow. Its radius in the
    // disk maps from just outside the photon ring outward; the top image is wide, the bottom one thin.
    float top = qr.y < 0.0 ? 1.0 : 0.0;
    float width = mix(0.32, 0.62, top) * Rs;
    float u = (r - Rs * 1.03) / width;
    if (u > -0.1 && u < 1.6) {
        float rho = Rs * 1.4 + max(u, 0.0) * Rs * 2.4;
        float side = -cos(theta);
        float3 halo = eh_disk(rho, theta * 1.0 + 3.14159, side * 0.6, Rs, t, speed, p);
        float fade = smoothstep(-0.1, 0.12, u) * (1.0 - smoothstep(0.7, 1.6, u));
        // Squeezed where the halo meets the direct disk, at the sides.
        fade *= mix(0.55, 1.0, smoothstep(0.0, 0.6, abs(sin(theta))));
        col += halo * fade * mix(0.7, 1.35, top);
    }

    // The photon ring: a thin bright line at the shadow's edge, then the shadow itself.
    float ring = exp(-eh_sq((r - Rs * 1.02) / (1.6 * px + Rs * 0.012)));
    col += locky_color(p, 1) * ring * 0.9;
    float shadow = smoothstep(Rs * 0.985, Rs * 0.985 - 1.5 * px, r);
    col = mix(col, float3(0.0), shadow);

    // The near side of the disk, in front of everything; the back half of it hides behind the shadow.
    float2 plane = float2(qr.x, qr.y / tilt);
    float rho = length(plane);
    float phi = atan2(plane.y, plane.x);
    float behind = (plane.y < 0.0) ? shadow : 0.0;
    float3 disk = eh_disk(rho, phi, -plane.x / max(rho, 1.0), Rs, t, speed, p);
    // Thin edge-on: soften vertically by a pixel so it does not alias.
    col += disk * (1.0 - behind);

    // Bloom: the hot inner disk lights the space around it.
    float glow = exp(-abs(qr.y) / (Rs * 0.35)) * exp(-eh_sq(qr.x / (Rs * 4.2))) * smoothstep(Rs * 0.9, Rs * 1.6, r);
    col += locky_color(p, 2) * glow * 0.18;
    col += locky_color(p, 1) * exp(-max(r - Rs, 0.0) / (Rs * 0.5)) * 0.12 * (1.0 - shadow);

    // Filmic tone map, so the hot core rolls off to white instead of clipping to flat yellow.
    col = 1.0 - exp(-col * 1.25);
    return float4(col, 1.0);
}
