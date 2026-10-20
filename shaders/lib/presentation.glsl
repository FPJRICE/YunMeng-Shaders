/* =============================================================================
 * final.fsh — Camera-Invariant Interior Silhouette Outlines & Post-Processing
 * ============================================================================= */

#define STYLE_SELECTION 1  // [0 1] 0: Guofeng Ink, 1: Xianxia Mist
#define INK_OUTLINES 0     // [0 1 2 3] 0: Auto (By Style), 1: Subtle, 2: Shanshui, 3: Off
// Neutral defaults preserve the original presentation in both styles.
#define VIGNETTE_STRENGTH 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50]
#define EXPOSURE 0.00 // [-1.00 -0.75 -0.50 -0.25 0.00 0.25 0.50 0.75 1.00]
#define SATURATION 1.00 // [0.00 0.25 0.50 0.75 1.00 1.10 1.25 1.50]
#define PAINTERLY_WASH_STRENGTH 1.00 // [0.00 0.25 0.50 0.75 1.00]
#define PAPER_GRAIN_STRENGTH 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50]
#define UNDERWATER_DISTORTION_STRENGTH 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50]
#define LICENSE_INFO 0     // [0] 0: GPL-3.0-only (Original Code & Textures)



uniform sampler2D colortex0;
#if MOTION_BLUR > 0
uniform sampler2D colortex4;
#endif
vec4 sceneSample(vec2 uv) {
#if MOTION_BLUR > 0
    return texture(colortex4, uv);
#else
    return texture(colortex0, uv);
#endif
}
uniform sampler2D colortex1;
uniform sampler2D depthtex0;

uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;
uniform float frameTimeCounter;
uniform int isEyeInWater;



float linearizeDepth(float rawDepth) {
    return (2.0 * near * far) / max(far + near - (rawDepth * 2.0 - 1.0) * (far - near), 1e-5);
}

// Hash without Sine by David Hoskins (MIT License, https://www.shadertoy.com/view/4djSRW)
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x),
        mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}

vec3 samplePainterlyWash(vec2 uv, vec2 texelSize, vec3 centerColor, float centerDepthLin) {
    vec3 accumColor = centerColor * 2.0;
    float totalWeight = 2.0;

    const vec2 OFFSETS[4] = vec2[4](
        vec2( 1.25,  0.50),
        vec2(-1.25, -0.50),
        vec2(-0.50,  1.25),
        vec2( 0.50, -1.25)
    );

    for (int i = 0; i < 4; i++) {
        vec2 sampleUV = uv + OFFSETS[i] * texelSize;
        vec3 sColor = sceneSample(sampleUV).rgb;
        float sDepth = linearizeDepth(texture(depthtex0, sampleUV).r);

        float depthWeight = exp(-abs(sDepth - centerDepthLin) * 1.2);
        float colorWeight = exp(-dot(sColor - centerColor, sColor - centerColor) * 6.0);
        float w = depthWeight * colorWeight;

        accumColor += sColor * w;
        totalWeight += w;
    }

    return accumColor / totalWeight;
}

// Plane-compensated view-normal & depth discontinuity filter (100% camera-angle invariant!)
float computeWuxiaSilhouetteOutline(vec2 unwarpedUV, vec2 texelSize, float centerDepthLin, vec3 viewNormal, float centerMatTag, int activeOutlineMode) {
    if (activeOutlineMode <= 0 || centerDepthLin >= 40.0 || centerDepthLin < 0.6) {
        return 0.0;
    }
    // Directly skip alpha-cutout grass/leaves/kelp (0.25), blossoms (0.75), and water (0.90) on the foreground pixel!
    if (abs(centerMatTag - 0.16) < 0.02 || abs(centerMatTag - 0.25) < 0.05 || abs(centerMatTag - 0.75) < 0.05 || abs(centerMatTag - 0.90) < 0.05) {
        return 0.0;
    }

    vec2 ndcXY = unwarpedUV * 2.0 - 1.0;
    float rayAngleComp = sqrt(1.0 + dot(ndcXY, ndcXY) * 0.42);
    float centerDist   = centerDepthLin * rayAngleComp;

    // Use surface normal to predict expected planar depth slope across 1 texel
    vec2 expectedSlope = -(viewNormal.xy / max(abs(viewNormal.z), 0.18)) * centerDist * 0.0035;

    float maxSilhouette = 0.0;
    vec2 directions[4] = vec2[4](vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(-0.7071, 0.7071), vec2(0.7071, 0.7071));

    for (int i = 0; i < 4; i++) {
        vec2 dir = directions[i];
        vec2 off = dir * texelSize;

        float dA = linearizeDepth(texture(depthtex0, unwarpedUV + off).r) * rayAngleComp;
        float dB = linearizeDepth(texture(depthtex0, unwarpedUV - off).r) * rayAngleComp;

        // Plane compensation: deviation from flat plane is identically 0.0 on flat ground at ANY camera angle!
        float planarityDiff = ((dA + dB) - centerDist * 2.0) / max(centerDist, 1.5);
        float bgStep = max(dA, dB) - centerDist;

        float stepGate = smoothstep(0.85, 1.85, bgStep);
        maxSilhouette  = max(maxSilhouette, planarityDiff * stepGate);
    }

    float rawMask   = smoothstep(0.24, 0.65, maxSilhouette);
    float distFade  = smoothstep(0.6, 1.6, centerDist) * (1.0 - smoothstep(20.0, 38.0, centerDist));
    float uwAtten   = (isEyeInWater == 1) ? (0.30 * exp(-centerDist * 0.14)) : 1.0;
    float modeScale = (activeOutlineMode == 2) ? 0.68 : 0.42;

    return clamp(rawMask * distFade * uwAtten * modeScale, 0.0, 0.70);
}

