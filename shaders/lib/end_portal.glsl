#ifndef YUNMENG_END_PORTAL
#define YUNMENG_END_PORTAL
#ifndef SKY_STYLE
#define SKY_STYLE 0 // [0 1] 0: Wuxia Smooth, 1: Minecraft Voxel
#endif
#ifndef END_PORTAL_LAYERS
#define END_PORTAL_LAYERS 3 // [2 3 4] Layered portal depth
#endif
#ifndef END_GLYPH_STYLE
#define END_GLYPH_STYLE 0 // [0 1 2 3] 0: Auto (By Shader Style), 1: Classical Chinese, 2: Enchanting Table (SGA), 3: Off
#endif
#define ACTIVE_END_GLYPH_STYLE ((END_GLYPH_STYLE == 0) ? ((SKY_STYLE == 1) ? 2 : 1) : END_GLYPH_STYLE)

uniform sampler2D portalInkTex;
uniform sampler2D portalCloudTex;

bool isYunMengEndPortal(float material) { return abs(material - 0.98) < 0.006; }

float portalHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Infinite-Resolution Analytic Calligraphic Brush Stroke SDF:
// Evaluates a tapered, gently curved brush stroke from a to b with start width w0 and end width w1.
// Remains 100% razor-sharp at any camera zoom level (never blobby or pixelated like a low-res bitmap).
float sdBrushStroke(vec2 p, vec2 a, vec2 b, float bend, float w0, float w1) {
    vec2 ba = b - a;
    float denom = max(dot(ba, ba), 1e-6);
    float t = clamp(dot(p - a, ba) / denom, 0.0, 1.0);
    vec2 n = vec2(-ba.y, ba.x) * inversesqrt(denom);
    vec2 curvePt = a + ba * t + n * (bend * 4.0 * t * (1.0 - t));
    float w = mix(w0, w1, t);
    return length(p - curvePt) - w;
}

// Evaluates 6 authentic Classical Chinese Void Characters using exact analytic brush strokes:
// 0: 太 (Tai - Great Void), 1: 玄 (Xuan - Mystic Cosmos), 2: 云 (Yun - Cloud Dream),
// 3: 天 (Tian - Firmament), 4: 道 (Dao - Cosmic Order), 5: 空 (Kong - Boundless Emptiness)
float sampleEndVectorCjkGlyph(int charIdx, vec2 uv) {
    if (uv.x < 0.02 || uv.x > 0.98 || uv.y < 0.02 || uv.y > 0.98) return 0.0;
    // Flip Y so y=0 is top and y=1 is bottom matching traditional stroke order
    vec2 p = vec2(uv.x, 1.0 - uv.y);
    float d = 10.0;
    int id = int(mod(float(charIdx), 8.0));

    if (id == 0) {
        // 太 (Tai)
        d = min(d, sdBrushStroke(p, vec2(0.16, 0.36), vec2(0.84, 0.34), -0.01, 0.032, 0.034));
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.14), vec2(0.18, 0.84),  0.06, 0.036, 0.018));
        d = min(d, sdBrushStroke(p, vec2(0.46, 0.44), vec2(0.84, 0.84), -0.05, 0.020, 0.038));
        d = min(d, sdBrushStroke(p, vec2(0.42, 0.68), vec2(0.52, 0.80),  0.01, 0.020, 0.032));
    } else if (id == 1) {
        // 玄 (Xuan)
        d = min(d, sdBrushStroke(p, vec2(0.47, 0.11), vec2(0.53, 0.21),  0.00, 0.022, 0.034));
        d = min(d, sdBrushStroke(p, vec2(0.16, 0.25), vec2(0.84, 0.23), -0.01, 0.030, 0.032));
        d = min(d, sdBrushStroke(p, vec2(0.48, 0.26), vec2(0.28, 0.52),  0.02, 0.030, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.28, 0.52), vec2(0.64, 0.48),  0.00, 0.026, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.62, 0.38), vec2(0.24, 0.80),  0.03, 0.030, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.24, 0.80), vec2(0.72, 0.74),  0.00, 0.028, 0.022));
        d = min(d, sdBrushStroke(p, vec2(0.66, 0.64), vec2(0.78, 0.84),  0.01, 0.020, 0.034));
    } else if (id == 2) {
        // 云 (Yun)
        d = min(d, sdBrushStroke(p, vec2(0.26, 0.24), vec2(0.74, 0.22), -0.01, 0.030, 0.032));
        d = min(d, sdBrushStroke(p, vec2(0.14, 0.44), vec2(0.86, 0.42), -0.01, 0.032, 0.034));
        d = min(d, sdBrushStroke(p, vec2(0.48, 0.44), vec2(0.24, 0.78),  0.02, 0.032, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.24, 0.78), vec2(0.74, 0.73),  0.00, 0.030, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.66, 0.61), vec2(0.80, 0.82),  0.01, 0.020, 0.036));
    } else if (id == 3) {
        // 天 (Tian)
        d = min(d, sdBrushStroke(p, vec2(0.22, 0.24), vec2(0.78, 0.22), -0.01, 0.030, 0.032));
        d = min(d, sdBrushStroke(p, vec2(0.16, 0.46), vec2(0.84, 0.44), -0.01, 0.030, 0.032));
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.24), vec2(0.16, 0.86),  0.06, 0.034, 0.018));
        d = min(d, sdBrushStroke(p, vec2(0.48, 0.46), vec2(0.86, 0.85), -0.05, 0.020, 0.038));
    } else if (id == 4) {
        // 道 (Dao)
        d = min(d, sdBrushStroke(p, vec2(0.46, 0.11), vec2(0.52, 0.20),  0.00, 0.020, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.72, 0.11), vec2(0.64, 0.21),  0.00, 0.024, 0.018));
        d = min(d, sdBrushStroke(p, vec2(0.38, 0.23), vec2(0.84, 0.21), -0.01, 0.026, 0.028));
        d = min(d, sdBrushStroke(p, vec2(0.58, 0.22), vec2(0.54, 0.33),  0.00, 0.024, 0.020));
        d = min(d, sdBrushStroke(p, vec2(0.44, 0.33), vec2(0.44, 0.70),  0.00, 0.026, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.44, 0.33), vec2(0.78, 0.33),  0.00, 0.026, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.78, 0.33), vec2(0.78, 0.70),  0.00, 0.026, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.44, 0.45), vec2(0.76, 0.45),  0.00, 0.020, 0.020));
        d = min(d, sdBrushStroke(p, vec2(0.44, 0.57), vec2(0.76, 0.57),  0.00, 0.020, 0.020));
        d = min(d, sdBrushStroke(p, vec2(0.44, 0.70), vec2(0.78, 0.70),  0.00, 0.024, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.18, 0.20), vec2(0.28, 0.30),  0.00, 0.020, 0.030));
        d = min(d, sdBrushStroke(p, vec2(0.14, 0.46), vec2(0.26, 0.44),  0.00, 0.024, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.26, 0.44), vec2(0.22, 0.74), -0.02, 0.024, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.12, 0.74), vec2(0.88, 0.84), -0.04, 0.028, 0.034));
    } else if (id == 5) {
        // 空 (Kong - Boundless Void)
        d = min(d, sdBrushStroke(p, vec2(0.48, 0.12), vec2(0.52, 0.22),  0.00, 0.024, 0.032));
        d = min(d, sdBrushStroke(p, vec2(0.20, 0.24), vec2(0.80, 0.22), -0.01, 0.028, 0.030));
        d = min(d, sdBrushStroke(p, vec2(0.20, 0.24), vec2(0.16, 0.36),  0.00, 0.026, 0.018));
        d = min(d, sdBrushStroke(p, vec2(0.80, 0.22), vec2(0.74, 0.34),  0.00, 0.028, 0.018));
        d = min(d, sdBrushStroke(p, vec2(0.40, 0.30), vec2(0.22, 0.50),  0.02, 0.028, 0.018));
        d = min(d, sdBrushStroke(p, vec2(0.58, 0.30), vec2(0.78, 0.48), -0.02, 0.024, 0.030));
        d = min(d, sdBrushStroke(p, vec2(0.30, 0.58), vec2(0.70, 0.56),  0.00, 0.026, 0.028));
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.57), vec2(0.50, 0.82),  0.00, 0.028, 0.028));
        d = min(d, sdBrushStroke(p, vec2(0.16, 0.83), vec2(0.84, 0.81), -0.01, 0.030, 0.034));
    } else if (id == 6) {
        // 虚 (Xu - Emptiness / Great Void)
        d = min(d, sdBrushStroke(p, vec2(0.52, 0.11), vec2(0.52, 0.26),  0.00, 0.026, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.52, 0.18), vec2(0.74, 0.17),  0.00, 0.022, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.22, 0.27), vec2(0.82, 0.25), -0.01, 0.028, 0.030));
        d = min(d, sdBrushStroke(p, vec2(0.24, 0.27), vec2(0.16, 0.84),  0.04, 0.028, 0.018));
        d = min(d, sdBrushStroke(p, vec2(0.44, 0.42), vec2(0.44, 0.78),  0.00, 0.024, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.64, 0.42), vec2(0.64, 0.78),  0.00, 0.024, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.30, 0.56), vec2(0.40, 0.68),  0.00, 0.020, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.78, 0.54), vec2(0.68, 0.68),  0.00, 0.024, 0.018));
        d = min(d, sdBrushStroke(p, vec2(0.28, 0.80), vec2(0.84, 0.79), -0.01, 0.028, 0.032));
    } else {
        // 极 (Ji - Ultimate / Cosmic Pole)
        d = min(d, sdBrushStroke(p, vec2(0.14, 0.36), vec2(0.42, 0.34),  0.00, 0.024, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.28, 0.14), vec2(0.28, 0.86),  0.00, 0.028, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.28, 0.40), vec2(0.14, 0.72),  0.02, 0.024, 0.016));
        d = min(d, sdBrushStroke(p, vec2(0.30, 0.44), vec2(0.40, 0.56),  0.00, 0.018, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.46, 0.24), vec2(0.82, 0.22), -0.01, 0.026, 0.028));
        d = min(d, sdBrushStroke(p, vec2(0.58, 0.24), vec2(0.44, 0.82),  0.04, 0.026, 0.018));
        d = min(d, sdBrushStroke(p, vec2(0.56, 0.46), vec2(0.80, 0.44),  0.00, 0.024, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.78, 0.44), vec2(0.48, 0.84),  0.03, 0.026, 0.018));
        d = min(d, sdBrushStroke(p, vec2(0.54, 0.54), vec2(0.86, 0.84), -0.04, 0.020, 0.034));
    }

    float edgeDist    = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float auraMask    = smoothstep(0.02, 0.16, edgeDist);
    float crispStroke = 1.0 - smoothstep(-0.008, 0.010, d);
    float softAura    = exp(-max(d, 0.0) * 22.0) * 0.26 * auraMask;
    return clamp(crispStroke + softAura, 0.0, 1.0);
}

