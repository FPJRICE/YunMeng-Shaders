#version 330 compatibility
#include "/lib/temporal_jitter.glsl"
#include "/lib/camera_options.glsl"
// Modified 2026-10-15: extended Guofeng and Xianxia above-water depth-color ramps.
/* =============================================================================
 * gbuffers_water.fsh — Surface-aligned water normals and depth absorption.
 * Shore contact foam is evaluated once, after geometry, in composite.fsh.
 * ============================================================================= */

#define STYLE_SELECTION 1          // [0 1] 0: Guofeng Ink, 1: Xianxia Mist
#define WATER_FOAM_INTENSITY 1.00  // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define WATER_WAVE_HEIGHT 1.00     // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define WIND_SPEED 1.00            // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]

in vec2 vTexCoord;
in vec2 vLmCoord;
in vec3 vViewNormal;
in vec3 vWorldNormal;
in vec3 vWorldPos;
in vec3 vPlayerPos;
in vec4 vVertexColor;
flat in int vMaterialId;
in float vVerticalCurtain;

uniform sampler2D gtexture;
uniform sampler2D depthtex1;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform int isEyeInWater;

#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
/* RENDERTARGETS: 0,1,2,5 */
layout(location = 3) out vec4 outMotion;
#else
/* RENDERTARGETS: 0,1,2 */
#endif
layout(location = 0) out vec4 outColor0;
layout(location = 1) out vec4 outColor1;
layout(location = 2) out vec4 outColor2;

float linearizeDepth(float d) {
    return (2.0 * near * far) / max(far + near - (d * 2.0 - 1.0) * (far - near), 1e-5);
}

vec3 reconstructViewPos(vec2 uv, float depth) {
    vec4 ndc = vec4((uv - cameraJitter(frameCounter, vec2(viewWidth, viewHeight))) * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * ndc;
    return viewPos.xyz / max(viewPos.w, 1e-6);
}

// Hash without Sine by David Hoskins (MIT License, https://www.shadertoy.com/view/4djSRW)
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Quintic value noise & analytical 2D derivatives (Ken Perlin 2002; Inigo Quilez, MIT License)
vec3 smoothNoiseGrad(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    float a = hash12(i + vec2(0.0, 0.0));
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));

    vec2 u  = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    float val = a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y;
    vec2 grad = du * vec2(
        (b - a) + (a - b - c + d) * u.y,
        (c - a) + (a - b - c + d) * u.x
    );
    return vec3(grad, val);
}

float fbmSmooth(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(0.80, -0.60, 0.60, 0.80);
    for (int i = 0; i < 3; i++) {
        v += a * smoothNoiseGrad(p).z;
        p = rot * p * 2.03 + vec2(13.7, 29.3);
        a *= 0.5;
    }
    return v;
}

vec3 evaluateFilteredWaveField(vec2 wp, float time, float viewDist) {
    const mat2 ROT1 = mat2( 0.921, -0.389,  0.389,  0.921);
    const mat2 ROT2 = mat2( 0.629,  0.777, -0.777,  0.629);
    const mat2 ROT3 = mat2(-0.438,  0.899, -0.899, -0.438);
    const mat2 ROT4 = mat2( 0.259, -0.966,  0.966,  0.259);

    float mip1 = exp(-viewDist * 0.008);
    float mip2 = exp(-viewDist * 0.018);
    float mip3 = exp(-viewDist * 0.038);
    float mip4 = exp(-viewDist * 0.075);

    vec2 uv1 = ROT1 * (wp * 0.11) + vec2( 0.09,  0.04) * time;
    vec2 uv2 = ROT2 * (wp * 0.27) + vec2(-0.13,  0.08) * time;
    vec2 uv3 = ROT3 * (wp * 0.59) + vec2( 0.17, -0.11) * time;
    vec2 uv4 = ROT4 * (wp * 1.23) + vec2(-0.23, -0.19) * time;

    vec3 n1 = smoothNoiseGrad(uv1 * 3.2);
    vec3 n2 = smoothNoiseGrad(uv2 * 3.2 + n1.xy * 0.25);
    vec3 n3 = smoothNoiseGrad(uv3 * 3.2 + n2.xy * 0.20);
    vec3 n4 = smoothNoiseGrad(uv4 * 3.2);

    vec2 grad = n1.xy * (0.42 * mip1)
              + n2.xy * (0.34 * mip2)
              + n3.xy * (0.22 * mip3)
              + n4.xy * (0.14 * mip4);
    float height = n1.z * 0.45 + n2.z * 0.35 + n3.z * 0.20;

    return vec3(grad, height);
}