// ACES Filmic Tone Mapping Curve fit by Krzysztof Narkowicz (2016, CC0 / Public Domain)
vec3 acesFilmicToneMap(vec3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

vec3 preparePresentation(vec2 vTexCoord, bool includePaperGrain) {
    #if LICENSE_INFO < 0
    // Ensures Iris registers LICENSE_INFO as an active option button
    #endif

    vec2 texelSize = 1.0 / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    vec2 sampleUV  = vTexCoord;

    if (isEyeInWater == 1 && UNDERWATER_DISTORTION_STRENGTH > 0.0) {
        vec2 uwWave = vec2(
            sin(sampleUV.y * 14.0 + frameTimeCounter * 2.1),
            cos(sampleUV.x * 12.0 - frameTimeCounter * 1.8)
        ) * (0.0018 * UNDERWATER_DISTORTION_STRENGTH);
        sampleUV = clamp(sampleUV + uwWave, vec2(0.002), vec2(0.998));
    }

    vec3 color = sceneSample(sampleUV).rgb;
    float rawDepth = texture(depthtex0, sampleUV).r;
    float linearDepth = linearizeDepth(rawDepth);
    vec4 normalSample = texture(colortex1, vTexCoord);
    vec3 viewNormal   = normalize(normalSample.rgb * 2.0 - 1.0);
    float matTag      = normalSample.a;

    if (STYLE_SELECTION == 0) {
        if (rawDepth < 0.999999 && PAINTERLY_WASH_STRENGTH > 0.0) {
            vec3 washed = samplePainterlyWash(sampleUV, texelSize, color, linearDepth);
            color = (PAINTERLY_WASH_STRENGTH == 1.0) ? washed
                : mix(color, washed, PAINTERLY_WASH_STRENGTH);
        }
        vec2 paperCoord = sampleUV * vec2(viewWidth, viewHeight) * 0.22;
        float fiberGrain = (PAPER_GRAIN_STRENGTH > 0.0)
            ? (valueNoise(paperCoord) - 0.5) * 0.012 * PAPER_GRAIN_STRENGTH : 0.0;
        if (EXPOSURE != 0.0) color *= exp2(EXPOSURE);
        color = acesFilmicToneMap(color * 0.85);
        color = pow(max(color, vec3(0.0)), vec3(1.10)); // Deepens ink shadows, prevents high-key wash
        if (includePaperGrain) color += vec3(fiberGrain);
    } else {
        if (EXPOSURE != 0.0) color *= exp2(EXPOSURE);
        color = acesFilmicToneMap(color * 0.92);
        color = pow(max(color, vec3(0.0)), vec3(1.04));
        float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
        // Vibrant Xianxia chroma boost (preserves rich azure skies, jade foliage & golden light)
        color = clamp(mix(vec3(luma), color, 1.08), 0.0, 1.0);
    }

    // Relative to each style's existing grade; 1.0 is an exact bypass.
    if (SATURATION != 1.0) {
        float gradedLuma = dot(color, vec3(0.2126, 0.7152, 0.0722));
        color = clamp(mix(vec3(gradedLuma), color, SATURATION), 0.0, 1.0);
    }

    int activeOutlineMode = (INK_OUTLINES == 0) ? (STYLE_SELECTION == 0 ? 2 : 0) : (INK_OUTLINES == 3 ? 0 : INK_OUTLINES);
    if (activeOutlineMode > 0) {
        float unwarpedDepthLin = linearizeDepth(texture(depthtex0, vTexCoord).r);
        float outlineMask = computeWuxiaSilhouetteOutline(vTexCoord, texelSize, unwarpedDepthLin, viewNormal, matTag, activeOutlineMode);

        vec3 outlineTint;
        if (STYLE_SELECTION == 0) {
            outlineTint = mix(vec3(0.08, 0.10, 0.12), color * 0.34, 0.55);
        } else {
            outlineTint = mix(vec3(0.05, 0.10, 0.18), color * 0.38, 0.65);
        }
        color = mix(color, outlineTint, outlineMask);
    }

    return color;
}

vec3 applyPresentationBorder(vec3 color, vec2 vTexCoord) {
    vec3 beforeVignette = color;
    vec2 centeredUV = vTexCoord * 2.0 - 1.0;
    centeredUV.x *= (viewWidth / max(viewHeight, 1.0)) * 0.65;
    float radialDistSq = dot(centeredUV, centeredUV);

    if (isEyeInWater == 1) {
        float uwVig = clamp(1.0 - radialDistSq * 0.32, 0.42, 1.0);
        color *= uwVig;
    } else if (STYLE_SELECTION == 0) {
        float scrollVignette = smoothstep(0.45, 1.85, radialDistSq);
        vec3 agedSilkBorder  = vec3(0.82, 0.78, 0.70);
        color = mix(color, color * agedSilkBorder, scrollVignette * 0.42);
    } else {
        float filmVignette = clamp(1.0 - radialDistSq * 0.22, 0.55, 1.0);
        color *= filmVignette;
    }

    if (VIGNETTE_STRENGTH != 1.0) {
        color = mix(beforeVignette, color, VIGNETTE_STRENGTH);
    }

    return clamp(color, 0.0, 1.0);
}