// Canonical 5x5 Standard Galactic Alphabet (Minecraft Enchanting Table) Bitmaps:
// 0:Y, 1:U, 2:N, 3:M, 4:E, 5:G, 6:V, 7:O, 8:I, 9:D
const int END_SGA_BITMAPS[10] = int[10](
    0x07114a11, // Y
    0x047f1555, // U
    0x1d17d557, // N
    0x1b45554e, // M
    0x1f475407, // E
    0x0e47901e, // G
    0x04113955, // V
    0x0e45544e, // O
    0x0e111004, // I
    0x0e493907  // D
);

float sampleEndSgaGlyph(int sgaIdx, vec2 uv) {
    if (uv.x < 0.10 || uv.x > 0.90 || uv.y < 0.10 || uv.y > 0.90) return 0.0;
    vec2 normUV = (uv - 0.12) / 0.76;
    if (normUV.x < 0.0 || normUV.x >= 1.0 || normUV.y < 0.0 || normUV.y >= 1.0) return 0.0;
    ivec2 cell = clamp(ivec2(floor(normUV * 5.0)), ivec2(0), ivec2(4));
    int mask = END_SGA_BITMAPS[clamp(sgaIdx, 0, 9)];
    int bitIndex = (4 - cell.y) * 5 + cell.x;
    return float((mask >> bitIndex) & 1);
}

// Tapered Calligraphic Brush-Stroke Versions of the 10 Canonical SGA Glyphs (for Wuxia Smooth):
// Uses the exact same Y, U, N, M, E, G, V, O, I, D alphabet as Voxel, rendered as soft glowing brush strokes.
float sampleEndBrushSgaGlyph(int sgaIdx, vec2 uv) {
    if (uv.x < 0.04 || uv.x > 0.96 || uv.y < 0.04 || uv.y > 0.96) return 0.0;
    vec2 p = vec2(uv.x, 1.0 - uv.y);
    float d = 10.0;
    int id = int(mod(float(sgaIdx), 10.0));

    if (id == 0) {
        // Y
        d = min(d, sdBrushStroke(p, vec2(0.18, 0.16), vec2(0.36, 0.36),  0.01, 0.030, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.36, 0.36), vec2(0.36, 0.62),  0.00, 0.028, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.80, 0.16), vec2(0.80, 0.84), -0.02, 0.032, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.18, 0.82), vec2(0.28, 0.82),  0.00, 0.026, 0.032));
    } else if (id == 1) {
        // U
        d = min(d, sdBrushStroke(p, vec2(0.16, 0.20), vec2(0.64, 0.20), -0.01, 0.030, 0.032));
        d = min(d, sdBrushStroke(p, vec2(0.26, 0.38), vec2(0.84, 0.38), -0.01, 0.030, 0.032));
        d = min(d, sdBrushStroke(p, vec2(0.22, 0.48), vec2(0.22, 0.84),  0.01, 0.028, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.54, 0.44), vec2(0.54, 0.84),  0.00, 0.028, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.82, 0.66), vec2(0.82, 0.84),  0.00, 0.026, 0.030));
    } else if (id == 2) {
        // N
        d = min(d, sdBrushStroke(p, vec2(0.18, 0.16), vec2(0.18, 0.82),  0.01, 0.030, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.18, 0.36), vec2(0.76, 0.34), -0.01, 0.030, 0.032));
        d = min(d, sdBrushStroke(p, vec2(0.82, 0.16), vec2(0.82, 0.84), -0.01, 0.030, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.36), vec2(0.50, 0.82),  0.00, 0.026, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.18, 0.82), vec2(0.56, 0.82),  0.00, 0.028, 0.030));
    } else if (id == 3) {
        // M
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.16), vec2(0.24, 0.56),  0.02, 0.028, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.16), vec2(0.78, 0.56), -0.02, 0.028, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.44), vec2(0.50, 0.82),  0.00, 0.026, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.26, 0.82), vec2(0.74, 0.82), -0.01, 0.030, 0.032));
        d = min(d, sdBrushStroke(p, vec2(0.76, 0.18), vec2(0.84, 0.24),  0.00, 0.024, 0.028));
    } else if (id == 4) {
        // E
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.16), vec2(0.50, 0.56),  0.00, 0.028, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.78, 0.16), vec2(0.78, 0.56),  0.00, 0.028, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.22, 0.38), vec2(0.78, 0.36), -0.01, 0.030, 0.030));
        d = min(d, sdBrushStroke(p, vec2(0.22, 0.38), vec2(0.22, 0.60),  0.00, 0.028, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.18, 0.82), vec2(0.62, 0.82), -0.01, 0.032, 0.030));
    } else if (id == 5) {
        // G
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.16), vec2(0.50, 0.56),  0.00, 0.032, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.16, 0.36), vec2(0.78, 0.35), -0.01, 0.032, 0.032));
        d = min(d, sdBrushStroke(p, vec2(0.26, 0.82), vec2(0.84, 0.81), -0.01, 0.032, 0.034));
    } else if (id == 6) {
        // V
        d = min(d, sdBrushStroke(p, vec2(0.18, 0.16), vec2(0.38, 0.42),  0.01, 0.030, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.26, 0.50), vec2(0.78, 0.50), -0.01, 0.030, 0.030));
        d = min(d, sdBrushStroke(p, vec2(0.32, 0.50), vec2(0.20, 0.84),  0.02, 0.028, 0.022));
        d = min(d, sdBrushStroke(p, vec2(0.52, 0.50), vec2(0.52, 0.84),  0.00, 0.028, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.74, 0.50), vec2(0.82, 0.84), -0.02, 0.028, 0.024));
    } else if (id == 7) {
        // O
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.16), vec2(0.50, 0.56),  0.00, 0.028, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.24), vec2(0.22, 0.64),  0.04, 0.028, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.24), vec2(0.78, 0.58), -0.04, 0.028, 0.024));
        d = min(d, sdBrushStroke(p, vec2(0.26, 0.82), vec2(0.74, 0.82), -0.01, 0.032, 0.032));
    } else if (id == 8) {
        // I
        d = min(d, sdBrushStroke(p, vec2(0.20, 0.18), vec2(0.50, 0.52),  0.02, 0.034, 0.028));
        d = min(d, sdBrushStroke(p, vec2(0.50, 0.72), vec2(0.50, 0.84),  0.00, 0.030, 0.034));
    } else {
        // D
        d = min(d, sdBrushStroke(p, vec2(0.46, 0.16), vec2(0.54, 0.24),  0.00, 0.026, 0.032));
        d = min(d, sdBrushStroke(p, vec2(0.28, 0.50), vec2(0.78, 0.50), -0.01, 0.030, 0.030));
        d = min(d, sdBrushStroke(p, vec2(0.78, 0.34), vec2(0.68, 0.72),  0.02, 0.028, 0.026));
        d = min(d, sdBrushStroke(p, vec2(0.20, 0.82), vec2(0.64, 0.82), -0.01, 0.032, 0.030));
    }

    float edgeDist    = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float auraMask    = smoothstep(0.04, 0.18, edgeDist);
    float crispStroke = 1.0 - smoothstep(-0.008, 0.012, d);
    float softAura    = exp(-max(d, 0.0) * 21.0) * 0.26 * auraMask;
    return clamp(crispStroke + softAura, 0.0, 1.0);
}

