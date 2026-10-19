#version 330 compatibility
#include "/lib/temporal_jitter.glsl"
// Build 2 performance update: scalable cloud, shadow and shoreline settings.
/* =============================================================================
 * composite.fsh — Lighting, colored shadows, SSR, and style grading
 * Modified 2026-10-15: Xianxia above-water bottom shadows and lighter caustics.
 * Build 2: depth absorption in both styles after blending, before reflections.
 * ============================================================================= */

#define STYLE_SELECTION 1          // [0 1] 0: Guofeng Ink, 1: Xianxia Mist
#define SHADOW_FILTER_QUALITY 1    // [0 1 2] Low, Medium, High
#define FOAM_QUALITY 1             // [0 1 2] Low, Medium, High
#define CAUSTICS_STRENGTH 1.00     // [0.00 0.25 0.50 0.75 1.00 1.25 1.50]
#define WATER_REFLECTIONS 1        // [0 1 2] 0: Sky Only, 1: Fast SSR, 2: Full SSR
#define WATER_FOAM_INTENSITY 1.00  // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define WIND_SPEED 1.00            // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]

const float sunPathRotation = -42.0;
const int shadowMapResolution = 2048; // [1024 2048 4096]

noperspective in vec2 vTexCoord;
flat in vec3 vLightViewDir;
flat in vec3 vSunViewDir;
flat in vec3 vMoonViewDir;
flat in vec3 vSunWorldDir;
flat in vec3 vMoonWorldDir;
flat in vec3 vUpViewDir;
flat in float vDaylightFactor;
flat in float vTwilightFactor;
flat in float vNightFactor;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D foamTex;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform vec3 cameraPosition;
uniform vec3 skyColor;
uniform vec3 fogColor;
uniform float frameTimeCounter;
uniform float viewHeight;
uniform float viewWidth;
uniform int frameCounter;
uniform float rainStrength;
uniform float wetness;
uniform float near;
uniform float far;
uniform int isEyeInWater;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor0;

const vec2 POISSON_DISK[8] = vec2[8](
    vec2(-0.7071,  0.7071),
    vec2(-0.0000, -0.8750),
    vec2( 0.5303,  0.5303),
    vec2(-0.6250, -0.0000),
    vec2( 0.3536, -0.3536),
    vec2(-0.0000,  0.3750),
    vec2(-0.1768, -0.1768),
    vec2( 0.1250,  0.0000)
);

float linearizeDepth(float d) {
    return (2.0 * near * far) / max(far + near - (d * 2.0 - 1.0) * (far - near), 1e-5);
}

vec3 reconstructViewPos(vec2 uv, float depth) {
    vec4 ndc = vec4((uv - cameraJitter(frameCounter, vec2(viewWidth, viewHeight))) * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * ndc;
    return viewPos.xyz / max(viewPos.w, 1e-6);
}

vec3 distortShadowClipPos(vec3 shadowClipPos) {
    float dist = length(shadowClipPos.xy);
    float distortFactor = mix(1.0, dist, 0.85);
    shadowClipPos.xy /= max(distortFactor, 1e-4);
    shadowClipPos.z  *= 0.2;
    return shadowClipPos;
}

vec3 computeShadowVisibility(vec3 playerPos, vec3 viewNormal, float NdotL) {
    vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * viewNormal);
    float distFromCam = length(playerPos);

    float normalBias = mix(0.035, 0.012, clamp(NdotL, 0.0, 1.0)) * (1.0 + distFromCam * 0.004);
    vec3 biasedPlayerPos = playerPos + worldNormal * normalBias;

    vec4 shadowViewPos = shadowModelView * vec4(biasedPlayerPos, 1.0);
    vec4 shadowClipPos = shadowProjection * shadowViewPos;
    shadowClipPos.xyz  = distortShadowClipPos(shadowClipPos.xyz);

    vec3 shadowUV = shadowClipPos.xyz * 0.5 + 0.5;
    if (shadowUV.x <= 0.001 || shadowUV.x >= 0.999 ||
        shadowUV.y <= 0.001 || shadowUV.y >= 0.999 ||
        shadowUV.z <= 0.000 || shadowUV.z >= 1.000) {
        return vec3(1.0);
    }

    float filterRadius = (STYLE_SELECTION == 0 ? 1.85 : 1.15) / float(shadowMapResolution);
    float depthBias = 0.00028;

    vec3 accumulatedShadow = vec3(0.0);
    const int FILTER_TAPS = (SHADOW_FILTER_QUALITY == 0) ? 4 : ((SHADOW_FILTER_QUALITY == 1) ? 6 : 8);
    for (int i = 0; i < FILTER_TAPS; i++) {
        int tap = (SHADOW_FILTER_QUALITY == 0) ? i * 2 : i;
        vec2 sampleUV = shadowUV.xy + POISSON_DISK[tap] * filterRadius;
        float solidDepth = texture(shadowtex1, sampleUV).r;
        float transDepth = texture(shadowtex0, sampleUV).r;

        float solidLit = step(shadowUV.z - depthBias, solidDepth);
        float transLit = step(shadowUV.z - depthBias, transDepth);

        if (solidLit > 0.5 && transLit < 0.5) {
            vec4 casterColor = texture(shadowcolor0, sampleUV);
            vec3 tintedLight = mix(vec3(1.0), casterColor.rgb * 1.15, casterColor.a * 0.75);
            accumulatedShadow += tintedLight;
        } else {
            accumulatedShadow += vec3(solidLit);
        }
    }
    // A narrow handoff fade avoids a long shadowless interval around twilight.
    // Direct light also approaches zero here, hiding the shadow-map source swap.
    float activeElev = dot(vLightViewDir, vUpViewDir);
    float horizonShadowFade = smoothstep(0.0, 0.045, activeElev);
    return mix(vec3(1.0), accumulatedShadow / float(FILTER_TAPS), horizonShadowFade);
}