void main() {
#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
    outMotion = vec4(0.0);
#endif
    vec4 texSample = texture(gtexture, vTexCoord);
    if (texSample.a < 0.05) {
        discard;
    }

    bool isWater = (vMaterialId == 8200);
    if (!isWater) {
        outColor0 = vec4(texSample.rgb * vVertexColor.rgb, texSample.a);
        outColor1 = vec4(normalize(vViewNormal) * 0.5 + 0.5, 0.0);
        outColor2 = vec4(vLmCoord.x, vLmCoord.y, vVertexColor.a, 0.0);
        return;
    }

    vec2 screenUV = gl_FragCoord.xy / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    float solidRawDepth = texture(depthtex1, screenUV).r;

    vec3 solidViewPos   = reconstructViewPos(screenUV, solidRawDepth);
    vec3 solidPlayerPos = (gbufferModelViewInverse * vec4(solidViewPos, 1.0)).xyz;
    vec3 solidWorldPos  = solidPlayerPos + cameraPosition;

    // This is the ray-visible bottom, not a view-independent bathymetry map.
    // Use it for absorption only; it must never create shoreline foam.
    float verticalWaterDepth = solidRawDepth < 0.999999
        ? max(vWorldPos.y - solidWorldPos.y, 0.0) : 32.0;
    float faceThickness = solidRawDepth < 0.999999
        ? abs(dot(solidPlayerPos - vPlayerPos, normalize(vWorldNormal))) : 32.0;
    float absorptionDepth = mix(verticalWaterDepth, faceThickness, vVerticalCurtain);

    float time = frameTimeCounter * WIND_SPEED;
    vec2 wp = vWorldPos.xz;
    float viewDist = length(vPlayerPos);

    // Planar coordinates follow the geometric face, including waterfall walls.
    // Never replace a vertical face normal with an upward-facing water normal.
    vec3 geoNormal = normalize(vWorldNormal);
    vec3 tangent = normalize(cross(abs(geoNormal.z) < 0.9
        ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0), geoNormal));
    vec3 bitangent = normalize(cross(geoNormal, tangent));
    vec3 patternPos = vWorldPos;
    patternPos.y += time * 0.85 * vVerticalCurtain; // pattern travels downward
    vec2 worldCoord = vec2(dot(patternPos, tangent), dot(patternPos, bitangent));
    vec3 blendedWave = evaluateFilteredWaveField(worldCoord, time, viewDist);

    vec3 viewRayWorld = normalize(vPlayerPos);
    float NdotVGeo = clamp(abs(dot(viewRayWorld, geoNormal)), 0.0, 1.0);

    float grazingDamp = mix(0.25, 1.0, NdotVGeo);
    float normalStrength = (STYLE_SELECTION == 0 ? 0.09 : 0.15) * WATER_WAVE_HEIGHT * grazingDamp;
    vec3 worldWaveNormal = normalize(geoNormal - normalStrength *
        (blendedWave.x * tangent + blendedWave.y * bitangent));
    vec3 perturbedViewNormal = normalize(mat3(gbufferModelView) * worldWaveNormal);

    float NdotV = clamp(abs(dot(worldWaveNormal, viewRayWorld)), 0.0, 1.0);
    float fresnel = pow(1.0 - NdotV, 3.8);

    vec3 finalWaterColor;
    float finalAlpha;

    if (isEyeInWater == 1) {
        float snellWindow = smoothstep(0.48, 0.74, NdotV);
        if (STYLE_SELECTION == 0) {
            vec3 tirCeladon   = vec3(0.16, 0.32, 0.34);
            vec3 windowBright = vec3(0.72, 0.82, 0.78);
            finalWaterColor   = mix(tirCeladon, windowBright, snellWindow);
            finalAlpha        = mix(0.84, 0.38, snellWindow);
        } else {
            vec3 tirAbyssal   = vec3(0.03, 0.18, 0.28);
            vec3 windowBright = vec3(0.38, 0.78, 0.86);
            float causticRim  = smoothstep(0.45, 0.65, NdotV) * (1.0 - smoothstep(0.65, 0.80, NdotV));
            finalWaterColor   = mix(tirAbyssal, windowBright, snellWindow) + vec3(0.25, 0.65, 0.70) * causticRim;
            finalAlpha        = mix(0.88, 0.32, snellWindow);
        }
        outColor0 = vec4(finalWaterColor, finalAlpha);
        outColor1 = vec4(-perturbedViewNormal * 0.5 + 0.5, 0.90);
        outColor2 = vec4(vLmCoord.x, vLmCoord.y, 1.0, vVerticalCurtain);
        return;
    }

    if (STYLE_SELECTION == 0) {
        vec2 panUV = wp * 0.13 + vec2(-time * 0.075, 0.0);
        float strokeRibbon = smoothstep(0.50, 0.76, fbmSmooth(vec2(panUV.x * 1.2, panUV.y * 4.5))) * (1.0 - vVerticalCurtain);

        vec3 shallowCeladon = vec3(0.34, 0.58, 0.56);
        vec3 deepJadeInk    = vec3(0.14, 0.32, 0.36);
        float depthBlend    = clamp(1.0 - exp(-absorptionDepth * 0.45), 0.0, 1.0);

        finalWaterColor = mix(shallowCeladon, deepJadeInk, depthBlend);
        finalWaterColor = mix(finalWaterColor, vec3(0.78, 0.84, 0.80), strokeRibbon * 0.20);
        finalAlpha = clamp(0.48 + depthBlend * 0.36 + fresnel * 0.24, 0.0, 0.94);
        // Preserve jade/ink colors, with a longer gradient across river shelves.
        float extendedDepth = (1.0 - exp(-absorptionDepth * 0.18)) * 0.70 +
                              (1.0 - exp(-absorptionDepth * 0.04)) * 0.30;
        vec3 depthColor = mix(shallowCeladon, vec3(0.055, 0.15, 0.17), extendedDepth);
        depthColor = mix(depthColor, vec3(0.78, 0.84, 0.80), strokeRibbon * 0.20);
        float depthAlpha = clamp(0.38 + extendedDepth * 0.50 + fresnel * 0.24, 0.0, 0.94);
        finalWaterColor = mix(depthColor, finalWaterColor, vVerticalCurtain);
        finalAlpha = mix(depthAlpha, finalAlpha, vVerticalCurtain);
    } else {
        // Extend the depth ramp so shelves, channels and deep water stay distinct.
        // Vertical sheets retain their existing face-thickness treatment.
        vec3 shallowJade  = vec3(0.12, 0.52, 0.58);
        vec3 deepSapphire = vec3(0.04, 0.22, 0.38);
        float depthBlend  = clamp(1.0 - exp(-absorptionDepth * 0.42), 0.0, 1.0);

        finalWaterColor = mix(shallowJade, deepSapphire, depthBlend);
        finalAlpha = clamp(0.40 + depthBlend * 0.42 + fresnel * 0.34, 0.0, 0.94);

        float shelfBlend = 1.0 - exp(-absorptionDepth * 0.16);
        float abyssBlend = 1.0 - exp(-absorptionDepth * 0.035);
        float extendedDepth = shelfBlend * 0.70 + abyssBlend * 0.30;
        vec3 depthColor = mix(shallowJade, vec3(0.015, 0.075, 0.16), extendedDepth);
        float depthAlpha = clamp(0.30 + extendedDepth * 0.62 + fresnel * 0.34, 0.0, 0.94);
        finalWaterColor = mix(depthColor, finalWaterColor, vVerticalCurtain);
        finalAlpha = mix(depthAlpha, finalAlpha, vVerticalCurtain);
    }

    outColor0 = vec4(finalWaterColor, finalAlpha);
    outColor1 = vec4(perturbedViewNormal * 0.5 + 0.5, 0.90);
    // Water-only metadata: alpha stores vertical-face weight, not a foam mask.
    outColor2 = vec4(vLmCoord.x, vLmCoord.y, 1.0, vVerticalCurtain);
}