// 100% Square, Undistorted Stars for the End Portal Block (removed shear wave that caused diamond distortion!)
vec3 portalStars(vec2 plane, float worldFootprint) {
    const float spacing = 0.82;
    plane += frameTimeCounter * vec2(0.014, -0.006);
    vec2 cell = floor(plane / spacing);
    float seed = portalHash(cell);
    float variation = portalHash(cell + vec2(31.0, 73.0));
    vec2 location = vec2(0.16) + vec2(seed, variation) * 0.68;
    vec2 d = abs(fract(plane / spacing) - location) * spacing;
    float radius = max(mix(0.012, 0.042, variation * variation), worldFootprint * 0.70);
    float edge = max(worldFootprint * 0.65, 0.002);
    float core = 1.0 - smoothstep(radius - edge, radius + edge, max(d.x, d.y));
    float halo = exp(-dot(d, d) / (radius * radius * 6.0)) * 0.14;
    vec2 border = min(fract(plane / spacing), 1.0 - fract(plane / spacing)) * spacing;
    halo *= smoothstep(0.0, 0.08, min(border.x, border.y));
    float pulse = 0.5 + 0.5 * sin(frameTimeCounter * mix(0.8, 1.5, variation) + seed * 6.2831853);
    float twinkle = 0.25 + 0.75 * pulse * pulse;
    float distanceFade = 1.0 - smoothstep(0.10, 0.30, worldFootprint);
    vec3 tint = mix(vec3(0.80, 0.96, 0.87), vec3(1.0, 0.92, 0.65), step(0.60, seed));
    float visible = step(0.18, portalHash(cell + vec2(91.0, 17.0)));
    return tint * (core * 1.35 + halo) * twinkle * distanceFade * visible;
}

// 100% Square, Clipping-Free 3D Tangent-Plane Sky Stars with Natural Angle Variations:
// - Evaluates cells on the 6 Cube-Map faces (ray / max(|x|,|y|,|z|)) rather than slicing a 3D Cartesian grid
//   with a sphere, completely eliminating paper-thin sliver cells that previously clipped stars into triangles!
// - Projects each star onto its local orthonormal 3D tangent plane (starRight, starUp) and rotates ~65% of stars
//   by a deterministic per-cell angle while keeping ~35% upright for natural variation!
vec3 renderEndTangentSquareStars(vec3 ray) {
    const float FACE_GRID = 12.0;
    vec3 absR = abs(ray);
    float maxAxis = max(absR.x, max(absR.y, absR.z));
    vec3 cubeP = ray / max(maxAxis, 1e-4);

    vec2 faceUV;
    float faceId;
    if (absR.y >= absR.x && absR.y >= absR.z) {
        faceUV = cubeP.xz;
        faceId = (ray.y >= 0.0) ? 0.0 : 1.0;
    } else if (absR.x >= absR.z) {
        faceUV = cubeP.yz;
        faceId = (ray.x >= 0.0) ? 2.0 : 3.0;
    } else {
        faceUV = cubeP.xy;
        faceId = (ray.z >= 0.0) ? 4.0 : 5.0;
    }

    vec2 scaledUV = (faceUV * 0.5 + 0.5) * FACE_GRID;
    vec2 cellId   = floor(scaledUV);
    float h0 = portalHash(cellId + vec2(faceId * 37.0, 19.0));
    if (h0 < 0.46) return vec3(0.0);

    float h1 = portalHash(cellId + vec2(73.0, faceId * 53.0));
    float h2 = portalHash(cellId + vec2(41.0 + faceId * 17.0, 29.0));

    // Keep star center well inside [0.26, 0.74] of the 2D cube-face cell so rotated corners never clip!
    vec2 starCellUV = (cellId + vec2(0.26) + vec2(h0, h1) * 0.48) / FACE_GRID * 2.0 - 1.0;
    vec3 starCubeP;
    if (faceId < 1.5) {
        starCubeP = vec3(starCellUV.x, (faceId < 0.5) ? 1.0 : -1.0, starCellUV.y);
    } else if (faceId < 3.5) {
        starCubeP = vec3((faceId < 2.5) ? 1.0 : -1.0, starCellUV.x, starCellUV.y);
    } else {
        starCubeP = vec3(starCellUV.x, starCellUV.y, (faceId < 4.5) ? 1.0 : -1.0);
    }
    vec3 starDir = normalize(starCubeP);

    // Orthonormal tangent basis perpendicular to starDir (guarantees 1:1 square shape at any viewing angle)
    vec3 upRef = (abs(starDir.y) < 0.92) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 starRight = normalize(cross(upRef, starDir));
    vec3 starUp    = cross(starDir, starRight);

    vec2 localXY = vec2(dot(ray - starDir, starRight), dot(ray - starDir, starUp));

    // ~35% of stars stay upright (0 deg); ~65% get a deterministic tilt angle (12..78 deg) for organic variety
    if (h2 >= 0.35) {
        float rotAngle = (0.21 + 1.15 * fract(h0 * 3.73 + h1 * 5.17));
        float ca = cos(rotAngle);
        float sa = sin(rotAngle);
        localXY = vec2(ca * localXY.x - sa * localXY.y, sa * localXY.x + ca * localXY.y);
    }

    float starRadius = mix(0.0020, 0.0040, h1 * h1);
    float dSquare = max(abs(localXY.x), abs(localXY.y));
    float core = 1.0 - smoothstep(starRadius * 0.65, starRadius * 1.15, dSquare);
    float halo = exp(-dot(localXY, localXY) / (starRadius * starRadius * 5.0)) * 0.14;
    if (core + halo <= 0.001) return vec3(0.0);

    float pulse = 0.55 + 0.45 * sin(frameTimeCounter * mix(0.7, 1.4, h2) + h0 * 6.2831853);
    vec3 tint = (STYLE_SELECTION == 0)
        ? mix(vec3(0.76, 0.88, 0.74), vec3(0.96, 0.90, 0.68), step(0.55, h1))
        : mix(vec3(0.72, 0.96, 0.90), vec3(0.96, 0.92, 0.72), step(0.58, h1));
    return tint * (core * 1.15 + halo) * pulse;
}

