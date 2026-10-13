// Blueprint: a print on drafting paper in Prussian blue. A fine grid with a heavier line every fifth, a double
// border with zone ticks, the mottling of the print, and soft creases where the sheet was folded.
// Colors: 0 the paper, 1 the lines.
// Params: 0 grid cells across the screen's height (default 40).

static float blueprint_hash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

static float blueprint_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(blueprint_hash(i), blueprint_hash(i + float2(1, 0)), f.x),
               mix(blueprint_hash(i + float2(0, 1)), blueprint_hash(i + float2(1, 1)), f.x), f.y);
}

// How much a line `width` pixels wide at distance `d` pixels covers a pixel.
static float blueprint_line(float d, float width) {
    return 1.0 - smoothstep(width * 0.5, width * 0.5 + 1.0, d);
}

float4 shade(float2 uv, float t, float2 res, constant LockyParams &p) {
    float2 px = uv * res;
    float unit = res.y / 1000.0;  // a thousandth of the height, so lines keep their weight at any resolution
    float cell = res.y / locky_param(p, 0, 40.0);

    float2 g = abs(fract(px / cell + 0.5) - 0.5) * cell;
    float2 G = abs(fract(px / (cell * 5.0) + 0.5) - 0.5) * cell * 5.0;
    float fine = max(blueprint_line(g.x, 0.8 * unit), blueprint_line(g.y, 0.8 * unit));
    float major = max(blueprint_line(G.x, 1.6 * unit), blueprint_line(G.y, 1.6 * unit));
    float ink = max(fine * 0.13, major * 0.24);

    // The border: a heavy outer line, a thin inner one, and a zone tick between them every eighth of the width.
    float outer = 22.0 * unit, inner = 40.0 * unit;
    float2 e = min(px, res - px);
    float edge = min(e.x, e.y);
    ink = max(ink, blueprint_line(abs(edge - outer), 3.0 * unit) * 0.85);
    ink = max(ink, blueprint_line(abs(edge - inner), 1.4 * unit) * 0.7);
    float zone = abs(fract(uv.x * 8.0 + 0.5) - 0.5) * res.x / 8.0;
    float zoneY = abs(fract(uv.y * 6.0 + 0.5) - 0.5) * res.y / 6.0;
    bool band = edge > outer && edge < inner;
    if (band && e.y < e.x) ink = max(ink, blueprint_line(zone, 1.4 * unit) * 0.7);
    if (band && e.x <= e.y) ink = max(ink, blueprint_line(zoneY, 1.4 * unit) * 0.7);
    if (edge < outer) ink *= 0.0;

    float3 col = mix(locky_color(p, 0), locky_color(p, 1), ink);

    // The print: uneven blue, lighter creases at the folds, darker toward the corners, and grain.
    float mottle = blueprint_noise(uv * float2(res.x / res.y, 1.0) * 3.0) * 0.6 + blueprint_noise(uv * 11.0) * 0.4;
    col *= 0.93 + 0.12 * mottle;
    float crease = exp(-pow((uv.x - 1.0 / 3.0) * 90.0, 2.0)) + exp(-pow((uv.x - 2.0 / 3.0) * 90.0, 2.0))
                 + exp(-pow((uv.y - 0.5) * 90.0, 2.0));
    col += crease * 0.025;
    float2 c = uv - 0.5;
    col *= 1.0 - 0.35 * dot(c, c);
    col += (blueprint_hash(px) - 0.5) * 0.025;
    return float4(col, 1.0);
}