vec3 applyWuxiaCanvasGrading(vec3 radiance, float matTag, float shadowLuma) {
    const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);
    float luma = dot(radiance, LUMA_WEIGHTS);

    if (STYLE_SELECTION == 0) {
        const mat3 QINGLU_SHANSHUI_MATRIX = mat3(
             1.04,  0.04, -0.04,
            -0.05,  1.06,  0.08,
            -0.04,  0.06,  1.02
        );

        vec3 mineralPigment = max(QINGLU_SHANSHUI_MATRIX * radiance, vec3(0.0));
        float colorRetention = (abs(matTag - 0.90) < 0.05) ? 0.95 : 0.94;
        vec3 colorfulInkWash = mix(vec3(luma), mineralPigment, colorRetention);

        vec3 xuanPaperWarmth = mix(vec3(0.84, 0.90, 0.96), vec3(0.98, 0.95, 0.89), vDaylightFactor);
        vec3 sumiShadowTint = mix(vec3(1.0), vec3(0.94, 0.98, 1.04), vDaylightFactor);

        vec3 shadedWash = colorfulInkWash * xuanPaperWarmth;
        // Tint existing radiance multiplicatively: dark albedo stays dark.
        // An additive tint creates a gray floor that erases wood/obsidian detail.
        return mix(shadedWash * 0.88 * sumiShadowTint, shadedWash, smoothstep(0.0, 0.85, shadowLuma));
    } else {
        const mat3 XIANXIA_RADIANT_MATRIX = mat3(
             1.08, -0.04, -0.04,
            -0.05,  1.10, -0.03,
            -0.04, -0.02,  1.08
        );

        vec3 graded = max(XIANXIA_RADIANT_MATRIX * radiance, vec3(0.0));

        if (abs(matTag - 0.50) < 0.05) {
            vec3 jadeTarget = vec3(radiance.r * 0.70, radiance.g * 1.12, radiance.b * 0.94 + radiance.g * 0.10);
            graded = mix(graded, jadeTarget, 0.48);
        } else if (abs(matTag - 0.75) < 0.05) {
            vec3 blossomPink = vec3(radiance.r * 1.22 + 0.03, radiance.g * 0.82, radiance.b * 1.10 + 0.03);
            graded = mix(graded, blossomPink, 0.55);
        }

        // Vibrant Xianxia cultivation atmosphere (distinctly more colorful & luminous than Guofeng Ink!)
        float colorRetention = (abs(matTag - 0.90) < 0.05) ? 1.16 : 1.12;
        vec3 vibrantXianxia = max(mix(vec3(luma), graded, colorRetention), vec3(0.0));

        vec3 silkWarmth = mix(vec3(0.84, 0.92, 1.02), vec3(1.00, 0.98, 0.94), vDaylightFactor);
        vec3 celestialShadowTint = mix(vec3(1.0), vec3(0.94, 0.98, 1.05), vDaylightFactor);

        vec3 shadedXianxia = vibrantXianxia * silkWarmth;
        return mix(shadedXianxia * 0.90 * celestialShadowTint, shadedXianxia, smoothstep(0.0, 0.85, shadowLuma));
    }
}

vec3 evaluateReflectedTerrainLit(vec2 uvProj, float rawDepth, vec3 directLightColor, vec3 skyAmbientColor, float ambientFloor) {
    vec3 hitAlbedo = pow(texture(colortex0, uvProj).rgb, vec3(2.2));
    vec4 hitNormSample = texture(colortex1, uvProj);
    vec3 hitNormal = normalize(hitNormSample.rgb * 2.0 - 1.0);
    float hitMatTag = hitNormSample.a;

    vec4 hitLm = texture(colortex2, uvProj);
    float hitBlockLight = hitLm.r;
    float hitSkyLight   = hitLm.g;
    float hitAo         = hitLm.b;

    float rawNdotL = dot(hitNormal, vLightViewDir);
    bool isFoliage = (hitMatTag > 0.20 && hitMatTag < 0.80);
    float wrapNdotL = isFoliage ? clamp((rawNdotL + 0.40) / 1.40, 0.0, 1.0) : clamp(rawNdotL, 0.0, 1.0);

    vec3 hitViewPos   = reconstructViewPos(uvProj, rawDepth);
    vec3 hitPlayerPos = (gbufferModelViewInverse * vec4(hitViewPos, 1.0)).xyz;
    vec4 shClip       = shadowProjection * (shadowModelView * vec4(hitPlayerPos, 1.0));
    shClip.xyz        = distortShadowClipPos(shClip.xyz);
    vec3 shUV         = shClip.xyz * 0.5 + 0.5;
    float hitShadow   = 1.0;
    if (shUV.x > 0.0 && shUV.x < 1.0 && shUV.y > 0.0 && shUV.y < 1.0 && shUV.z > 0.0 && shUV.z < 1.0) {
        hitShadow = step(shUV.z - 0.0005, texture(shadowtex1, shUV.xy).r);
    }

    float hitSkyFacing = clamp(dot(hitNormal, vUpViewDir) * 0.5 + 0.5, 0.0, 1.0);
    float hitHemisphere = mix(0.60, 1.0, hitSkyFacing);
    vec3 hitAmbient = skyAmbientColor * mix(ambientFloor, 1.0, hitSkyLight * hitSkyLight) * hitAo * hitHemisphere;
    vec3 hitLantern = vec3(1.35, 0.78, 0.36) * pow(hitBlockLight, 2.2) * 1.45;
    hitShadow = mix(1.0, hitShadow, smoothstep(0.0, 0.045, dot(vLightViewDir, vUpViewDir)));
    vec3 hitTotalLight = hitAmbient + directLightColor * wrapNdotL * hitShadow + hitLantern;
    vec3 hitLit = hitAlbedo * hitTotalLight;
    return applyWuxiaCanvasGrading(hitLit, hitMatTag, hitShadow);
}