// Fine Tangent-Plane Angled Micro-Stardust (embedded inside the Zenith Crown, Celestial River & Nadir Abyss):
// Uses a 26x26 cube-face grid of tiny rotated-square dust glints so the nebula clouds and poles feel rich and alive
// without ever distorting or blocky-quantizing the smooth 3D nebula!
vec3 renderEndNebulaMicroStardust(vec3 ray, float nebulaDensity) {
    if (nebulaDensity <= 0.02) return vec3(0.0);
    const float DUST_GRID = 26.0;
    vec3 absR = abs(ray);
    float maxAxis = max(absR.x, max(absR.y, absR.z));
    vec3 cubeP = ray / max(maxAxis, 1e-4);

    vec2 faceUV;
    float faceId;
    if (absR.y >= absR.x && absR.y >= absR.z) {
        faceUV = cubeP.xz;
        faceId = (ray.y >= 0.0) ? 0.0 : 1.0;
    } else if (absR.x >= absR.z) {
        faceUV = cubeP.yz;
        faceId = (ray.x >= 0.0) ? 2.0 : 3.0;
    } else {
        faceUV = cubeP.xy;
        faceId = (ray.z >= 0.0) ? 4.0 : 5.0;
    }

    vec2 scaledUV = (faceUV * 0.5 + 0.5) * DUST_GRID;
    vec2 cellId   = floor(scaledUV);
    float h0 = portalHash(cellId + vec2(faceId * 43.0, 61.0));
    float threshold = (SKY_STYLE == 1) ? 0.48 : 0.58;
    if (h0 < threshold) return vec3(0.0);

    float h1 = portalHash(cellId + vec2(97.0, faceId * 29.0));
    float h2 = portalHash(cellId + vec2(19.0 + faceId * 31.0, 83.0));

    vec2 starCellUV = (cellId + vec2(0.28) + vec2(h0, h1) * 0.44) / DUST_GRID * 2.0 - 1.0;
    vec3 starCubeP;
    if (faceId < 1.5) {
        starCubeP = vec3(starCellUV.x, (faceId < 0.5) ? 1.0 : -1.0, starCellUV.y);
    } else if (faceId < 3.5) {
        starCubeP = vec3((faceId < 2.5) ? 1.0 : -1.0, starCellUV.x, starCellUV.y);
    } else {
        starCubeP = vec3(starCellUV.x, starCellUV.y, (faceId < 4.5) ? 1.0 : -1.0);
    }
    vec3 starDir = normalize(starCubeP);

    vec3 upRef = (abs(starDir.y) < 0.92) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 starRight = normalize(cross(upRef, starDir));
    vec3 starUp    = cross(starDir, starRight);

    vec2 localXY = vec2(dot(ray - starDir, starRight), dot(ray - starDir, starUp));
    if (h2 >= 0.30) {
        float rotAngle = 0.25 + 1.10 * fract(h0 * 4.13 + h1 * 6.71);
        float ca = cos(rotAngle);
        float sa = sin(rotAngle);
        localXY = vec2(ca * localXY.x - sa * localXY.y, sa * localXY.x + ca * localXY.y);
    }

    float dustRadius = mix(0.0010, 0.0022, h1);
    float dSquare = max(abs(localXY.x), abs(localXY.y));
    float core = 1.0 - smoothstep(dustRadius * 0.60, dustRadius * 1.15, dSquare);
    if (core <= 0.001) return vec3(0.0);

    float twinkle = 0.45 + 0.55 * sin(frameTimeCounter * mix(0.9, 1.8, h2) + h0 * 6.2831853);
    vec3 dustTint = (STYLE_SELECTION == 0)
        ? mix(vec3(0.68, 0.84, 0.68), vec3(0.95, 0.88, 0.64), step(0.50, h1))
        : mix(vec3(0.56, 0.94, 0.88), vec3(0.88, 0.96, 0.78), step(0.55, h1));
    float styleBoost = (SKY_STYLE == 1) ? 0.95 : 0.68;
    return dustTint * (core * twinkle * clamp(nebulaDensity * 1.35, 0.0, 1.0) * styleBoost);
}

// Evaluates Periodic 360-Degree Undulating Celestial River Elevation (100% branch-cut-free using sin/cos of ray.xz):
// Keeps the main 3D volumetric nebula river & vertical sutra columns at y = 0.16..0.44 above the horizon
// across all 360 degrees so every look direction is balanced, atmospheric, and cohesive!
float evaluateEndCelestialRiverY(vec2 horizDir) {
    float s1 = horizDir.x;
    float c1 = -horizDir.y;
    float s2 = 2.0 * s1 * c1;
    float c2 = c1 * c1 - s1 * s1;
    return 0.28 + 0.08 * (s1 * 0.82 + c1 * 0.57) + 0.04 * (c2 * 0.76 - s2 * 0.65);
}

// Evaluates a single Vertical Inscription Column (竖排天书 / Vertical SGA Rune Stream) along a meridian:
// - Uses the exact meridian plane normal `colRight = vec3(cos(colAzim), 0.0, sin(colAzim))` so every stacked
//   character in the vertical column is 100% upright, 1:1 square, and aligned vertically with zero tilt!
// - Applies a smooth vertical stream window and head-to-tail luminance fade over 5 to 6 stacked glyphs.
void accumulateSingleVerticalGlyphColumn(
    vec3 ray,
    float colAzim,
    float colCenterElev,
    float colHalfSpanElev,
    float glyphSize,
    float glyphPitch,
    float driftSpeed,
    float colSeed,
    float layerOpacityScale,
    inout vec4 accumGlyph
) {
    vec2 colHoriz = vec2(sin(colAzim), -cos(colAzim));
    // Fast hemisphere & meridian culling
    float horizForward = dot(ray.xz, colHoriz);
    if (horizForward <= 0.75) return;

    vec3 colRight = vec3(-colHoriz.y, 0.0, colHoriz.x);
    float localX  = dot(ray, colRight);
    if (abs(localX) >= glyphSize * 0.49) return;

    float elevAng = asin(clamp(ray.y, -0.99, 0.99));
    float relElev = elevAng - colCenterElev;
    if (abs(relElev) >= colHalfSpanElev) return;

    // Normalized position along the vertical column: 0.0 at bottom, 1.0 at top
    float colU01 = clamp((relElev + colHalfSpanElev) / (2.0 * colHalfSpanElev), 0.0, 1.0);
    // Smooth top & bottom column fade-in/out window (zero harsh cutoffs at column ends!)
    float colWindow = smoothstep(0.0, 0.18, colU01) * (1.0 - smoothstep(0.82, 1.0, colU01));
    if (colWindow <= 0.002) return;

    // Vertical scrolling coordinate:
    // - In Wuxia Smooth (SKY_STYLE == 0): slow upward spiritual drift; in Voxel (SKY_STYLE == 1): slow downward rune cascade
    float scrollDir = (SKY_STYLE == 1) ? 1.0 : -1.0;
    float vCoord    = (relElev + colHalfSpanElev) / glyphPitch + scrollDir * frameTimeCounter * driftSpeed + colSeed * 3.7;
    float rowIdx    = floor(vCoord);
    float cellFractY = fract(vCoord);

    // Leave a clean 18% vertical breathing gap between stacked characters in the column
    if (cellFractY < 0.09 || cellFractY > 0.91) return;
    float glyphUV_Y = (cellFractY - 0.09) / 0.82;
    float glyphUV_X = (localX / glyphSize) + 0.5;
    vec2 gUV = vec2(glyphUV_X, glyphUV_Y);

    // Deterministic character/rune selection per row in the vertical verse
    int charId = int(mod(abs(rowIdx + floor(colSeed * 11.0)), 8.0));
    int sgaId  = int(mod(abs(rowIdx * 3.0 + floor(colSeed * 17.0)), 10.0));

    float glyphMask = (ACTIVE_END_GLYPH_STYLE == 1)
        ? sampleEndVectorCjkGlyph(charId, gUV)
        : sampleEndSgaGlyph(sgaId, gUV);
    if (glyphMask <= 0.002) return;

    // Head-to-tail luminance & alpha trail envelope along the vertical column:
    // Creates a luminous leading character ("head") and a smooth 5-character fading tail
    float streamCycle = fract(colU01 * 0.85 + scrollDir * frameTimeCounter * 0.028 + colSeed * 0.618);
    float headGlow    = exp(-streamCycle * 5.2);
    float tailBody    = smoothstep(0.02, 0.22, 1.0 - streamCycle) * (0.38 + 0.62 * exp(-streamCycle * 1.65));
    float rowPulse    = 0.82 + 0.18 * sin(frameTimeCounter * 0.9 + rowIdx * 1.35 + colSeed * 4.1);

    vec3 leadCol, trailCol;
    if (STYLE_SELECTION == 0) {
        // Guofeng Ink: Warm Xuan-gold parchment lead -> Shilu celadon-ochre trail
        leadCol  = vec3(0.95, 0.90, 0.72);
        trailCol = vec3(0.56, 0.72, 0.56);
    } else {
        // Xianxia Mist: Luminous pale mint-jade lead -> Spirit cyan-jade trail
        leadCol  = vec3(0.84, 0.98, 0.93);
        trailCol = vec3(0.28, 0.82, 0.76);
    }

    vec3 glyphColor = mix(trailCol, leadCol, clamp(headGlow * 1.15 + glyphMask * 0.35, 0.0, 1.0));
    float alpha = glyphMask * colWindow * tailBody * rowPulse * layerOpacityScale;
    if (alpha > 0.002) {
        accumGlyph.rgb = mix(accumGlyph.rgb, glyphColor, alpha / max(accumGlyph.a + alpha, 1e-4));
        accumGlyph.a   = clamp(accumGlyph.a + alpha * (1.0 - accumGlyph.a), 0.0, 0.68);
    }
}

