#version 330 compatibility
#include "/lib/camera_options.glsl"
#include "/lib/presentation.glsl"
noperspective in vec2 vTexCoord;
layout(location = 0) out vec4 outColor0;

#if ANTI_ALIASING > 0
uniform sampler2D colortex3;

vec3 preparedPixel(ivec2 p) {
    return texelFetch(colortex3, clamp(p, ivec2(0), textureSize(colortex3, 0) - 1), 0).rgb;
}

vec3 preparedLinear(vec2 pixel) {
    vec2 q = pixel - 0.5;
    ivec2 p = ivec2(floor(q));
    vec2 f = fract(q);
    return mix(mix(preparedPixel(p), preparedPixel(p + ivec2(1, 0)), f.x),
               mix(preparedPixel(p + ivec2(0, 1)), preparedPixel(p + ivec2(1, 1)), f.x), f.y);
}

float aaLuma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 spatialAA(vec2 uv) {
    ivec2 texSize = textureSize(colortex3, 0);
    vec2 pixel = uv * vec2(texSize);
    ivec2 p = ivec2(pixel);

    vec3 c  = preparedPixel(p);
    vec3 cN = preparedPixel(p + ivec2( 0,  1));
    vec3 cS = preparedPixel(p + ivec2( 0, -1));
    vec3 cE = preparedPixel(p + ivec2( 1,  0));
    vec3 cW = preparedPixel(p + ivec2(-1,  0));

    float m = aaLuma(c);
    float n = aaLuma(cN);
    float s = aaLuma(cS);
    float e = aaLuma(cE);
    float w = aaLuma(cW);

    float nw = aaLuma(preparedPixel(p + ivec2(-1,  1)));
    float ne = aaLuma(preparedPixel(p + ivec2( 1,  1)));
    float sw = aaLuma(preparedPixel(p + ivec2(-1, -1)));
    float se = aaLuma(preparedPixel(p + ivec2( 1, -1)));

    float lo = min(m, min(min(n, s), min(e, w)));
    float hi = max(m, max(max(n, s), max(e, w)));
    float boxLo = min(lo, min(min(nw, ne), min(sw, se)));
    float boxHi = max(hi, max(max(nw, ne), max(sw, se)));
    float contrast = boxHi - boxLo;

    // Contrast-adaptive texture crispening across all AA modes keeps 16x16 block pixel art sharp and true to texture
    vec3 neighborAvg = (cN + cS + cE + cW) * 0.25;
    vec3 rgbLo = min(c, min(min(cN, cS), min(cE, cW)));
    vec3 rgbHi = max(c, max(max(cN, cS), max(cE, cW)));
    vec3 crispCenter = clamp(c + (c - neighborAvg) * 0.16, rgbLo, rgbHi);

    if (contrast < max(0.032, boxHi * 0.12)) {
        return crispCenter;
    }

    // Sobel 3x3 gradient incorporates diagonal neighbors for accurate staircase orientation
    float gradX = (ne + 2.0 * e + se) - (nw + 2.0 * w + sw);
    float gradY = (nw + 2.0 * n + ne) - (sw + 2.0 * s + se);
    vec2 gradient = vec2(gradX, gradY);
    float g = length(gradient);
    if (g < contrast * 0.18) return crispCenter;

    // Require strong directional coherence so internal block pixel-art texels are never blurred!
    float gradientBudget = abs(ne - nw) + 2.0 * abs(e - w) + abs(se - sw)
        + abs(nw - sw) + 2.0 * abs(n - s) + abs(ne - se);
    float edgeConfidence = smoothstep(0.54, 0.84, g / max(gradientBudget, 1e-5));
    if (edgeConfidence <= 0.0) return crispCenter;

    float neighborLo = min(min(n, s), min(e, w));
    float neighborHi = max(max(n, s), max(e, w));
    if (m > neighborHi + contrast * 0.16 || m < neighborLo - contrast * 0.16) return crispCenter;

    vec2 tangent = vec2(-gradient.y, gradient.x) / g;

    float spanScale = (ANTI_ALIASING == 2) ? 0.90 : 0.70;
    vec3 tap1 = (preparedLinear(pixel + tangent * (0.55 * spanScale)) +
                 preparedLinear(pixel - tangent * (0.55 * spanScale))) * 0.5;
    vec3 tap2 = (preparedLinear(pixel + tangent * (0.95 * spanScale)) +
                 preparedLinear(pixel - tangent * (0.95 * spanScale))) * 0.5;

    float lumaTap2 = aaLuma(tap2);
    bool tap2InBounds = (lumaTap2 >= boxLo && lumaTap2 <= boxHi);
    vec3 edgeFiltered = tap2InBounds ? mix(tap1, tap2, 0.20) : tap1;

    float fl = aaLuma(edgeFiltered);
    if (fl < boxLo || fl > boxHi) edgeFiltered = tap1;

    float baseBlend = (ANTI_ALIASING == 2) ? 0.34 : (ANTI_ALIASING == 3 ? 0.18 : 0.24);
    float finalWeight = clamp(baseBlend * edgeConfidence, 0.0, 0.42);
    return mix(crispCenter, edgeFiltered, finalWeight);
}
#endif

void main() {
#if ANTI_ALIASING > 0
    vec3 color = spatialAA(vTexCoord);
    if (STYLE_SELECTION == 0 && PAPER_GRAIN_STRENGTH > 0.0) {
        vec2 paperUV = vTexCoord;
        if (isEyeInWater == 1 && UNDERWATER_DISTORTION_STRENGTH > 0.0) {
            paperUV += vec2(sin(paperUV.y * 14.0 + frameTimeCounter * 2.1),
                            cos(paperUV.x * 12.0 - frameTimeCounter * 1.8)) * (0.0018 * UNDERWATER_DISTORTION_STRENGTH);
            paperUV = clamp(paperUV, vec2(0.002), vec2(0.998));
        }
        color += vec3((valueNoise(paperUV * vec2(viewWidth, viewHeight) * 0.22) - 0.5) * 0.012 * PAPER_GRAIN_STRENGTH);
    }
#else
    vec3 color = preparePresentation(vTexCoord, true);
#endif
    outColor0 = vec4(applyPresentationBorder(color, vTexCoord), 1.0);
}