vec3 evaluateDynamicCaustics(vec3 worldPos, vec3 lightDirWorld, float time) {
    vec2 causticUV = worldPos.xz - lightDirWorld.xz * (worldPos.y / max(abs(lightDirWorld.y), 0.25));

    mat2 rot1 = mat2( 0.92, -0.39,  0.39,  0.92);
    mat2 rot2 = mat2( 0.64,  0.77, -0.77,  0.64);
    mat2 rot3 = mat2(-0.45,  0.89, -0.89, -0.45);

    vec2 p1 = rot1 * (causticUV * 0.17) + vec2( time * 0.055, -time * 0.038);
    vec2 p2 = rot2 * (causticUV * 0.31) + vec2(-time * 0.062,  time * 0.051);
    vec2 p3 = rot3 * (causticUV * 0.53) + vec2( time * 0.075,  time * 0.044);

    float w1 = sin(p1.x * 6.28318 + cos(p1.y * 4.5)) * cos(p1.y * 6.28318 - sin(p1.x * 4.1));
    float w2 = sin(p2.x * 6.28318 - cos(p2.y * 4.9)) * cos(p2.y * 6.28318 + sin(p2.x * 4.3));
    float w3 = sin(p3.x * 6.28318 + sin(p3.y * 5.2)) * 0.5;

    float netA = clamp(1.0 - abs(w1 + w2), 0.0, 1.0);
    float netB = clamp(1.0 - abs(w2 + w3), 0.0, 1.0);
    float focus = pow(max(netA, netB * 0.85), 3.2);

    if (STYLE_SELECTION == 0) {
        return vec3(0.68, 0.84, 0.80) * smoothstep(0.35, 0.85, focus) * 0.55 * CAUSTICS_STRENGTH;
    } else {
        return vec3(0.38, 0.96, 0.90) * focus * 1.45 * CAUSTICS_STRENGTH;
    }
}

// Above-water Xianxia caustics have a separate, restrained pattern. The original
// evaluator remains unchanged for underwater rendering and the Guofeng style.
vec3 evaluateXianxiaSurfaceCaustics(vec3 worldPos, vec3 lightDirWorld, float time) {
    vec2 uv = worldPos.xz - lightDirWorld.xz *
        (worldPos.y / max(abs(lightDirWorld.y), 0.25));
    vec2 a = mat2(0.92, -0.39, 0.39, 0.92) * uv * 0.17 + vec2(time * 0.055, -time * 0.038);
    vec2 b = mat2(0.64, 0.77, -0.77, 0.64) * uv * 0.31 + vec2(-time * 0.062, time * 0.051);
    float wa = sin(a.x * 6.28318 + cos(a.y * 4.5)) * cos(a.y * 6.28318 - sin(a.x * 4.1));
    float wb = sin(b.x * 6.28318 - cos(b.y * 4.9)) * cos(b.y * 6.28318 + sin(b.x * 4.3));
    // Average two narrow networks instead of selecting the broadest bright one.
    float networkA = exp(-18.0 * abs(wa + wb));
    float networkB = exp(-22.0 * abs(wb + 0.5 * sin(a.y * 5.2)));
    float focus = networkA * 0.65 + networkB * 0.35;
    return vec3(0.40, 0.80, 0.72) * focus * 0.42 * CAUSTICS_STRENGTH;
}

vec3 applySurfaceWaterAbsorption(vec3 transmittedColor, float waterDepth,
                                  float daylight, float skyLight) {
    // This runs on the already-blended G-buffer color. A pale riverbed cannot
    // bypass the depth extinction by leaking through the surface alpha blend.
    vec3 extinction = (STYLE_SELECTION == 0) ? vec3(0.32, 0.24, 0.22) : vec3(0.42, 0.30, 0.20);
    vec3 inkColor = (STYLE_SELECTION == 0) ? vec3(0.012, 0.025, 0.025) : vec3(0.004, 0.014, 0.028);
    vec3 transmittance = exp(-clamp(waterDepth, 0.0, 64.0) * extinction);
    vec3 deepScatter = inkColor * mix(0.20, 1.0, daylight) *
                       mix(0.35, 1.0, skyLight);
    return mix(deepScatter, transmittedColor, transmittance);
}