// Evaluates a Parallax Depth Tier of Vertical Inscription Columns ("Celestial Sutra Streams"):
// - Tier 0 (isForeground == false): 10 Deep Background column clusters (smaller scale, softer opacity, veiled behind nebula folds)
// - Tier 1 (isForeground == true):  7 Foreground Canopy column clusters (paired hanging-scroll couplets, crisp scale)
vec4 evaluateEndVerticalGlyphLayer(vec3 ray, bool isForeground, float visibility) {
    if (ACTIVE_END_GLYPH_STYLE == 3 || visibility <= 0.01 || abs(ray.y) <= 0.02 || abs(ray.y) >= 0.86) return vec4(0.0);

    vec4 accum = vec4(0.0);
    int numClusters   = isForeground ? 7 : 10;
    float fClusters   = float(numClusters);
    float glyphSize   = isForeground ? 0.033 : 0.021;
    float glyphPitch  = isForeground ? 0.041 : 0.027;
    float halfSpan    = glyphPitch * (isForeground ? 2.75 : 3.15); // 5 to 6 stacked characters per vertical column!
    float baseOpacity = (isForeground ? 0.46 : 0.24) * visibility;
    float driftRate   = isForeground ? 0.11 : 0.075;
    float tierOffset  = isForeground ? 0.44 : 0.12;

    for (int i = 0; i < 10; i++) {
        if (i >= numClusters) break;
        float fi = float(i);
        float h0 = portalHash(vec2(fi * 3.7 + 1.1, isForeground ? 19.3 : 7.1));
        float h1 = portalHash(vec2(fi * 5.9 + 4.3, isForeground ? 31.7 : 13.9));

        float clusterAzim = (fi + 0.20 + 0.60 * h0) * (6.2831853 / fClusters) + tierOffset;
        vec2 cHoriz       = vec2(sin(clusterAzim), -cos(clusterAzim));
        if (dot(ray.xz, cHoriz) > 0.72) {
            float riverY = evaluateEndCelestialRiverY(cHoriz);
            float mainCenterElev = clamp(riverY + (h1 - 0.45) * 0.14 + (isForeground ? 0.02 : 0.06), 0.18, 0.54);

            // Primary vertical column in this cluster
            accumulateSingleVerticalGlyphColumn(
                ray, clusterAzim, mainCenterElev, halfSpan,
                glyphSize, glyphPitch, driftRate * (0.85 + 0.30 * h0),
                fi + (isForeground ? 10.0 : 0.0), baseOpacity, accum
            );

            // Companion vertical column (forming a traditional 2-column hanging scroll couplet on ~65% of clusters!)
            if (h0 > 0.35) {
                float sideSign = (h1 > 0.5) ? 1.0 : -1.0;
                float compAzim = clusterAzim + sideSign * (glyphSize * 1.45);
                float compElev = mainCenterElev - 0.035; // Slightly staggered lower like a traditional scroll couplet
                float compSpan = halfSpan * 0.82;
                accumulateSingleVerticalGlyphColumn(
                    ray, compAzim, compElev, compSpan,
                    glyphSize * 0.90, glyphPitch * 0.90, driftRate * (0.95 + 0.20 * h1),
                    fi + (isForeground ? 27.0 : 17.0), baseOpacity * 0.82, accum
                );
            }
        }
    }
    return accum;
}

// Base End Void Dome Gradient (harmonious dark cosmic void that blends smoothly with the 3D nebula)
vec3 evaluateYunMengEndBaseSky(vec3 worldRayDir) {
    float elev = clamp(worldRayDir.y, -1.0, 1.0);
    float upCurve = pow(clamp(elev, 0.0, 1.0), 0.78);
    float horizGlow = exp(-pow((elev - 0.04) / 0.28, 2.0));
    float abyssFade = clamp((-elev - 0.04) / 0.55, 0.0, 1.0);

    vec3 cZenith, cMid, cHorizon, cAbyss;
    if (STYLE_SELECTION == 0) {
        // Guofeng Ink (归墟水墨): Velvety Songyan pine-ink & muted mineral celadon
        cZenith  = vec3(0.008, 0.015, 0.012);
        cMid     = vec3(0.018, 0.032, 0.026);
        cHorizon = vec3(0.032, 0.056, 0.045);
        cAbyss   = vec3(0.005, 0.010, 0.008);
    } else {
        // Xianxia Mist (太虚碧落): Velvety astral teal-indigo & deep spirit-jade
        cZenith  = vec3(0.006, 0.016, 0.024);
        cMid     = vec3(0.014, 0.038, 0.044);
        cHorizon = vec3(0.026, 0.068, 0.068);
        cAbyss   = vec3(0.004, 0.011, 0.016);
    }

    vec3 sky = mix(cMid, cZenith, upCurve);
    sky = mix(sky, cHorizon, horizGlow * 0.65);
    sky = mix(sky, cAbyss, abyssFade * 0.75);
    return sky;
}

#ifdef YUNMENG_CLOUD_FIELD
// "Celestial Sutra Streams" (太虚天书) — Pure 3D Volumetric Nebula & Two-Depth Vertical Glyph Column Skybox:
// - Keeps the 2D portal block texture strictly inside the End Portal block (zero 2D sprites pasted on the sky!).
// - Renders a rich, multi-octave 3D volumetric nebula along the 360-degree Celestial River & Upper Canopy.
// - Embeds two parallax depth tiers of vertical stacked glyph columns (Tier 0 veiled behind nebula folds,
//   Tier 1 floating in front of the mid-nebula) with head-to-tail luminance trails and zero tilt distortion!
// Multi-directional travelling Sound-Wave Ocean swell across the even 2D pillar grid (cell.x, cell.y)
float evaluateEndSoundWaveOceanSwell(vec2 cell, float t) {
    float w1 = sin(cell.x * 0.32 + cell.y * 0.21 - t * 1.05);
    float w2 = cos(cell.x * 0.19 - cell.y * 0.35 + t * 0.82);
    float w3 = sin((cell.x + cell.y) * 0.15 + sin(cell.x * 0.11 - cell.y * 0.13) * 2.0);
    return (w1 * 0.42 + w2 * 0.35 + w3 * 0.23) * 0.5 + 0.5;
}

