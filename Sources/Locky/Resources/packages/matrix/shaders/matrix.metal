// Matrix: digital rain. Columns of glyphs fall at their own speeds, each stream led by a bright head and fading
// behind it; glyphs change now and then. The glyphs are strokes picked at random on a small lattice, so they read as
// an unknown script. The middle of the screen is darker, so a clock there stays legible.
// Colors: 0 the background, 1 the rain, 2 the heads.
// Params: 0 how many streams (default 1), 1 how much the middle darkens (default 0.6).

// Inputs are whole cell numbers, so the hash must not repeat on integers.
static float matrix_hash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

// How much of a glyph covers `f` (0…1 in its cell): up to 17 strokes on a 3 × 4 lattice.
static float matrix_glyph(float2 f, float seed) {
    f = (f - 0.5) * float2(1.5, 1.3) + 0.5;  // a margin around the glyph
    if (f.x < -0.1 || f.x > 1.1 || f.y < -0.1 || f.y > 1.1) return 0.0;
    float d = 1.0;
    for (int i = 0; i < 17; i++) {
        if (matrix_hash(float2(seed, float(i))) > 0.38) continue;
        float2 a, b;
        if (i < 8) {  // horizontal: 4 rows, 2 spans each
            float y = float(i / 2) / 3.0, x = float(i % 2) * 0.5;
            a = float2(x, y); b = float2(x + 0.5, y);
        } else {      // vertical: 3 columns, 3 spans each
            int j = i - 8;
            float x = float(j / 3) * 0.5, y = float(j % 3) / 3.0;
            a = float2(x, y); b = float2(x, y + 1.0 / 3.0);
        }
        float2 pa = f - a, ba = b - a;
        float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        d = min(d, length(pa - ba * h));
    }
    return smoothstep(0.11, 0.05, d);
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float aspect = res.x / res.y;
    float rows = 40.0;
    float cols = floor(rows * aspect * 1.35);
    float2 g = float2(uv.x * cols, uv.y * rows);
    float2 cell = floor(g), f = fract(g);
    float density = locky_param(p, 0, 1.0);

    // Two streams per column, each with its own speed, length, and start.
    float bright = 0.0, head = 0.0;
    for (int k = 0; k < 2; k++) {
        float2 id = float2(cell.x, float(k) * 17.0);
        if (matrix_hash(id + 3.0) > 0.55 + 0.4 * density) continue;
        float speed = 5.0 + 9.0 * matrix_hash(id);           // rows per second
        float span = rows * (1.4 + matrix_hash(id + 1.0));   // a fall, plus a pause off screen
        float length = 8.0 + 22.0 * matrix_hash(id + 2.0);
        float at = rows - fmod(t * speed + matrix_hash(id + 4.0) * span, span);  // the head's row, falling
        float behind = cell.y - at;                          // rows above the head
        if (behind >= 0.0 && behind < length) {
            bright = max(bright, pow(1.0 - behind / length, 1.6));
            head = max(head, 1.0 - smoothstep(0.0, 1.0, behind));
        }
    }

    // Some glyphs change often, most rarely.
    float rate = matrix_hash(cell + 9.0) > 0.85 ? 6.0 : 0.3;
    float seed = matrix_hash(cell + floor(t * rate + matrix_hash(cell) * 10.0));
    float glyph = matrix_glyph(f, seed * 97.0);

    float3 col = locky_color(p, 0);
    float faint = 0.05;  // the code that is always there, dimly
    col += locky_color(p, 1) * glyph * max(bright, faint);
    col = mix(col, locky_color(p, 2), glyph * head);

    float2 c = (uv - float2(0.5, 0.55)) * float2(aspect, 1.0);
    col *= 1.0 - locky_param(p, 1, 0.6) * exp(-dot(c, c) * 5.0);
    return float4(col, 1.0);
}