vec3 computeWaterSurfaceReflection(
    vec3 viewPos,
    vec3 viewNormal,
    float waterLinDepth,
    float waterSkyLight,
    vec3 directLightColor,
    vec3 skyAmbientColor,
    float ambientFloor,
    vec3 shadowVis
) {
    vec3 viewDir = normalize(viewPos);

    // Slightly smooth normal for tracing while retaining wave facets for glints
    vec3 traceNormal = normalize(mix(vUpViewDir, viewNormal, 0.22));
    vec3 reflView    = normalize(reflect(viewDir, traceNormal));
    vec3 fullRefl    = normalize(reflect(viewDir, viewNormal));
    float reflUpDot  = clamp(dot(fullRefl, vUpViewDir), 0.0, 1.0);

    // Reflected world direction for accurate celestial and sky reflection
    vec3 reflWorldDir = normalize(mat3(gbufferModelViewInverse) * fullRefl);

    // 1. Accurate Sky Radiance in Reflection
    vec3 skyRefl;
    if (STYLE_SELECTION == 0) {
        vec3 horizonPaper  = mix(vec3(0.04, 0.06, 0.09), mix(vec3(0.64, 0.70, 0.68), vec3(0.78, 0.48, 0.34), vTwilightFactor), vDaylightFactor);
        vec3 zenithCeladon = mix(vec3(0.015, 0.03, 0.06), vec3(0.28, 0.48, 0.58), vDaylightFactor);
        skyRefl = mix(horizonPaper, zenithCeladon, pow(reflUpDot, 0.65));
    } else {
        vec3 horizonMist = mix(vec3(0.025, 0.05, 0.10), mix(vec3(0.64, 0.78, 0.86), vec3(0.84, 0.52, 0.38), vTwilightFactor), vDaylightFactor);
        vec3 zenithAzure = mix(vec3(0.01, 0.02, 0.05), vec3(0.20, 0.44, 0.68), vDaylightFactor);
        skyRefl = mix(horizonMist, zenithAzure, pow(reflUpDot, 0.65));
    }
    skyRefl *= mix(0.25, 1.0, waterSkyLight * waterSkyLight);

    // 2. Distributed Celestial Light Sheen (No sharp disc cutout on water!)
    float cosSunRefl  = max(dot(reflWorldDir, vSunWorldDir), 0.0);
    float cosMoonRefl = max(dot(reflWorldDir, vMoonWorldDir), 0.0);

    vec3 sunColor  = (STYLE_SELECTION == 0) ? vec3(0.96, 0.78, 0.52) : vec3(0.98, 0.86, 0.64);
    vec3 moonColor = (STYLE_SELECTION == 0) ? vec3(0.88, 0.86, 0.78) : vec3(0.84, 0.90, 0.98);

    float sunWaterSheen  = pow(cosSunRefl, 10.0) * 0.18 * vDaylightFactor * (1.0 - rainStrength * 0.85);
    float moonWaterSheen = pow(cosMoonRefl, 12.0) * 0.14 * vNightFactor * (1.0 - rainStrength * 0.85);
    skyRefl += sunColor * sunWaterSheen + moonColor * moonWaterSheen;

    // 3. Screen-Space Terrain Reflections (SSR) Robust Across ALL View Angles
    #if WATER_REFLECTIONS >= 1
    if (reflView.z < 0.15) {
        const int SSR_STEPS = (WATER_REFLECTIONS >= 2) ? 22 : 12;
        float stepLen = max(waterLinDepth * 0.05, 0.38);
        vec3 marchPos = viewPos + reflView * (stepLen * 0.6) + traceNormal * 0.08;

        for (int i = 0; i < SSR_STEPS; i++) {
            marchPos += reflView * stepLen;
            stepLen  *= 1.10;

            vec4 clipProj = gbufferProjection * vec4(marchPos, 1.0);
            if (clipProj.w <= 0.01) break;
            vec3 ndcProj  = clipProj.xyz / clipProj.w;
            vec2 uvProj   = ndcProj.xy * 0.5 + 0.5 + cameraJitter(frameCounter, vec2(viewWidth, viewHeight));

            // Stop if ray leaves screen
            if (uvProj.x < 0.005 || uvProj.x > 0.995 || uvProj.y < 0.005 || uvProj.y > 0.995) {
                break;
            }

            float sceneRawDepth = texture(depthtex1, uvProj).r;
            if (sceneRawDepth < 0.9999) {
                float marchLinDepth = linearizeDepth(ndcProj.z * 0.5 + 0.5);
                float sceneLinDepth = linearizeDepth(sceneRawDepth);

                // Ignore exact same water pixel while preserving shoreline hits
                if (abs(sceneLinDepth - waterLinDepth) < 0.12) {
                    continue;
                }

                float depthDiff = marchLinDepth - sceneLinDepth;
                float thicknessTolerance = max(stepLen * 1.45, 1.2);

                if (depthDiff > 0.0 && depthDiff < thicknessTolerance) {
                    vec3 hitLitColor = evaluateReflectedTerrainLit(uvProj, sceneRawDepth, directLightColor, skyAmbientColor, ambientFloor);
                    // Smooth border fade right to edge of screen
                    vec2 borderFade  = smoothstep(vec2(0.005), vec2(0.055), uvProj) * smoothstep(vec2(0.005), vec2(0.055), 1.0 - uvProj);
                    float distFade   = clamp(1.0 - max(sceneLinDepth - waterLinDepth, 0.0) / (far * 0.75), 0.0, 1.0);
                    float ssrWeight  = borderFade.x * borderFade.y * distFade * 0.88;
                    skyRefl = mix(skyRefl, hitLitColor * 0.82, ssrWeight);
                    break;
                }
            }
        }
    }
    #endif

    // 4. Distributed wave-facet specular highlights
    // Amplify wave normal slopes across multiple scales so light scatters across a wide patch of wave ripples
    vec3 waveTilt = viewNormal - vUpViewDir;
    vec3 broadWaveNormal = normalize(vUpViewDir + waveTilt * 2.8);
    vec3 midWaveNormal   = normalize(vUpViewDir + waveTilt * 4.5);
    vec3 crestWaveNormal = normalize(vUpViewDir + waveTilt * 6.8);

    vec3 halfVec = normalize(-viewDir + vLightViewDir);
    float NdotH_broad = max(dot(broadWaveNormal, halfVec), 0.0);
    float NdotH_mid   = max(dot(midWaveNormal,   halfVec), 0.0);
    float NdotH_crest = max(dot(crestWaveNormal, halfVec), 0.0);

    // Multi-lobe microfacet wave distribution:
    // Broad lobe distributes soft light across the wave patch; mid & crest lobes illuminate individual wave ripples
    float wavePathBroad = pow(NdotH_broad, 14.0) * 0.26;
    float wavePathMid   = pow(NdotH_mid,   38.0) * 0.52;
    float wavePathCrest = pow(NdotH_crest, 110.0) * 0.88;
    float distributedSpec = wavePathBroad + wavePathMid + wavePathCrest;

    vec3 sunGlitter  = directLightColor * distributedSpec * (STYLE_SELECTION == 0 ? 0.78 : 0.92) * shadowVis * vDaylightFactor;
    float sourceVisibility = smoothstep(0.0, 0.10, dot(vLightViewDir, vUpViewDir));
    vec3 moonGlitter = moonColor * (wavePathBroad * 0.85 + wavePathMid * 0.90 + wavePathCrest * 0.75) * shadowVis * vNightFactor * (1.0 - rainStrength * 0.8) * sourceVisibility;

    return skyRefl + sunGlitter + moonGlitter;
}