// Contiguous, Hole-Free 2D-DDA 3D Sound-Wave Ocean with Volumetric Trough Mist & Crest Cap Inscriptions:
// 1. Zero Holes: Every cell (100%) has a continuous 3D rectangular column extending from its undulating cap height
//    yCap(cell) all the way to SLAB_TOP (32.0), so no ray can ever pass behind a block or hit a missing cell!
// 2. Zero Black Grid Trenches: Columns are contiguous edge-to-edge (exact 2D-DDA heightfield column traversal),
//    with a soft inner bevel and Volumetric Trough & Depth Mist pooling inside the wave valleys and along step walls.
// 3. Integrated Cap Inscriptions: High wave crests (swell > 0.68) display a subtle glowing Classical Chinese or SGA
//    inscription directly on the flat 3D cap face of the block!
vec4 renderEndSoundWaveOcean3D(vec3 ray, vec3 nebulaMistColor, float nebulaDensity) {
    float absRy = abs(ray.y);
    if (absRy <= 0.06) return vec4(0.0);

    const float SLAB_BASE = 11.5;
    const float SLAB_TOP  = 32.0;
    const float CELL_SIZE = 2.35;
    const int   DDA_STEPS = 32;

    float tEnterSlab = SLAB_BASE / absRy;
    float tExitSlab  = min(SLAB_TOP / absRy, tEnterSlab + 68.0);
    if (tExitSlab <= tEnterSlab) return vec4(0.0);

    vec2 safeRxz = mix(vec2(-1.0), vec2(1.0), step(vec2(0.0), ray.xz)) * max(abs(ray.xz), vec2(1e-5));
    vec2 invRxz  = 1.0 / safeRxz;

    vec2 startXZ = ray.xz * tEnterSlab;
    vec2 cell    = floor(startXZ / CELL_SIZE);
    vec2 stepDir = sign(safeRxz);
    vec2 nextB   = (cell + step(vec2(0.0), safeRxz)) * CELL_SIZE;
    vec2 tMax    = tEnterSlab + (nextB - startXZ) * invRxz;
    vec2 tDelta  = CELL_SIZE * abs(invRxz);

    vec3 cCap, cFront, cSide, cRim, cTroughMist;
    if (STYLE_SELECTION == 0) {
        // Guofeng Ink: Shilu mineral celadon caps, pine-ink shaded walls, warm Xuan-ochre rims & celadon trough mist
        cCap        = vec3(0.195, 0.255, 0.185);
        cFront      = vec3(0.105, 0.155, 0.118);
        cSide       = vec3(0.048, 0.082, 0.064);
        cRim        = vec3(0.460, 0.430, 0.280);
        cTroughMist = vec3(0.065, 0.115, 0.090);
    } else {
        // Xianxia Mist: Spirit-jade caps, Prussian-teal walls, luminous cyan-mint rims & deep jade trough mist
        cCap        = vec3(0.145, 0.355, 0.335);
        cFront      = vec3(0.075, 0.225, 0.222);
        cSide       = vec3(0.034, 0.112, 0.122);
        cRim        = vec3(0.280, 0.650, 0.620);
        cTroughMist = vec3(0.052, 0.158, 0.165);
    }

    float waveTime = frameTimeCounter * 0.40 * WIND_SPEED;
    float tCurr = tEnterSlab;
    int lastAxis = -1;

    for (int i = 0; i < DDA_STEPS; ++i) {
        if (tCurr >= tExitSlab) break;
        float tNext = min(min(tMax.x, tMax.y), tExitSlab);

        float swell = evaluateEndSoundWaveOceanSwell(cell, waveTime);
        float hVar  = portalHash(cell);

        // Continuous undulating cap height yCap in [12.5, 19.2]; column extends solidly from yCap to SLAB_TOP (32.0)!
        float yCap = 12.5 + (1.0 - swell) * 5.8 + (hVar - 0.5) * 0.65;
        float yAtEnter = absRy * tCurr;
        float yAtExit  = absRy * tNext;

        if (yAtExit >= yCap) {
            // Ray intersects this contiguous 3D column!
            // If yAtEnter < yCap, we hit the horizontal Cap Face at tHit = yCap / absRy;
            // Otherwise (yAtEnter >= yCap), we entered directly into the vertical 3D Side Wall at tHit = tCurr!
            bool isCapFace = (i == 0) ? (yAtEnter <= yCap + 1e-4) : ((yAtEnter < yCap) && ((yCap / absRy) > tCurr));
            float tHit = isCapFace ? clamp(yCap / absRy, tCurr, tNext) : tCurr;
            bool isXSide = (!isCapFace) && (lastAxis == 0);

            vec2 centerXZ = (cell + 0.5) * CELL_SIZE;
            vec2 localUV  = (ray.xz * tHit - centerXZ) / CELL_SIZE + 0.5; // in [0, 1]
            float hitY    = max(absRy * tHit - yCap, 0.0);

            float crestGlow = 0.32 + 0.72 * pow(swell, 1.30);
            float wallGrad  = exp(-hitY * 0.38);

            // Soft 3D inner cushion bevel on each cap & wall so adjacent columns are clearly defined without black gaps!
            vec2 edgeDist2 = abs(localUV - 0.5) * 2.0; // 0 at center, 1 at cell border
            float edgeMax  = max(edgeDist2.x, edgeDist2.y);
            float seamShadow = 1.0 - smoothstep(0.86, 1.00, edgeMax) * 0.32;
            float innerRim   = smoothstep(0.76, 0.90, edgeMax) * (1.0 - smoothstep(0.90, 0.99, edgeMax));

            vec3 faceCol = isCapFace
                ? (cCap * crestGlow * seamShadow)
                : ((isXSide ? cSide : cFront) * (crestGlow * wallGrad * seamShadow));

            faceCol += cRim * (innerRim * crestGlow * (isCapFace ? 0.28 : 0.14));

            // Subtle Glowing Cap-Face Inscription on high wave crests (unifies the text/runes with the 3D wave blocks!)
            if (isCapFace && ACTIVE_END_GLYPH_STYLE != 3 && swell > 0.64 && hVar > 0.42) {
                vec2 gUV = clamp((localUV - 0.14) / 0.72, 0.0, 1.0);
                int charId = int(mod(abs(cell.x * 3.0 + cell.y * 7.0), 8.0));
                int sgaId  = int(mod(abs(cell.x * 5.0 + cell.y * 11.0), 10.0));
                float capGlyph = (ACTIVE_END_GLYPH_STYLE == 1)
                    ? sampleEndVectorCjkGlyph(charId, gUV)
                    : sampleEndSgaGlyph(sgaId, gUV);
                float crestPulse = (0.55 + 0.45 * sin(frameTimeCounter * 1.1 + hVar * 6.283)) * smoothstep(0.64, 0.85, swell);
                faceCol += cRim * (capGlyph * crestPulse * 0.55);
            }

            // Volumetric Trough & Depth Mist:
            // Wave valleys (low swell), recessed vertical walls (hitY), and distant columns are softly veiled
            // in glowing nebula-harmonized mist so the wave ocean blends seamlessly with the End nebula!
            float troughFog = (1.0 - swell) * 0.52 + (1.0 - wallGrad) * 0.35;
            float distFog   = 1.0 - exp(-max(tHit - 13.0, 0.0) * 0.036);
            vec3 mistTarget = mix(cTroughMist, nebulaMistColor, clamp(nebulaDensity * 0.85, 0.0, 0.75));
            faceCol = mix(faceCol, mistTarget, clamp(troughFog + distFog * 0.55, 0.0, 0.88));

            // Smooth horizon & distance dissolve so the 3D wave melts into the Horizon Nebula & Rune Sanctum
            float visFade = exp(-max(tHit - 14.0, 0.0) * 0.038) * smoothstep(0.06, 0.28, absRy);
            return vec4(faceCol, clamp(visFade * 0.94, 0.0, 1.0));
        }

        if (tMax.x < tMax.y) {
            tCurr    = tMax.x;
            tMax.x  += tDelta.x;
            cell.x  += stepDir.x;
            lastAxis = 0;
        } else {
            tCurr    = tMax.y;
            tMax.y  += tDelta.y;
            cell.y  += stepDir.y;
            lastAxis = 1;
        }
    }

    return vec4(0.0);
}

// Sculpted 3D Imperial Silk-Scroll Wave Heightfield (SKY_STYLE == 0):
// Restores the crisp, sculptural 3D imperial scrolls with graceful open troughs between ribbons,
// fluid silk undulation, refined single-line gold embroidery trim, and zero background circle clutter.
float evaluateImperialScrollWaveHeight(vec2 posXZ, float waveTime, out float swellOut, out float phaseOut, out float alongOut) {
    float flowU = posXZ.x * 0.076 + posXZ.y * 0.102;
    float flowV = -posXZ.x * 0.102 + posXZ.y * 0.076;
    // Graceful, flowing serpentine silk curve (lighter and more fluid than stiff straight slats)
    float warp  = 0.62 * sin(flowV * 0.29 + waveTime * 0.17) + 0.22 * cos(flowV * 0.58 - waveTime * 0.23);
    float phase = flowU + warp - waveTime * 0.10;

    // Cross-scroll coordinate dCenter in [0.0, 0.5]: 0.0 = scroll spine, 0.5 = deep misty valley
    float dCenter = abs(fract(phase + 0.5) - 0.5);
    // Clean, balanced flat-topped scroll face (dCenter < 0.21) with generous open valleys between scrolls
    float plateau = 1.0 - smoothstep(0.19, 0.36, dCenter);
    float crown   = (1.0 - smoothstep(0.0, 0.24, dCenter)) * 0.10;
    float billow  = 0.5 + 0.5 * sin(flowV * 0.46 - waveTime * 0.32 + floor(phase + 0.5) * 1.9);

    swellOut = clamp((plateau * 0.88 + crown) * (0.74 + 0.26 * billow), 0.0, 1.0);
    phaseOut = phase;
    alongOut = flowV;
    return 11.8 + (1.0 - swellOut) * 6.8;
}