// Hash without Sine by David Hoskins (MIT License, https://www.shadertoy.com/view/4djSRW)
float hash12Water(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float smoothNoiseWater(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash12Water(i + vec2(0.0, 0.0));
    float b = hash12Water(i + vec2(1.0, 0.0));
    float c = hash12Water(i + vec2(0.0, 1.0));
    float d = hash12Water(i + vec2(1.0, 1.0));
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y;
}

float waterSilkFbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(0.80, -0.60, 0.60, 0.80);
    for (int i = 0; i < 3; i++) {
        v += a * smoothNoiseWater(p);
        p = rot * p * 2.02 + vec2(13.7, 29.3);
        a *= 0.5;
    }
    return v;
}

// Mirrored tiling joins texture boundaries without hard wrap seams. The UVs
// remain a fixed world-space plane; both scrolling layers use this same mapping.
float samplePlanarFoam(vec2 uv) {
    vec2 tiled = 1.0 - abs(mod(uv, 2.0) - 1.0);
    vec2 border = 0.5 / vec2(textureSize(foamTex, 0));
    return textureLod(foamTex, clamp(tiled, border, 1.0 - border), 0.0).r;
}

/* Shoreline foam is a visible terrain contact effect, not a shallow-water fill.
 * Probe a fixed world-space radius; reconstruct actual scene positions before
 * accepting a hit. Hidden/off-screen banks cannot be recovered from depth alone.
 * No depth-to-bottom or open-water crest term is allowed in this mask.
 */
float computeCompositeShoreFoam(vec3 waterViewPos, vec3 waterWorldPos,
                               float verticalFace, float pixelFootprint) {
    float viewDist = length(waterViewPos);
    if (WATER_FOAM_INTENSITY <= 0.01 || viewDist >= 95.0 || verticalFace > 0.85)
        return 0.0;

    // Intensity changes opacity only, never the distance foam reaches into water.
    const float REACH = 1.20;
    const vec2 DIRS[8] = vec2[8](
        vec2(1.0, 0.0), vec2(0.707107, 0.707107), vec2(0.0, 1.0),
        vec2(-0.707107, 0.707107), vec2(-1.0, 0.0),
        vec2(-0.707107, -0.707107), vec2(0.0, -1.0), vec2(0.707107, -0.707107));
    const float RADII[3] = float[3](0.25, 0.65, 1.20);
    ivec2 screenSize = textureSize(depthtex0, 0);
    float nearestBank = REACH;

    const int DIRECTIONS = (FOAM_QUALITY == 0) ? 4 : 8;
    const int RINGS = (FOAM_QUALITY == 1) ? 2 : 3;
    for (int d = 0; d < DIRECTIONS; ++d) {
        int direction = (FOAM_QUALITY == 0) ? d * 2 : d;
        for (int r = 0; r < RINGS; ++r) {
            float radius = (FOAM_QUALITY == 1) ? (r == 0 ? 0.45 : REACH) : RADII[r];
            vec3 worldOffset = vec3(DIRS[direction].x * radius, 0.18, DIRS[direction].y * radius);
            vec3 probeView = waterViewPos + mat3(gbufferModelView) * worldOffset;
            vec4 clip = gbufferProjection * vec4(probeView, 1.0);
            if (clip.w <= 0.0) continue;
            vec2 uv = clip.xy / clip.w * 0.5 + 0.5 + cameraJitter(frameCounter, vec2(viewWidth, viewHeight));
            if (any(lessThanEqual(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) continue;
            ivec2 pixel = clamp(ivec2(uv * vec2(screenSize)), ivec2(0), screenSize - 1);
            vec4 bankNormalTag = texelFetch(colortex1, pixel, 0);
            // Ordinary solid terrain only: not water, foliage, entities or hands.
            if (abs(bankNormalTag.a) > 0.035) continue;
            float depth = texelFetch(depthtex0, pixel, 0).r;
            if (depth >= 0.999999) continue;
            // Exclude translucent foreground surfaces (glass etc.).
            float opaqueDepth = texelFetch(depthtex1, pixel, 0).r;
            if (abs(linearizeDepth(depth) - linearizeDepth(opaqueDepth)) > 0.06) continue;

            vec2 sampleUV = (vec2(pixel) + 0.5) / vec2(screenSize);
            vec3 bankView = reconstructViewPos(sampleUV, depth);
            // Work in camera-relative world axes to retain precision far from spawn.
            vec3 delta = mat3(gbufferModelViewInverse) * (bankView - waterViewPos);
            if (delta.y < -0.18 || delta.y > 0.85) continue;
            float shoreDist = length(delta.xz);
            if (shoreDist > REACH + 0.12) continue;
            // On a near-vertical solid face, distance to its local plane is more
            // stable than distance to the sampled pixel (especially when grazing).
            vec3 bankN = normalize(mat3(gbufferModelViewInverse) *
                                   (bankNormalTag.xyz * 2.0 - 1.0));
            if (abs(bankN.y) < 0.25) {
                float planeDist = abs(dot(delta.xz, normalize(bankN.xz)));
                shoreDist = max(planeDist, shoreDist - 0.25);
            }
            nearestBank = min(nearestBank, max(shoreDist - 0.035, 0.0));
        }
    }
    if (nearestBank >= REACH) return 0.0;

    // Shore distance is only an opacity envelope: it never generates contours,
    // rings, UVs, bump normals or repeated bright contact bands.
    // A wider quintic fade reaches zero with no slope or curvature discontinuity.
    float shoreT = clamp(nearestBank / REACH, 0.0, 1.0);
    float shoreMask = 1.0 - shoreT * shoreT * shoreT *
                      (shoreT * (shoreT * 6.0 - 15.0) + 10.0);
    float t = frameTimeCounter * WIND_SPEED;
    vec2 uv = waterWorldPos.xz * 0.28;
    vec2 scrollA = vec2(0.013, -0.009) * t;
    vec2 scrollB = vec2(-0.008, 0.011) * t + vec2(0.37, 0.61);
    // Four explicit taps filter the planar decal footprint; do not distort UVs
    // with waves or screen depth, and do not rely on unavailable custom PNG mips.
    float filterWidth = clamp(pixelFootprint * 0.28 * 0.30, 0.0004, 0.045);
    vec2 dx = vec2(filterWidth, 0.0);
    vec2 dy = vec2(0.0, filterWidth);
    float texA = (samplePlanarFoam(uv + scrollA + dx) +
                  samplePlanarFoam(uv + scrollA - dx) +
                  samplePlanarFoam(uv + scrollA + dy) +
                  samplePlanarFoam(uv + scrollA - dy)) * 0.25;
    float texB = (samplePlanarFoam(uv + scrollB + dx) +
                  samplePlanarFoam(uv + scrollB - dx) +
                  samplePlanarFoam(uv + scrollB + dy) +
                  samplePlanarFoam(uv + scrollB - dy)) * 0.25;
    float flatTexture = clamp(texA * 0.78 + texB * 0.46, 0.0, 1.0);
    // Unresolved detail tends toward sparse average coverage, not a solid rim.
    flatTexture = mix(flatTexture, 0.055, smoothstep(0.12, 0.50, pixelFootprint));
    float distanceFade = 1.0 - smoothstep(60.0, 95.0, viewDist);
    float faceGate = 1.0 - smoothstep(0.15, 0.85, verticalFace);
    return clamp(flatTexture * shoreMask * distanceFade * faceGate *
                 WATER_FOAM_INTENSITY, 0.0, 0.82);
}


void main() {
    float depth0 = texture(depthtex0, vTexCoord).r;
    float depth1 = texture(depthtex1, vTexCoord).r;
    vec4 baseSample = texture(colortex0, vTexCoord);

    if (depth0 >= 0.999999) {
        outColor0 = baseSample;
        return;
    }

    vec3 albedo = pow(baseSample.rgb, vec3(2.2));
    vec4 normalSample = texture(colortex1, vTexCoord);
    vec3 viewNormal = normalize(normalSample.rgb * 2.0 - 1.0);
    float matTag = normalSample.a;

    vec4 lmSample = texture(colortex2, vTexCoord);
    float blockLight = lmSample.r;
    float skyLight   = lmSample.g;
    float vertexAo   = lmSample.b;
    float verticalWaterFace = lmSample.a;
    float foamFactor = 0.0;

    vec3 viewPos   = reconstructViewPos(vTexCoord, depth0);
    vec3 playerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 worldPos  = playerPos + cameraPosition;
    float waterLinDepth = linearizeDepth(depth0);
    // Derivatives evaluated before the material branch for stable filtering.
    float waterPixelFootprint = max(length(dFdx(playerPos)), length(dFdy(playerPos)));
    // Evaluate derivatives before the water branch so bottom normals are stable
    // within a terrain face. Depthtex1 supplies the visible opaque bottom.
    vec3 bottomViewPos = reconstructViewPos(vTexCoord, depth1);
    vec3 bottomCross = cross(dFdx(bottomViewPos), dFdy(bottomViewPos));
    vec3 bottomViewNormal = bottomCross / max(length(bottomCross), 1e-6);
    if (dot(bottomViewNormal, -bottomViewPos) < 0.0) bottomViewNormal = -bottomViewNormal;

    float rawNdotL = dot(viewNormal, vLightViewDir);
    bool isFoliageOrBamboo = (matTag > 0.20 && matTag < 0.80);
    bool isWaterSurface    = (abs(matTag - 0.90) < 0.05);
    bool isEntity          = (abs(matTag - 0.10) < 0.05);

    float wrapNdotL = isFoliageOrBamboo
        ? clamp((rawNdotL + 0.40) / 1.40, 0.0, 1.0)
        : (isWaterSurface ? clamp((rawNdotL + 0.65) / 1.65, 0.30, 1.0) : clamp(rawNdotL, 0.0, 1.0));

    vec3 shadowVis = (wrapNdotL > 0.001)
        ? computeShadowVisibility(playerPos, viewNormal, wrapNdotL)
        : vec3(0.0);

    vec3 sunColorDay    = (STYLE_SELECTION == 0) ? vec3(0.86, 0.82, 0.74) : vec3(0.98, 0.92, 0.82);
    vec3 sunColorSunset = (STYLE_SELECTION == 0) ? vec3(0.98, 0.68, 0.48) : vec3(1.22, 0.68, 0.44);
    vec3 moonColorNight = (STYLE_SELECTION == 0) ? vec3(0.12, 0.18, 0.22) : vec3(0.15, 0.24, 0.38);

    vec3 directLightColor = mix(moonColorNight, mix(sunColorDay, sunColorSunset, vTwilightFactor), vDaylightFactor);
    directLightColor *= (1.0 - rainStrength * 0.65);
    // Keep continuous ambient twilight while directional light fades to zero
    // at the handoff. A hard source-direction change then carries no energy.
    float sourceVisibility = smoothstep(0.0, 0.10, dot(vLightViewDir, vUpViewDir));
    directLightColor *= sourceVisibility;

    float ambientFloor = (STYLE_SELECTION == 0)
        ? mix(0.09, 0.16, vDaylightFactor)
        : mix(0.10, 0.18, vDaylightFactor);
    vec3 skyAmbientColor = (STYLE_SELECTION == 0)
        ? mix(vec3(0.04, 0.06, 0.09), vec3(0.30, 0.34, 0.36), vDaylightFactor)
        : mix(vec3(0.04, 0.07, 0.13), vec3(0.36, 0.46, 0.56), vDaylightFactor);

    if (isEyeInWater == 1) {
        vec3 uwTint = (STYLE_SELECTION == 0) ? vec3(0.42, 0.68, 0.65) : vec3(0.22, 0.68, 0.76);
        directLightColor *= uwTint * 0.72;
        skyAmbientColor  *= uwTint * 0.68;
    }

    float skyFacing = clamp(dot(viewNormal, vUpViewDir) * 0.5 + 0.5, 0.0, 1.0);
    float skyHemisphere = mix(0.60, 1.0, skyFacing);
    vec3 ambientLight = skyAmbientColor * mix(ambientFloor, 1.0, skyLight * skyLight) * vertexAo * skyHemisphere;
    float torchFalloff = pow(blockLight, 2.2);
    vec3 lanternLight = vec3(1.35, 0.78, 0.36) * torchFalloff * 1.45;

    vec3 totalLighting = ambientLight + directLightColor * wrapNdotL * shadowVis + lanternLight;
    vec3 litRadiance   = albedo * totalLighting;

    if (isWaterSurface && isEyeInWater == 0) {
        foamFactor = computeCompositeShoreFoam(viewPos, worldPos, verticalWaterFace, waterPixelFootprint);

        vec3 reflectionColor = computeWaterSurfaceReflection(
            viewPos,
            viewNormal,
            waterLinDepth,
            skyLight,
            directLightColor,
            skyAmbientColor,
            ambientFloor,
            shadowVis
        );
        float NdotV = clamp(abs(dot(viewNormal, normalize(-viewPos))), 0.0, 1.0);
        float fresnel = clamp(0.06 + 0.78 * pow(1.0 - NdotV, 3.8), 0.0, 0.82);
        if (verticalWaterFace < 0.5) {
            // Normal-incidence reflection is small; retain the grazing mirror.
            fresnel = clamp(0.02 + 0.82 * pow(1.0 - NdotV, 3.8), 0.0, 0.82);
        }

        fresnel *= (1.0 - foamFactor * 0.45);
        litRadiance *= mix(0.22, 1.0, vDaylightFactor);

        if (verticalWaterFace < 0.5 && depth1 > depth0 && depth1 < 0.999999) {
            vec3 bottomPlayerPos = (gbufferModelViewInverse * vec4(bottomViewPos, 1.0)).xyz;
            vec3 bottomWorldPos = bottomPlayerPos + cameraPosition;
            float waterDepth = max(worldPos.y - bottomWorldPos.y, 0.0);
            vec3 bottomNormalWorld = normalize(mat3(gbufferModelViewInverse) * bottomViewNormal);
            float bottomNdotL = max(dot(bottomViewNormal, vLightViewDir), 0.0);
            vec3 bottomShadow = computeShadowVisibility(bottomPlayerPos, bottomViewNormal, bottomNdotL);
            float bottomHemisphere = mix(0.60, 1.0, clamp(bottomNormalWorld.y * 0.5 + 0.5, 0.0, 1.0));
            vec3 bottomAmbient = skyAmbientColor * mix(ambientFloor, 1.0, skyLight * skyLight) * bottomHemisphere;
            vec3 bottomLighting = bottomAmbient + directLightColor * bottomNdotL * bottomShadow + lanternLight;
            vec3 lightingRatio = clamp(bottomLighting / max(totalLighting, vec3(0.025)), vec3(0.18), vec3(1.20));
            float bottomVisibility = exp(-waterDepth * 0.10) * (1.0 - verticalWaterFace);
            litRadiance *= mix(vec3(1.0), lightingRatio, bottomVisibility * 0.88);
            float scatteredDaylight = vDaylightFactor * (0.55 + 0.45 * dot(bottomShadow, vec3(0.333333)));
            litRadiance = applySurfaceWaterAbsorption(litRadiance, waterDepth, scatteredDaylight, skyLight);

            vec3 lightDirWorld = normalize(mat3(gbufferModelViewInverse) * vLightViewDir);
            float depthFade = exp(-waterDepth * 0.18) * (1.0 - exp(-waterDepth * 3.0));
            float bottomFacing = max(bottomNormalWorld.y, 0.0);
            float sunGate = smoothstep(0.02, 0.30, lightDirWorld.y) * vDaylightFactor * (1.0 - rainStrength * 0.85);
            vec3 caustics = (STYLE_SELECTION == 0)
                ? evaluateDynamicCaustics(bottomWorldPos, lightDirWorld, frameTimeCounter) * 0.35
                : evaluateXianxiaSurfaceCaustics(bottomWorldPos, lightDirWorld, frameTimeCounter);
            litRadiance += albedo * caustics * bottomShadow * bottomFacing * depthFade * sunGate * (1.0 - foamFactor);
        }
        else if (verticalWaterFace < 0.5) {
            // No visible bottom: use the same opaque-depth fallback as the
            // surface pass, rather than leaving distant water unattenuated.
            litRadiance = applySurfaceWaterAbsorption(litRadiance, 32.0, vDaylightFactor, skyLight);
        }
        litRadiance = mix(litRadiance, reflectionColor, fresnel);

        if (foamFactor > 0.005) {
            vec3 topFoamTint = (STYLE_SELECTION == 0) ? vec3(0.92, 0.91, 0.86) : vec3(0.88, 0.95, 0.97);
            vec3 foamAlbedo = topFoamTint; // constant diffuse color; mask changes opacity only
            foamAlbedo = pow(foamAlbedo, vec3(2.2));

            vec3 foamSkyLight = skyAmbientColor * 1.15 * mix(0.35, 1.0, skyLight);
            // A flat diffuse layer: foam does not inherit the rippled water normal.
            float foamNdotL = max(dot(normalize(vUpViewDir), normalize(vLightViewDir)), 0.0);
            vec3 foamSunLight = directLightColor * (0.30 + 0.70 * foamNdotL) * (0.34 + 0.66 * shadowVis);
            vec3 foamRadiance = foamAlbedo * (foamSkyLight + foamSunLight + lanternLight * 0.55);

            // Blend over water surface after pow(2.2) & reflections so foam is always clearly visible
            // while preserving translucent water reflections underneath!
            litRadiance = mix(litRadiance, foamRadiance, clamp(foamFactor * 0.82, 0.0, 0.82));
        }
    }

    bool isShallowSeabed = (depth1 > depth0 + 0.00001) && isWaterSurface;
    if (!isEntity && (isEyeInWater == 1 || (STYLE_SELECTION == 0 && (!isWaterSurface || verticalWaterFace >= 0.5))) &&
        (isEyeInWater == 1 || isShallowSeabed || wetness > 0.05)) {
        vec3 lightDirWorld = normalize(mat3(gbufferModelViewInverse) * vLightViewDir);
        vec3 causticWorldPos = worldPos;
        if (isShallowSeabed) {
            vec3 solidView = reconstructViewPos(vTexCoord, depth1);
            causticWorldPos = (gbufferModelViewInverse * vec4(solidView, 1.0)).xyz + cameraPosition;
        }

        // Only calculate caustics for submerged underwater surfaces or wet surfaces
        vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * viewNormal);
        float upwardSurface = clamp(worldNormal.y * 0.75 + 0.25, 0.0, 1.0);

        float causticMask = 0.0;
        if (isEyeInWater == 1) {
            // When underwater: only surfaces AT OR BELOW the water level receive caustics!
            // Land, cliffs, and banks rising above the water level must NOT have water ripples!
            float submergeFactor = clamp(1.0 - (causticWorldPos.y - (cameraPosition.y + 0.3)) / 0.7, 0.0, 1.0);
            float notWaterSurface = isWaterSurface ? 0.0 : 1.0;
            causticMask = 0.80 * submergeFactor * upwardSurface * notWaterSurface;
        } else if (isShallowSeabed) {
            causticMask = (1.0 - foamFactor) * 0.45 * upwardSurface;
        } else if (wetness > 0.05) {
            causticMask = wetness * skyLight * 0.25 * upwardSurface;
        }

        if (causticMask > 0.001) {
            vec3 caustics = evaluateDynamicCaustics(causticWorldPos, lightDirWorld, frameTimeCounter);
            litRadiance += albedo * caustics * shadowVis * causticMask * mix(0.25, 1.0, vDaylightFactor) * sourceVisibility;
        }
    }

    float shadowLuma = clamp(dot(shadowVis, vec3(0.3333)), 0.0, 1.0);
    // Shadow grading must fade with direct lighting too. Otherwise an unlit
    // east/west face still changes its ambient tint when the source swaps.
    shadowLuma = mix(1.0, shadowLuma, sourceVisibility);
    vec3 gradedRadiance = applyWuxiaCanvasGrading(litRadiance, matTag, shadowLuma);

    outColor0 = vec4(pow(max(gradedRadiance, vec3(0.0)), vec3(1.0 / 2.2)), 1.0);
}