// Unified Wuxia Smooth End Skybox (SKY_STYLE == 0):
// Crisp, flowing 3D silk scrolls with refined pale-gold silk trim, centered glowing brush calligraphy
// (Classical Chinese or Brush-Stroke SGA), and deep, open misty valleys (zero background circles).
vec4 renderEndSmoothTaixuSky(vec3 ray, vec3 nebulaMistColor, float nebulaDensity) {
    float absRy = abs(ray.y);
    if (absRy <= 0.06) return vec4(0.0);

    const float SLAB_BASE = 11.4;
    const float SLAB_TOP  = 20.6;
    const int   STEPS     = 34;

    float tEnter = SLAB_BASE / absRy;
    float tExit  = min(SLAB_TOP / absRy, tEnter + 68.0);
    if (tExit <= tEnter) return vec4(0.0);

    vec3 cScrollFace, cScrollLit, cSideShadow, cTroughMist, cGoldCore, cGoldHalo, cJadeTrim;
    if (STYLE_SELECTION == 0) {
        // Guofeng Ink: Ink-jade silk scroll faces, celadon lit slopes, pine-ink troughs, antique pale gold trim & glyphs
        cScrollFace = vec3(0.048, 0.090, 0.072);
        cScrollLit  = vec3(0.108, 0.172, 0.134);
        cSideShadow = vec3(0.015, 0.032, 0.026);
        cTroughMist = vec3(0.026, 0.050, 0.040);
        cJadeTrim   = vec3(0.175, 0.295, 0.235);
        cGoldCore   = vec3(0.920, 0.805, 0.490);
        cGoldHalo   = vec3(0.560, 0.450, 0.220);
    } else {
        // Xianxia Mist: Deep abyssal teal scroll faces, spirit-jade lit slopes, deep teal troughs, pale champagne gold
        cScrollFace = vec3(0.028, 0.102, 0.110);
        cScrollLit  = vec3(0.074, 0.214, 0.214);
        cSideShadow = vec3(0.010, 0.038, 0.046);
        cTroughMist = vec3(0.020, 0.068, 0.078);
        cJadeTrim   = vec3(0.150, 0.420, 0.410);
        cGoldCore   = vec3(0.955, 0.870, 0.565);
        cGoldHalo   = vec3(0.580, 0.475, 0.235);
    }

    float waveTime = frameTimeCounter * 0.35 * max(WIND_SPEED, 0.15);
    vec2 hemiRayXZ = (ray.y >= 0.0) ? ray.xz : vec2(-ray.z, ray.x);
    vec2 hemiShift = (ray.y >= 0.0) ? vec2(0.0) : vec2(21.3, -15.8);

    float tPrev = tEnter;
    bool hit = false;
    float tHit = tExit;
    float swellHit = 0.5;
    float phaseHit = 0.0;
    float alongHit = 0.0;

    for (int i = 1; i <= STEPS; ++i) {
        float f = float(i) / float(STEPS);
        float t = mix(tEnter, tExit, f);
        float sw, ph, al;
        float yWave = evaluateImperialScrollWaveHeight(hemiRayXZ * t + hemiShift, waveTime, sw, ph, al);
        if (absRy * t >= yWave) {
            float tA = tPrev;
            float tB = t;
            for (int b = 0; b < 4; ++b) {
                float tM = 0.5 * (tA + tB);
                float swM, phM, alM;
                float yM = evaluateImperialScrollWaveHeight(hemiRayXZ * tM + hemiShift, waveTime, swM, phM, alM);
                if (absRy * tM >= yM) {
                    tB = tM;
                    sw = swM; ph = phM; al = alM;
                } else {
                    tA = tM;
                }
            }
            tHit = tB;
            swellHit = sw;
            phaseHit = ph;
            alongHit = al;
            hit = true;
            break;
        }
        tPrev = t;
    }

    if (!hit) return vec4(0.0);

    vec2 hitXZ = hemiRayXZ * tHit + hemiShift;
    const float EPS = 0.18;
    float swX, phX, alX, swZ, phZ, alZ;
    float hC = 11.8 + (1.0 - swellHit) * 6.8;
    float hX = evaluateImperialScrollWaveHeight(hitXZ + vec2(EPS, 0.0), waveTime, swX, phX, alX);
    float hZ = evaluateImperialScrollWaveHeight(hitXZ + vec2(0.0, EPS), waveTime, swZ, phZ, alZ);
    vec3 surfNormal = normalize(vec3((hX - hC) / EPS, 1.0, (hZ - hC) / EPS));

    float ribbonCoord = phaseHit + 0.5;
    float ribbonId    = floor(ribbonCoord);
    float inRibbonV   = fract(ribbonCoord);
    float dSpine      = abs(inRibbonV - 0.5); // 0.0 at exact scroll center, 0.5 at trough center

    // 1. Directional Velvet Silk Shading + Refined Single-Line Pale-Gold Silk Trim
    vec3 viewDirSurf = normalize(vec3(-hemiRayXZ.x, absRy, -hemiRayXZ.y));
    vec3 keyLightDir = normalize(vec3(0.56, 0.62, 0.55));
    float litFront   = smoothstep(-0.20, 0.84, dot(surfNormal, keyLightDir));
    float onFace     = 1.0 - smoothstep(0.19, 0.28, dSpine);
    float velvetRim  = pow(1.0 - clamp(dot(surfNormal, viewDirSurf), 0.0, 1.0), 2.1) * smoothstep(0.18, 0.78, swellHit);

    float silkGrain  = cloudVolume(vec3(hitXZ * 0.042, 0.25)).r;
    vec3 faceBase    = mix(cScrollFace, cScrollLit, litFront * 0.70 + silkGrain * 0.22);
    vec3 slopeBase   = mix(cSideShadow, cScrollFace * 0.82, litFront);
    vec3 surfCol     = mix(slopeBase, faceBase, onFace);

    // Delicate, finely antialiased single pale-gold embroidery trim (dSpine = 0.208) — light and crisp, never heavy rails
    float aaBorder   = max(fwidth(dSpine) * 1.4, 0.007);
    float goldTrim   = 1.0 - smoothstep(0.0025, 0.0025 + aaBorder, abs(dSpine - 0.208));
    float trimHalo   = exp(-abs(dSpine - 0.208) * 38.0) * 0.18;
    float borderVis  = smoothstep(0.28, 0.66, swellHit);
    surfCol += cGoldCore * (goldTrim * 0.44 * borderVis)
             + cGoldHalo * (trimHalo * borderVis)
             + cJadeTrim * (velvetRim * 0.22);

    // 2. Crisp, Fully-Centered Pale-Gold Brush Calligraphy Inside the Scroll Trim (Zero Edge Clipping!)
    float poleTextClearance = smoothstep(0.12, 0.32, absRy);
    if (ACTIVE_END_GLYPH_STYLE != 3 && poleTextClearance > 0.01 && dSpine < 0.192) {
        float charStep    = (alongHit - waveTime * 0.08) / 0.54;
        float charIdx     = floor(charStep);
        float cu          = fract(charStep);
        float scrollIdx   = floor(charIdx / 12.0);
        float posInScroll = mod(charIdx, 12.0);

        // 7-character poetic verse with 5 units of breathing space between verses
        if (posInScroll < 6.5 && cu > 0.02 && cu < 0.98) {
            float scrollU = (posInScroll + cu) / 7.0;
            float cycle   = fract(frameTimeCounter * 0.046 + ribbonId * 0.37 + scrollIdx * 0.618);
            float revealFront = smoothstep(0.08, 0.54, cycle) * 1.18 - 0.06;
            float cycleFade   = smoothstep(0.98, 0.78, cycle);
            float activeSpan  = smoothstep(0.04, 0.12, cycle) * cycleFade;

            // Generous centered band with smooth aura headroom so glow fades organically to zero with zero box edge
            float cv = (inRibbonV - 0.310) / 0.380;
            if (cv > 0.02 && cv < 0.98) {
                vec2 gUV = vec2(
                    (cu - 0.02) / 0.96,
                    ((ray.y >= 0.0 ? (1.0 - cv) : cv) - 0.02) / 0.96
                );

                int seqSlot = int(mod(abs(posInScroll), 8.0));
                int charId  = (seqSlot == 1) ? 6 : ((seqSlot == 3) ? 1 : seqSlot);
                int sgaId   = int(mod(abs(charIdx + ribbonId * 3.0), 10.0));
                float glyphMask = (ACTIVE_END_GLYPH_STYLE == 1)
                    ? sampleEndVectorCjkGlyph(charId, gUV)
                    : sampleEndBrushSgaGlyph(sgaId, gUV);

                float revealed     = smoothstep(revealFront + 0.04, revealFront - 0.08, scrollU);
                float strokeIgnite = 0.85 + 0.42 * exp(-pow((scrollU - revealFront + 0.02) / 0.09, 2.0));
                float verseW       = glyphMask * revealed * strokeIgnite * activeSpan * poleTextClearance * borderVis;

                surfCol += cGoldCore * (verseW * 0.80) + cGoldHalo * (verseW * 0.32);
            }
        }
    }

    // 3. Soft Volumetric Trough Mist & Open Starry Sky Between Scrolls
    float cloudWisp = cloudVolume(vec3(hitXZ * 0.022 + vec2(waveTime * 0.04, waveTime * 0.028), 0.55)).r;
    float troughFog = pow(1.0 - swellHit, 1.25) * (0.50 + 0.20 * cloudWisp);
    float distFog   = 1.0 - exp(-max(tHit - 14.0, 0.0) * 0.034);
    vec3 mistTarget = mix(cTroughMist, nebulaMistColor, clamp(nebulaDensity * 0.85, 0.0, 0.75));
    surfCol = mix(surfCol, mistTarget, clamp(troughFog + distFog * 0.54, 0.0, 0.88));

    // Scrolls stay solid & crisp on their faces while deep troughs open softly to let stars & mist breathe
    float openTroughAlpha = mix(0.32, 0.95, smoothstep(0.08, 0.45, swellHit));
    float visFade = exp(-max(tHit - 15.0, 0.0) * 0.034) * smoothstep(0.06, 0.28, absRy);
    return vec4(min(surfCol, vec3(1.04)), clamp(visFade * openTroughAlpha, 0.0, 0.96));
}

vec3 renderYunMengEndSkyDome(vec3 worldRayDir, vec3 viewRayDir, vec3 baseVoidSky) {
    vec3 ray = normalize(worldRayDir);
    vec3 sky = baseVoidSky;

    float horizonVis = smoothstep(-0.22, 0.10, ray.y);
    float starVis    = clamp(horizonVis + smoothstep(-0.04, -0.24, ray.y) * 0.88, 0.0, 1.0);
    vec2 horizDir = ray.xz / max(length(ray.xz), 1e-4);
    float riverY  = evaluateEndCelestialRiverY(horizDir);
    float canopyY = 0.56 + 0.07 * (-horizDir.y * 0.80 + horizDir.x * 0.60);

    // 1. Multi-Octave 3D Volumetric Nebula (Pure 3D trilinear silk/nebula field)
    vec3 p1 = ray * 0.52 + vec3(frameTimeCounter * 0.0018, 0.14, -frameTimeCounter * 0.0012);
    vec4 vol1 = cloudVolume(p1);

    vec3 p2 = ray * 1.08 - vol1.xyz * 0.22 + vec3(-frameTimeCounter * 0.0026, 0.31, frameTimeCounter * 0.0020);
    vec4 vol2 = cloudVolume(p2);

    vec3 p3 = ray * 2.15 + vol2.yzx * 0.16 + vec3(frameTimeCounter * 0.0034, -0.22, frameTimeCounter * 0.0016);
    vec4 vol3 = cloudVolume(p3);

    float mainRiverBand    = exp(-pow((ray.y - riverY) / 0.27, 2.0));
    float upperCanopyBand  = exp(-pow((ray.y - canopyY) / 0.23, 2.0)) * 0.65;
    float lowerAbyssBridge = exp(-pow((ray.y + 0.22) / 0.24, 2.0)) * 0.55;
    float skyEnvelope      = clamp(mainRiverBand + upperCanopyBand + lowerAbyssBridge, 0.0, 1.0);

    float fbm      = vol1.r * 0.48 + vol2.g * 0.34 + vol3.b * 0.18;
    float nebMask  = smoothstep(0.22, 0.75, fbm) * skyEnvelope;
    float nebRidge = smoothstep(0.46, 0.82, vol1.g * 0.55 + vol2.r * 0.45) * nebMask;
    float silkWisp = smoothstep(0.54, 0.86, vol2.g * 0.52 + vol3.r * 0.48) * nebMask;
    float darkRift = smoothstep(0.42, 0.76, vol2.b) * 0.45;

    vec3 cFold, cBody, cCrest;
    if (STYLE_SELECTION == 0) {
        cFold  = vec3(0.014, 0.026, 0.020);
        cBody  = vec3(0.054, 0.098, 0.078);
        cCrest = vec3(0.155, 0.198, 0.148);
    } else {
        cFold  = vec3(0.012, 0.034, 0.040);
        cBody  = vec3(0.044, 0.132, 0.136);
        cCrest = vec3(0.122, 0.295, 0.278);
    }

    vec3 nebColor = mix(cFold, cBody, smoothstep(0.0, 0.64, nebMask));
    nebColor = mix(nebColor, cCrest, clamp(nebRidge + silkWisp * 0.45, 0.0, 1.0));
    nebColor = mix(nebColor, baseVoidSky * 0.85, darkRift);

    // 2. Varied-Angle Square Tangent-Plane Stars in the Deep Void
    if (starVis > 0.01) {
        sky += renderEndTangentSquareStars(ray) * starVis * (1.0 - nebMask * 0.55);
    }

    // (Side skybox vertical glyph columns removed; characters live on the 3D wave surfaces)

    // 4. Composite 3D Volumetric Nebula Body & Horizon Bridge
    sky = mix(sky, nebColor, nebMask * 0.78);

    // 5. Zenith & Nadir End Sky Architecture:
    //    - Wuxia Smooth (SKY_STYLE == 0): Taixu Celestial Formation Array overhead + 3-layer ink cloud-sea & reflection below
    //    - Minecraft Voxel (SKY_STYLE == 1): Contiguous 3D Sound-Wave Ocean columns with cap-face runes
    float waveOcclusion = 0.0;
    if (abs(ray.y) > 0.05) {
        vec4 skyArch = (SKY_STYLE == 1)
            ? renderEndSoundWaveOcean3D(ray, nebColor, nebMask)
            : renderEndSmoothTaixuSky(ray, nebColor, nebMask);
        sky = mix(sky, skyArch.rgb, skyArch.a);
        waveOcclusion = skyArch.a;

        // Soft volumetric nebula veil drifting gently in front of distant troughs / outer perimeter
        float frontMist = nebMask * (0.14 + 0.28 * (1.0 - smoothstep(0.12, 0.48, abs(ray.y)))) * skyArch.a;
        sky = mix(sky, max(sky, nebColor * 1.12), frontMist);
    }
    // Cohesive End horizon mist band matching isotropicEndMist fog around Obsidian Pillars
    float horizMistGlow = exp(-pow((ray.y - 0.02) / 0.20, 2.0));
    vec3 endHorizBand   = (STYLE_SELECTION == 0) ? vec3(0.034, 0.056, 0.045) : vec3(0.026, 0.072, 0.076);
    sky = mix(sky, max(sky, endHorizBand), horizMistGlow * 0.65);



    return max(sky, vec3(0.0));
}
#endif

// Parallel planes behind the End Portal block aperture
vec3 renderYunMengEndPortal(vec3 playerPos, vec3 rayPlayer) {
    vec2 world = playerPos.xz + cameraPosition.xz;
    vec3 ray = normalize(rayPlayer);
    vec2 slope = ray.xz / sqrt(ray.y * ray.y + dot(ray.xz, ray.xz) * 0.065);
    vec3 color = STYLE_SELECTION == 0 ? vec3(0.016, 0.036, 0.023) : vec3(0.022, 0.052, 0.039);
    if (STYLE_SELECTION == 1) {
        float haze = 0.5 + 0.5 * sin(world.x * 0.43 + world.y * 0.31 + frameTimeCounter * 0.08)
            * sin(world.y * 0.57 - world.x * 0.19 - frameTimeCounter * 0.05);
        color += vec3(0.010, 0.020, 0.012) * haze;
    }
    vec3 starlight = vec3(0.0);
    for (int i = 0; i < END_PORTAL_LAYERS; i++) {
        float f = float(i) / float(END_PORTAL_LAYERS - 1);
        float layerDepth = mix(2.8, 0.30, f);
        float tileWidth = STYLE_SELECTION == 0 ? mix(3.4, 5.0, f) : mix(4.5, 6.5, f);
        vec2 uv = (world + slope * layerDepth) / tileWidth;
        uv += vec2(0.173, 0.317) * float(i);
        uv += frameTimeCounter * (STYLE_SELECTION == 0 ? vec2(0.0012, 0.0003) : vec2(0.0060, -0.0021)) * (0.55 + f * 0.45);
        vec2 pixelUV = (floor(uv * 256.0) + 0.5) / 256.0;
        vec4 layer = (STYLE_SELECTION == 0)
            ? textureLod(portalInkTex, fract(pixelUV), 0.0)
            : textureLod(portalCloudTex, fract(pixelUV), 0.0);
        float worldFootprint = max(length(playerPos), 0.01) * 1.2 / max(viewHeight, 1.0) / max(abs(ray.y), 0.10);
        float footprint = worldFootprint / tileWidth;
        float detail = 1.0 - smoothstep(0.012, 0.065, footprint);
        float opacity = layer.a * (STYLE_SELECTION == 0 ? mix(0.12, 0.78, f) : mix(0.22, 0.86, f)) * detail;
        vec3 tint = STYLE_SELECTION == 0 ? vec3(0.88, 0.98, 0.90) : vec3(0.78, 1.05, 1.16);
        vec3 lit = layer.rgb * tint * mix(0.35, 0.92, f);
        if (STYLE_SELECTION == 0) {
            float tone = dot(layer.rgb, vec3(0.25, 0.50, 0.25));
            lit = mix(vec3(0.07, 0.20, 0.12), vec3(0.68, 0.86, 0.65), tone)
                * tone * mix(0.40, 1.0, f);
        }
        if (STYLE_SELECTION == 1) {
            float tone = dot(layer.rgb, vec3(0.25, 0.50, 0.25));
            float crest = smoothstep(0.30, 0.70, tone);
            vec3 jade = vec3(max(layer.r, layer.g * 0.50), layer.g * 1.04,
                layer.b * 0.70 + layer.g * 0.18);
            lit = jade * mix(0.35, 0.92, f) * 1.12
                + vec3(0.16, 0.20, 0.08) * crest * mix(0.30, 0.80, f);
            float shadedFold = (1.0 - smoothstep(0.15, 0.40, tone)) * mix(0.70, 0.25, f);
            lit = mix(lit, vec3(0.020, 0.070, 0.050) * mix(0.55, 1.0, f), shadedFold);
        }
        color = mix(color, lit, opacity);
    }
    float starFootprint = max(length(playerPos), 0.01) * 1.2 / max(viewHeight, 1.0) / max(abs(ray.y), 0.10);
    starlight = portalStars(world + slope * 1.35, starFootprint);
    if (STYLE_SELECTION == 0) starlight *= vec3(0.88, 0.94, 0.78);
    return max(color + starlight, vec3(0.0));
}
#endif
