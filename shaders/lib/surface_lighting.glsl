#ifndef SKY_STYLE
#define SKY_STYLE 0 // [0 1] 0:Wuxia Smooth 1:Minecraft Voxel
#endif
#ifndef WATER_STYLE
#define WATER_STYLE 0 // [0 1 2] 0:Auto (By Shader Style) 1:Wuxia Smooth 2:Minecraft Voxel
#endif
#ifndef ACTIVE_WATER_STYLE
#define ACTIVE_WATER_STYLE ((WATER_STYLE == 0) ? ((SKY_STYLE == 1) ? 2 : 1) : WATER_STYLE)
#endif
#include "/lib/temporal_jitter.glsl"
#include "/lib/water_optics.glsl"
/* =============================================================================
 * composite.fsh — Lighting, colored shadows, SSR, and style grading
 * Modified 2026-10-15: Xianxia above-water bottom shadows and lighter caustics.
 * Build 2: depth absorption in both styles after blending, before reflections.
 * ============================================================================= */

#define CLOUD_QUALITY 1 // [0 1 2 3]
#define CLOUD_TYPE 0 // [0 1 2 3]
#define FLOW_FOAM_STRENGTH 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50]
#define STYLE_SELECTION 1          // [0 1] 0: Guofeng Ink, 1: Xianxia Mist
#define SHADOW_FILTER_QUALITY 1    // [0 1 2] Low, Medium, High
#define DYNAMIC_LIGHTING 2         // [0 1 2 3] Off, Simple, Medium, High
#define CAUSTICS_STRENGTH 1.00     // [0.00 0.25 0.50 0.75 1.00 1.25 1.50]
#define WATER_REFLECTIONS 1        // [0 1 2] 0: Sky Only, 1: Fast SSR, 2: Full SSR
#define WATER_WAVE_HEIGHT 1.00     // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define WATER_TEXTURE 0.00         // [0.00 0.25 0.50 0.75 1.00]
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
flat in vec3 vHandPlayerOrigin;
flat in float vDaylightFactor;
flat in float vTwilightFactor;
flat in float vNightFactor;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex13;

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
uniform vec3 previousCameraPosition;
uniform float frameTime;
uniform vec3 skyColor;
uniform vec3 fogColor;
uniform float frameTimeCounter;
uniform float viewHeight;
uniform float viewWidth;
uniform int frameCounter;
uniform float rainStrength;
uniform float rainFactor;
uniform float thunderStrength;
uniform vec4 lightningBoltPosition;
uniform float wetness;
uniform float near;
uniform float far;
uniform float fogStart;
uniform float fogEnd;
uniform int isEyeInWater;
uniform int moonPhase;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform bool firstPersonCamera;
uniform vec3 relativeEyePosition;

vec3 evaluateHandPlayerOrigin() {
    if (firstPersonCamera) {
        return vec3(0.0, -0.35, 0.0);
    }
    vec3 camForwardWorld = normalize(mat3(gbufferModelViewInverse) * vec3(0.0, 0.0, -1.0));
    vec3 headOffsetPlayer = (dot(relativeEyePosition, camForwardWorld) < 0.0)
        ? -relativeEyePosition
        : relativeEyePosition;
    if (length(headOffsetPlayer) < 0.05) {
        headOffsetPlayer = camForwardWorld * 3.85;
    }
    return headOffsetPlayer + vec3(0.0, -0.35, 0.0);
}
#define BIOME_TINT_STRENGTH 1.00 // [0.00 0.50 0.75 1.00 1.15 1.25 1.50]
uniform float inBambooJungle;
uniform float inMountainBiome;
uniform float inCherryGrove;
uniform float inSnowyBiome;
uniform float inAridBiome;
uniform float inSwampBiome;
uniform float inTheEnd;

// Iris reads format directives from GLSL lines beginning with const.
// Keep each declaration on its own line inside this block comment.
/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16F;
const int colortex2Format = RGBA8;
*/
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor0;

float linearizeDepth(float d) {
    return (2.0 * near * far) / max(far + near - (d * 2.0 - 1.0) * (far - near), 1e-5);
}

#include "/lib/end_portal.glsl"

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


#define YUNMENG_CLOUD_LIGHT_CACHE
#include "/lib/cloud_field.glsl"
#include "/lib/air_fog.glsl"
#include "/lib/shadow_coverage.glsl"

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

    float preDist = length((shadowProjection * shadowViewPos).xy);
    float distortScale = mix(1.0, preDist, 0.85);
    float filterRadius = (STYLE_SELECTION == 0 ? 1.85 : 1.15) / float(shadowMapResolution);
    float depthBias = 0.00028 + 0.00042 * distortScale * (1.0 - clamp(NdotL, 0.0, 1.0));

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
    float horizonShadowFade = smoothstep(0.00, 0.035, activeElev);
    float coverage = isEyeInWater == 1 ? 1.0 : shadowCoverageWeight(shadowUV);
    return mix(vec3(1.0), accumulatedShadow / float(FILTER_TAPS), horizonShadowFade * coverage);
}

vec3 applyYunMengCanvasGrading(vec3 radiance, float matTag, float shadowLuma, float blockLight) {
    const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);
    float luma = dot(radiance, LUMA_WEIGHTS);

    if (STYLE_SELECTION == 0) {
        // Preserve faithful block texture hues and contrast while imparting subtle Guofeng shadow/light warmth
        float nightDesat = mix(0.65, 1.08, vDaylightFactor);
        vec3 colorfulInkWash = mix(vec3(luma), radiance, nightDesat);

        vec3 xuanPaperWarmth = mix(vec3(0.86, 0.91, 0.96), vec3(0.99, 0.97, 0.94), vDaylightFactor);
        vec3 sumiShadowTint  = mix(vec3(1.0), vec3(0.92, 0.96, 1.02), vDaylightFactor);

        vec3 shadedWash = colorfulInkWash * xuanPaperWarmth;
        return mix(shadedWash * 0.84 * sumiShadowTint, shadedWash, smoothstep(0.0, 0.85, shadowLuma));
    } else {
        vec3 graded = radiance;
        if (abs(matTag - 0.50) < 0.05) {
            vec3 jadeTarget = vec3(radiance.r * 0.82, radiance.g * 1.06, radiance.b * 0.95 + radiance.g * 0.05);
            graded = mix(graded, jadeTarget, 0.28);
        } else if (abs(matTag - 0.75) < 0.05) {
            vec3 blossomPink = vec3(radiance.r * 1.12 + 0.01, radiance.g * 0.90, radiance.b * 1.05 + 0.01);
            graded = mix(graded, blossomPink, 0.32);
        }

        const mat3 XIANXIA_WATER_MATRIX = mat3(
             1.08, -0.04, -0.04,
            -0.05,  1.10, -0.03,
            -0.04, -0.02,  1.08
        );
        bool isAboveWaterSurface = (isEyeInWater == 0) && (abs(matTag - 0.90) < 0.05);
        if (isAboveWaterSurface) {
            graded = max(XIANXIA_WATER_MATRIX * radiance, vec3(0.0)) * 0.84;
        }
        float nightDesat = mix(0.56, 1.0, vDaylightFactor);
        float colorRetention = (isAboveWaterSurface ? 1.18 : 1.12) * nightDesat;
        vec3 vibrantXianxia = max(mix(vec3(luma), graded, colorRetention), vec3(0.0));

        vec3 silkWarmth = mix(vec3(0.86, 0.92, 1.00), vec3(1.00, 0.99, 0.96), vDaylightFactor);
        vec3 celestialShadowTint = mix(vec3(1.0), vec3(0.92, 0.96, 1.03), vDaylightFactor);

        vec3 shadedXianxia = mix(vibrantXianxia * silkWarmth * 0.86 * celestialShadowTint, vibrantXianxia * silkWarmth, smoothstep(0.0, 0.85, shadowLuma));

        // Preserve native crimson/red lava hue and dark-crust vs. bright-vein contrast in Xianxia Mist
        // strictly on emissive lava (matTag == 0.04 or level-15 blockLight > 0.95), never on sunlit red terrain blocks!
        if (abs(matTag - 0.04) < 0.01 || (matTag < 0.05 && blockLight > 0.95)) {
            float moltenMask = smoothstep(0.18, 0.48, radiance.r - max(radiance.g * 1.75, radiance.b * 2.50));
            if (moltenMask > 0.001) {
                float rCurved = pow(max(radiance.r - 0.18, 0.02), 2.45) * 0.42;
                float gCurved = pow(max(radiance.g, 0.0), 1.18) * 0.36 + rCurved * 0.0065;
                float bCurved = pow(max(radiance.b, 0.0), 1.12) * 0.45 + rCurved * 0.0060;
                vec3 moltenCrimson = vec3(rCurved, gCurved, bCurved);
                shadedXianxia = mix(shadedXianxia, moltenCrimson, moltenMask);
            }
        }
        return shadedXianxia;
    }
}

vec3 evaluateReflectedTerrainLit(vec2 uvProj, float rawDepth, vec3 directLightColor, vec3 skyAmbientColor, float ambientFloor, vec3 rayOriginPlayer, out vec3 hitPlayerPos) {
    ivec2 c1Size = textureSize(colortex1, 0);
    ivec2 hitTexel = clamp(ivec2(uvProj * vec2(c1Size)), ivec2(0), c1Size - ivec2(1));
    vec3 hitAlbedo = pow(texelFetch(colortex0, hitTexel, 0).rgb, vec3(2.2));
    vec4 hitNormSample = texelFetch(colortex1, hitTexel, 0);
    vec3 hitNormal = normalize(hitNormSample.rgb * 2.0 - 1.0);
    float hitMatTag = hitNormSample.a;
    if (isYunMengEndPortal(hitMatTag)) {
        vec3 portalView = reconstructViewPos(uvProj, rawDepth);
        hitPlayerPos = (gbufferModelViewInverse * vec4(portalView, 1.0)).xyz;
        return pow(renderYunMengEndPortal(hitPlayerPos, hitPlayerPos - rayOriginPlayer), vec3(2.2));
    }
    if (hitMatTag > 0.335 && hitMatTag < 0.475) {
        vec3 eyeView = reconstructViewPos(uvProj, rawDepth);
        hitPlayerPos = (gbufferModelViewInverse * vec4(eyeView, 1.0)).xyz;
        return hitAlbedo * 1.15;
    }

    vec4 hitLm = texture(colortex2, uvProj);
    float hitBlockLight = hitLm.r;
    float hitSkyLight   = hitLm.g;
    float hitAo         = abs(hitMatTag-0.90)<0.05 ? 1.0 : hitLm.b;

    float rawNdotL = dot(hitNormal, vLightViewDir);
    bool isFoliage = (hitMatTag > 0.20 && hitMatTag < 0.80);
    float wrapNdotL = isFoliage ? clamp((rawNdotL + 0.40) / 1.40, 0.0, 1.0) : clamp(rawNdotL, 0.0, 1.0);

    vec3 hitViewPos   = reconstructViewPos(uvProj, rawDepth);
    hitPlayerPos = (gbufferModelViewInverse * vec4(hitViewPos, 1.0)).xyz;
    vec4 shClip       = shadowProjection * (shadowModelView * vec4(hitPlayerPos, 1.0));
    shClip.xyz        = distortShadowClipPos(shClip.xyz);
    vec3 shUV         = shClip.xyz * 0.5 + 0.5;
    float hitShadow   = 1.0;
    if (shUV.x > 0.0 && shUV.x < 1.0 && shUV.y > 0.0 && shUV.y < 1.0 && shUV.z > 0.0 && shUV.z < 1.0) {
        hitShadow = step(shUV.z - 0.0005, texture(shadowtex1, shUV.xy).r);
        hitShadow = mix(1.0, hitShadow, shadowCoverageWeight(shUV));
    }

    float hitSkyFacing = clamp(dot(hitNormal, vUpViewDir) * 0.5 + 0.5, 0.0, 1.0);
    float hitHemisphere = mix(0.60, 1.0, hitSkyFacing);
    vec3 hitAmbient = skyAmbientColor * mix(ambientFloor, 1.0, hitSkyLight * hitSkyLight) * hitAo * hitHemisphere;
    float effHitBlock = hitBlockLight;
    float hitDynTorch = 0.0;
    #if DYNAMIC_LIGHTING > 0
    float reflHeld = float(max(heldBlockLightValue, heldBlockLightValue2)) / 15.0;
    if (reflHeld > 0.001) {
        float hitHandDist = length(evaluateHandPlayerOrigin() - hitPlayerPos);
        float hitLinear = smoothstep(0.0, 1.0, (1.0 - clamp(hitHandDist / max(15.0 * reflHeld, 0.001), 0.0, 1.0)) * reflHeld);
        hitDynTorch = (pow(hitLinear, 1.85) * 0.68 + pow(hitLinear, 3.6) * 0.52) * hitAo;
    }
    #endif
    vec3 hitLantern = vec3(1.35, 0.78, 0.36) * max(pow(effHitBlock, 2.2), hitDynTorch) * 1.45;
    hitShadow = mix(1.0, hitShadow, smoothstep(0.00, 0.035, dot(vLightViewDir, vUpViewDir)));
    vec3 hitTotalLight = hitAmbient + directLightColor * wrapNdotL * hitShadow + hitLantern;
    vec3 hitLit = hitAlbedo * hitTotalLight;
    return applyYunMengCanvasGrading(hitLit, hitMatTag, hitShadow, hitBlockLight);
}

// Tight, fine-scale 3D noise-refracted water caustics (3.2 to 4.6 ripples per block):
// Uses counter-drifting 3D trilinear noise slices (cloudVolume) to refract the lookup coordinate,
// producing tight, organic, non-cartoony aquatic light dapples instead of wide analytic sine-wave ribbons.
float evaluateCausticFieldScalar(vec2 uv, float time) {
    const mat2 rotA = mat2( 0.80, -0.60,  0.60,  0.80);
    const mat2 rotB = mat2( 0.64,  0.77, -0.77,  0.64);

    // Each 64x64 slice of cloudVolume contains ~1.77 low-frequency noise cycles across 1.0 UV unit.
    // Scaling uv by 0.234..0.333 (4.5x tighter than 0.052..0.074) yields ~3.4 tight ripples per 1x1 block.
    vec4 nA = cloudVolume(vec3(uv * 0.234 + vec2( time * 0.042, -time * 0.032), time * 0.028));
    vec4 nB = cloudVolume(vec3((rotA * uv) * 0.333 + vec2(-time * 0.048,  time * 0.038), -time * 0.024 + 0.37));

    // Refract the third 3D slice lookup by the counter-drifting wave normals (nA.rg, nB.gb)
    vec2 refractOffset = (nA.rg - 0.5) * 0.144 + (nB.gb - 0.5) * 0.108;
    vec4 nC = cloudVolume(vec3((rotB * uv) * 0.288 + refractOffset, time * 0.022 + 0.71));

    // Constructive optical convergence where refracted 3D wave normals focus light
    float ridgeA = 1.0 - abs((nC.r - nA.b) * 2.4);
    float ridgeB = 1.0 - abs((nC.g - nB.r) * 2.4);
    float combined = clamp(ridgeA * 0.55 + ridgeB * 0.45, 0.0, 1.0);
    return smoothstep(0.32, 0.86, pow(combined, 1.9));
}

vec3 evaluateDynamicCaustics(vec3 worldPos, vec3 lightDirWorld, float time) {
    // Refract incident light ray into the water column so caustics project naturally onto sunlit floors
    vec3 refractedLight = normalize(vec3(lightDirWorld.x * 0.55, max(abs(lightDirWorld.y), 0.65), lightDirWorld.z * 0.55));
    vec2 baseUV = worldPos.xz - refractedLight.xz * (worldPos.y / refractedLight.y);
    if (ACTIVE_WATER_STYLE == 2) {
        // Snap caustic projection to the 1/16-block pixel grid for Minecraft Voxel water style!
        baseUV = (floor(baseUV * 16.0) + 0.5) / 16.0;
    }

    float focus = evaluateCausticFieldScalar(baseUV, time);
    if (ACTIVE_WATER_STYLE == 2) {
        focus = floor(focus * 6.0 + 0.5) / 6.0;
    }

    if (STYLE_SELECTION == 0) {
        vec3 inkJadeTint = vec3(0.68, 0.88, 0.85);
        return inkJadeTint * focus * 0.44 * CAUSTICS_STRENGTH;
    } else {
        vec3 xianxiaAquaTint = vec3(0.56, 0.92, 0.98);
        return xianxiaAquaTint * focus * 0.52 * CAUSTICS_STRENGTH;
    }
}

vec3 evaluateBiomeWaterMod() {
    float bStr = clamp(BIOME_TINT_STRENGTH, 0.0, 1.5);
    float wSwamp  = clamp(inSwampBiome   * bStr, 0.0, 1.0);
    float wSnowy  = clamp(inSnowyBiome   * bStr, 0.0, 1.0);
    float wBamboo = clamp(inBambooJungle * bStr, 0.0, 1.0);
    float wCherry = clamp(inCherryGrove  * bStr, 0.0, 1.0);
    float wArid   = clamp(inAridBiome    * bStr, 0.0, 1.0);
    float wPale   = evaluatePaleGardenWeight();

    vec3 modCol = vec3(1.0);
    if (STYLE_SELECTION == 0) {
        modCol = mix(modCol, vec3(1.12, 0.84, 0.58), wSwamp  * 0.65);
        modCol = mix(modCol, vec3(0.80, 0.78, 1.12), wSnowy  * 0.55);
        modCol = mix(modCol, vec3(0.88, 1.08, 0.90), wBamboo * 0.45);
        modCol = mix(modCol, vec3(1.18, 1.02, 1.12), wCherry * 0.42);
        modCol = mix(modCol, vec3(0.95, 1.06, 0.98), wArid   * 0.40);
        modCol = mix(modCol, vec3(0.92, 0.78, 0.74), wPale   * 0.75);
    } else {
        modCol = mix(modCol, vec3(1.35, 0.92, 0.52), wSwamp  * 0.65);
        modCol = mix(modCol, vec3(0.85, 0.72, 1.18), wSnowy  * 0.55);
        modCol = mix(modCol, vec3(0.92, 1.12, 0.88), wBamboo * 0.45);
        modCol = mix(modCol, vec3(1.25, 1.08, 1.18), wCherry * 0.45);
        modCol = mix(modCol, vec3(1.05, 1.14, 1.06), wArid   * 0.42);
        modCol = mix(modCol, vec3(1.12, 0.76, 0.68), wPale   * 0.75);
    }
    return modCol;
}

vec3 applySurfaceWaterAbsorption(vec3 transmittedColor, float waterDepth,
                                  float daylight, float skyLight) {
    // Since gbuffers_water.fsh already computes the per-block biome water color and depth ramp in colortex0
    // (transmittedColor), preserve both the per-pixel hue AND brightness difference across in-view biome boundaries!
    vec3 biomeMod = evaluateBiomeWaterMod();
    vec3 extinction = (STYLE_SELECTION == 0) ? vec3(0.28, 0.22, 0.20) : vec3(0.36, 0.26, 0.18);
    vec3 baseInk = ((STYLE_SELECTION == 0) ? vec3(0.012, 0.025, 0.025) : vec3(0.004, 0.014, 0.028)) * biomeMod;
    vec3 deepScatter = baseInk * mix(0.28, 1.0, daylight) * mix(0.40, 1.0, skyLight);
    // Anchor deepScatter to transmittedColor so side-by-side biome boundaries (e.g. bright teal vs dark frozen cobalt)
    // stay 100% distinct even in deep water and at dusk/night!
    deepScatter = mix(deepScatter, transmittedColor * 0.58, 0.68 * clamp(BIOME_TINT_STRENGTH, 0.0, 1.25));

    vec3 transmittance = exp(-clamp(waterDepth, 0.0, 64.0) * extinction);
    transmittance = max(transmittance, vec3(0.46, 0.50, 0.54));
    float effWaterTexAbs = (WATER_TEXTURE > 0.0) ? WATER_TEXTURE : ((ACTIVE_WATER_STYLE == 2) ? 0.62 : 0.0);
    if (effWaterTexAbs > 0.0) {
        transmittance = mix(transmittance, max(transmittance, vec3(0.64, 0.68, 0.72)), effWaterTexAbs);
    }
    return mix(deepScatter, transmittedColor, transmittance);
}

// Shared macro sky-opening estimator so scene direct highlights, shadows, water glints,
// and volumetric light shafts respond coherently to cloud openings during rain vs dense overcast.
void evaluateSceneWeatherAndOpening(vec3 origin, out float wetnessFactor, out float stormFactor, out float lightningFlash, out float skyLightOpening) {
    float rawRain = clamp(mix(rainStrength, max(rainStrength, rainFactor), 0.60), 0.0, 1.0);
    wetnessFactor = smoothstep(0.0, 1.0, rawRain);
    stormFactor = smoothstep(0.0, 1.0, thunderStrength) * wetnessFactor;
    lightningFlash = clamp(lightningBoltPosition.w, 0.0, 1.0) * wetnessFactor;
    vec3 lightDir = normalize(mat3(gbufferModelViewInverse) * vLightViewDir);
    int mode = (CLOUD_TYPE == 0) ? (STYLE_SELECTION == 0 ? 1 : 2) : CLOUD_TYPE;
    skyLightOpening = cloudLightTransmission(origin, lightDir, frameTimeCounter, mode, wetnessFactor, stormFactor);
}

#include "/lib/water_environment.glsl"
#include "/lib/water_waves.glsl"

// Full-resolution, derivative-antialiased reflected night starfield for water & ice:
// Evaluates crisp pinpoint stars at native screen resolution (never half-res upsampled smudges),
// energy-conserves over rippled wave normals via fwidth(), and respects clouds, moon, weather & SSR occlusion.
float starReflHash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Procedural raindrop impact ripples on wet upward ground & water surfaces:
// - Wuxia Smooth (SKY_STYLE == 0): concentric circular silk-mist rings
// - Minecraft Voxel (SKY_STYLE == 1): crisp 1px-snapped expanding square rings
float evaluateRainRippleLayer(vec2 worldXZ, float t, float cellScale, float seedOff) {
    vec2 p = (SKY_STYLE == 1) ? (floor(worldXZ * 16.0) / 16.0) : worldXZ;
    vec2 g = p * cellScale;
    vec2 id = floor(g);
    vec2 f  = fract(g);

    float h0 = starReflHash12(id + vec2(seedOff, seedOff * 1.7));
    if (h0 < 0.42) return 0.0;
    float h1 = starReflHash12(id + vec2(19.3 + seedOff, 47.1));
    float h2 = starReflHash12(id + vec2(61.7, 23.9 + seedOff));

    float life = fract(t * (0.72 + 0.45 * h0) + h1);
    vec2 center = vec2(0.24 + 0.52 * h1, 0.24 + 0.52 * h2);
    vec2 d = f - center;

    float radius = life * 0.46;
    float fade   = smoothstep(0.0, 0.10, life) * pow(1.0 - life, 1.55);

    if (SKY_STYLE == 1) {
        float distSq = max(abs(d.x), abs(d.y));
        float ring = 1.0 - smoothstep(0.020, 0.055, abs(distSq - radius));
        float bead = (1.0 - smoothstep(0.02, 0.06, distSq)) * smoothstep(0.22, 0.0, life);
        return (ring * 0.85 + bead * 0.65) * fade;
    } else {
        float distC = length(d);
        float mainRing  = exp(-pow((distC - radius) / 0.032, 2.0));
        float innerRing = exp(-pow((distC - max(radius - 0.10, 0.0)) / 0.026, 2.0)) * 0.55 * smoothstep(0.22, 0.45, life);
        float mistPuff  = exp(-pow(distC / 0.055, 2.0)) * smoothstep(0.24, 0.0, life) * 0.50;
        return (mainRing + innerRing + mistPuff) * fade;
    }
}

float evaluateRainImpactRipples(vec2 worldXZ, float time) {
    float r1 = evaluateRainRippleLayer(worldXZ, time, 0.85, 11.3);
    float r2 = evaluateRainRippleLayer(worldXZ + vec2(0.47, 0.31), time * 1.12, 1.15, 37.9);
    return clamp(r1 + r2 * 0.80, 0.0, 1.0);
}

vec3 evaluateFullResReflectedStars(vec3 reflWorld, vec3 waterWorldPos, float wetnessFactor, float stormFactor) {
    if (inTheEnd > 0.5 || reflWorld.y <= 0.05) return vec3(0.0);
    float starTwilightVis = (1.0 - smoothstep(-0.09, 0.01, vSunWorldDir.y)) * (1.0 - evaluatePaleGardenWeight() * 0.90);
    float clearNight = (1.0 - wetnessFactor * 0.96) * (1.0 - stormFactor * 0.96);
    float horizonGate = smoothstep(0.06, 0.28, reflWorld.y);
    float moonClear = 1.0 - smoothstep(0.990, 0.997, dot(reflWorld, vMoonWorldDir));
    float vis = starTwilightVis * clearNight * horizonGate * moonClear;
    if (vis <= 0.002) return vec3(0.0);

    vec3 dir = normalize(reflWorld);
    vec3 absD = abs(dir);
    vec2 cubeUV;
    float faceId;
    if (absD.y >= absD.x && absD.y >= absD.z) {
        cubeUV = dir.xz / max(absD.y, 1e-4);
        faceId = (dir.y >= 0.0) ? 1.0 : 2.0;
    } else if (absD.x >= absD.z) {
        cubeUV = dir.zy / max(absD.x, 1e-4);
        faceId = (dir.x >= 0.0) ? 3.0 : 4.0;
    } else {
        cubeUV = dir.xy / max(absD.z, 1e-4);
        faceId = (dir.z >= 0.0) ? 5.0 : 6.0;
    }

    float gridScale = (SKY_STYLE == 1) ? 54.0 : 64.0;
    vec2 gPos = cubeUV * gridScale;
    vec2 cell = floor(gPos);
    vec2 fUV  = fract(gPos);
    vec2 fw   = max(fwidth(gPos), vec2(0.04));

    float h0 = starReflHash12(cell + vec2(faceId * 17.3, faceId * 31.7));
    if (h0 < 0.942) return vec3(0.0);

    float h1 = starReflHash12(cell + vec2(43.1, 19.7) + faceId * 11.1);
    float h2 = starReflHash12(cell + vec2(71.9, 53.3) + faceId * 23.9);
    vec2 starCenter = vec2(0.22 + 0.56 * h1, 0.22 + 0.56 * h2);
    vec2 delta = fUV - starCenter;

    float footprint = max(fw.x, fw.y);
    float radius = clamp(footprint * 0.62, 0.045, 0.16);
    float d = (SKY_STYLE == 1)
        ? max(abs(delta.x), abs(delta.y))
        : length(delta);
    float pinpoint = 1.0 - smoothstep(radius * 0.45, radius * 1.15, d);
    if (pinpoint <= 0.001) return vec3(0.0);

    // Energy-conserving attenuation when steep water waves stretch the footprint
    float energyKeep = clamp(0.075 / max(footprint, 0.075), 0.18, 1.0);

    // Cloud occlusion along the reflected ray so reflected clouds naturally block stars
    int cloudMode = (CLOUD_TYPE == 0) ? (STYLE_SELECTION == 0 ? 1 : 2) : CLOUD_TYPE;
    float cloudClear = (cloudMode == 3) ? 1.0
        : cloudLightTransmission(waterWorldPos, dir, frameTimeCounter, cloudMode, wetnessFactor, stormFactor);

    float starTier = smoothstep(0.942, 0.998, h0);
    float twinkle  = 0.76 + 0.24 * sin(frameTimeCounter * (0.9 + 1.5 * h2) + h1 * 6.2831853);

    vec3 warmStar = (STYLE_SELECTION == 0) ? vec3(1.00, 0.88, 0.66) : vec3(0.95, 0.92, 0.82);
    vec3 coolStar = (STYLE_SELECTION == 0) ? vec3(0.66, 0.86, 0.82) : vec3(0.64, 0.84, 1.05);
    vec3 starCol  = mix(coolStar, warmStar, h1);

    return starCol * (pinpoint * energyKeep * (0.22 + 0.72 * starTier) * twinkle * cloudClear * vis);
}

vec3 computeWaterSurfaceReflection(
    vec3 viewPos,
    vec3 viewNormal,
    float waterLinDepth,
    float waterSkyLight,
    vec3 directLightColor,
    vec3 skyAmbientColor,
    float ambientFloor,
    vec3 shadowVis,
    vec4 sharedWeather,
    bool slopedTop,
    bool allowCelestialShimmer
) {
    vec3 viewDir = normalize(viewPos);
    vec3 waterPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 waterWorldPos  = waterPlayerPos + cameraPosition;

    // Smooth normal for SSR & sky tracing across both level and gently-sloped flowing water
    // so stepped cave pools and voxel wave facets never slice the reflection ray direction.
    float horizontalSurface = slopedTop ? 0.0 : smoothstep(0.70, 0.95, abs(dot(viewNormal, vUpViewDir)));
    float upwardWater       = smoothstep(0.55, 0.92, abs(dot(viewNormal, vUpViewDir)));
    vec3 traceNormal = normalize(mix(viewNormal,
        normalize(mix(vUpViewDir, viewNormal, 0.30)), upwardWater));
    vec3 reflView    = normalize(reflect(viewDir, traceNormal));
    vec3 fullRefl    = normalize(reflect(viewDir, viewNormal));
    // Anchor sky reflection lookups on steep/vertical water faces to the upper sky hemisphere
    // so the lower end of flowing water nearing the ground never reflects warm/gray sub-horizon haze.
    float sheetSkyFloor = mix(0.28, 0.0, upwardWater);
    float reflUpDot  = clamp(max(dot(fullRefl, vUpViewDir), sheetSkyFloor), 0.0, 1.0);
    float macroUpDot = clamp(max(dot(reflView, vUpViewDir), sheetSkyFloor), 0.0, 1.0);

    // 1. Accurate Sky Radiance in Reflection (Coordinated with Rain, Storm & Lightning)
    float wetnessFactor   = sharedWeather.x;
    float stormFactor     = sharedWeather.y;
    float lightningFlash  = sharedWeather.z;
    float skyLightOpening = sharedWeather.w;

    vec3 skyRefl;
    vec3 macroSkyRefl;
    if (STYLE_SELECTION == 0) {
        vec3 horizonPaper  = mix(vec3(0.04, 0.06, 0.09), mix(vec3(0.64, 0.70, 0.68), vec3(0.78, 0.48, 0.34), vTwilightFactor), vDaylightFactor);
        vec3 zenithCeladon = mix(vec3(0.015, 0.03, 0.06), vec3(0.28, 0.48, 0.58), vDaylightFactor);
        vec3 clearRefl     = mix(horizonPaper, zenithCeladon, pow(reflUpDot, 0.65));
        vec3 clearMacro    = mix(horizonPaper, zenithCeladon, pow(macroUpDot, 0.65));
        vec3 rainRefl      = mix(vec3(0.042, 0.068, 0.092), vec3(0.34, 0.41, 0.42), vDaylightFactor);
        vec3 stormRefl     = mix(vec3(0.030, 0.050, 0.072), vec3(0.17, 0.21, 0.23), vDaylightFactor);
        skyRefl      = mix(clearRefl,  mix(rainRefl, stormRefl, stormFactor), wetnessFactor * 0.85);
        macroSkyRefl = mix(clearMacro, mix(rainRefl, stormRefl, stormFactor), wetnessFactor * 0.85);
    } else {
        vec3 horizonMist = mix(vec3(0.025, 0.05, 0.10), mix(vec3(0.64, 0.78, 0.86), vec3(0.84, 0.52, 0.38), vTwilightFactor), vDaylightFactor);
        vec3 zenithAzure = mix(vec3(0.01, 0.02, 0.05), vec3(0.20, 0.44, 0.68), vDaylightFactor);
        vec3 clearRefl   = mix(horizonMist, zenithAzure, pow(reflUpDot, 0.65));
        vec3 clearMacro  = mix(horizonMist, zenithAzure, pow(macroUpDot, 0.65));
        vec3 rainRefl    = mix(vec3(0.040, 0.068, 0.120), vec3(0.32, 0.42, 0.54), vDaylightFactor);
        vec3 stormRefl   = mix(vec3(0.026, 0.048, 0.092), vec3(0.16, 0.21, 0.28), vDaylightFactor);
        skyRefl      = mix(clearRefl,  mix(rainRefl, stormRefl, stormFactor), wetnessFactor * 0.88);
        macroSkyRefl = mix(clearMacro, mix(rainRefl, stormRefl, stormFactor), wetnessFactor * 0.88);
    }
    vec3 flashReflTint = (STYLE_SELECTION == 0) ? vec3(0.55, 0.66, 0.74) : vec3(0.52, 0.68, 0.94);
    skyRefl += flashReflTint * lightningFlash * 0.42;
    macroSkyRefl += flashReflTint * lightningFlash * 0.42;

    // Attenuate sky & cloud environment reflection smoothly when water is covered by overhangs or cave roofs
    // so enclosed daytime cave pools never leak bright cyan sky slices where SSR misses.
    float skyOpenAccess = smoothstep(0.18, 0.92, waterSkyLight) * pow(clamp(waterSkyLight, 0.0, 1.0), 2.4);
    vec4 environment = reconstructSurfaceWaterEnvironment(vTexCoord, viewPos, traceNormal, slopedTop);
    vec3 facetSkyDelta = (skyRefl - macroSkyRefl) * (ACTIVE_WATER_STYLE == 2 ? 0.55 : 1.05) * skyOpenAccess;
    skyRefl = mix(skyRefl, max(environment.rgb + facetSkyDelta, vec3(0.0)), environment.a * skyOpenAccess);
    skyRefl = pow(max(skyRefl, vec3(0.0)), vec3(2.2));
    vec3 coveredCaveRefl = skyAmbientColor * ambientFloor * mix(0.28, 0.55, waterSkyLight);
    skyRefl = mix(coveredCaveRefl, skyRefl, skyOpenAccess);

    // 2. Celestial Setup & Screen-Space Occlusion Check
    vec3 sunColor  = (STYLE_SELECTION == 0)
        ? mix(vec3(1.05, 0.86, 0.58), vec3(1.18, 0.62, 0.34), vTwilightFactor)
        : mix(vec3(1.10, 0.94, 0.68), vec3(1.24, 0.66, 0.38), vTwilightFactor);
    vec3 moonColor = (STYLE_SELECTION == 0) ? vec3(0.82, 0.90, 0.88) : vec3(0.78, 0.90, 1.05);

    int mPhase = moonPhase & 7;
    float moonPhaseScale = (mPhase == 0) ? 1.00
        : ((mPhase == 1 || mPhase == 7) ? 0.86
        : ((mPhase == 2 || mPhase == 6) ? 0.72
        : ((mPhase == 3 || mPhase == 5) ? 0.58 : 0.42)));

    float sunActive  = step(0.0, dot(vSunViewDir,  vLightViewDir)) * vDaylightFactor;
    float moonActive = step(0.0, dot(vMoonViewDir, vLightViewDir)) * vNightFactor * moonPhaseScale;
    float sourceVisibility = smoothstep(0.04, 0.20, dot(vLightViewDir, vUpViewDir));

    float lightScreenVis = 1.0;
    vec4 lightClip = gbufferProjection * vec4(vLightViewDir, 0.0);
    if (lightClip.w > 0.0) {
        vec2 lightUV = lightClip.xy / lightClip.w * 0.5 + 0.5 + cameraJitter(frameCounter, vec2(viewWidth, viewHeight));
        if (all(greaterThan(lightUV, vec2(0.005))) && all(lessThan(lightUV, vec2(0.995)))) {
            float centerSky = step(0.99999, texture(depthtex1, lightUV).r);
            float lowerSky  = step(0.99999, texture(depthtex1, clamp(lightUV + vec2(0.0, -0.025), vec2(0.002), vec2(0.998))).r);
            lightScreenVis  = 0.5 * (centerSky + lowerSky);
        }
    }

    // 3. Screen-Space Terrain Reflections (SSR) with Sub-Step Jitter & Secant Overhang Refinement
    // Prevents discrete step-band slicing when reflecting overhanging cave/cliff blocks during the day.
    float ssrOcclusion = 0.0;
    #if WATER_REFLECTIONS >= 1
    if (reflView.z < 0.15) {
        const int SSR_STEPS = (WATER_REFLECTIONS >= 2) ? 22 : 14;
        float stepLen = max(waterLinDepth * 0.045, 0.32);
        float ssrDither = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
        vec3 marchPos = viewPos + reflView * (stepLen * (0.35 + 0.65 * ssrDither)) + traceNormal * 0.06;
        vec3 prevMarchPos = viewPos + traceNormal * 0.06;
        float prevDepthDiff = -0.15;

        for (int i = 0; i < SSR_STEPS; i++) {
            if (i > 0) {
                prevMarchPos = marchPos;
                marchPos += reflView * stepLen;
                stepLen  *= 1.10;
            }

            vec4 clipProj = gbufferProjection * vec4(marchPos, 1.0);
            if (clipProj.w <= 0.01) break;
            vec3 ndcProj  = clipProj.xyz / clipProj.w;
            vec2 uvProj   = ndcProj.xy * 0.5 + 0.5 + cameraJitter(frameCounter, vec2(viewWidth, viewHeight));

            if (uvProj.x < 0.005 || uvProj.x > 0.995 || uvProj.y < 0.005 || uvProj.y > 0.995) {
                break;
            }

            float sceneRawDepth = texture(depthtex1, uvProj).r;
            if (sceneRawDepth < 0.9999) {
                float marchLinDepth = linearizeDepth(ndcProj.z * 0.5 + 0.5);
                float sceneLinDepth = linearizeDepth(sceneRawDepth);

                if (abs(sceneLinDepth - waterLinDepth) < 0.10) {
                    continue;
                }

                ivec2 c1S = textureSize(colortex1, 0); float hitTag = texelFetch(colortex1, clamp(ivec2(uvProj * vec2(c1S)), ivec2(0), c1S - ivec2(1)), 0).a;
                // If uvProj is still on the water surface or a held item,depthtex1 is the riverbed behind water;
                // do not treat the riverbed as an above-water reflection hit.
                if (abs(hitTag - 0.90) < 0.05 || abs(hitTag - 0.12) < 0.007) {
                    prevDepthDiff = -0.10;
                    continue;
                }

                float depthDiff = marchLinDepth - sceneLinDepth;
                // Reject foreground occluders that are closer to the camera than the water start point
                // when the ray was already behind them, preventing false foreground slices.
                if (sceneLinDepth < waterLinDepth - 0.35 && prevDepthDiff > 0.0) {
                    prevDepthDiff = depthDiff;
                    continue;
                }

                // When stepping from in front of geometry (prevDepthDiff <= 0.0) to behind an overhang/wall
                // (depthDiff > 0.0), refine the intersection position linearly so discrete step sizes never
                // jump through cave ceilings or slice overhanging blocks into bands.
                bool crossedSurface = (prevDepthDiff <= 0.0 && depthDiff > 0.0 && sceneLinDepth >= waterLinDepth - 0.45);
                float thicknessTolerance = crossedSurface ? max(stepLen * 3.4, 3.8) : max(stepLen * 1.85, 1.65);

                if (depthDiff > 0.0 && depthDiff < thicknessTolerance) {
                    vec2 hitUV = uvProj;
                    float hitRawDepth = sceneRawDepth;
                    if (crossedSurface && i > 0) {
                        float tHit = clamp(-prevDepthDiff / max(depthDiff - prevDepthDiff, 1e-4), 0.15, 0.85);
                        vec3 refinedPos = mix(prevMarchPos, marchPos, tHit);
                        vec4 refClip = gbufferProjection * vec4(refinedPos, 1.0);
                        if (refClip.w > 0.01) {
                            vec2 refUV = (refClip.xy / refClip.w) * 0.5 + 0.5 + cameraJitter(frameCounter, vec2(viewWidth, viewHeight));
                            if (all(greaterThan(refUV, vec2(0.005))) && all(lessThan(refUV, vec2(0.995)))) {
                                float refRaw = texture(depthtex1, refUV).r;
                                float refTag = texelFetch(colortex1, clamp(ivec2(refUV * vec2(c1S)), ivec2(0), c1S - ivec2(1)), 0).a;
                                if (refRaw < 0.9999 && abs(refTag - 0.90) >= 0.05 && abs(refTag - 0.12) >= 0.007) {
                                    hitUV = refUV;
                                    hitRawDepth = refRaw;
                                    sceneLinDepth = linearizeDepth(refRaw);
                                }
                            }
                        }
                    }

                    vec3 hitPlayerPos;
                    vec3 hitLitColor = evaluateReflectedTerrainLit(hitUV, hitRawDepth, directLightColor, skyAmbientColor, ambientFloor, waterPlayerPos, hitPlayerPos);
                    vec2 borderFade  = smoothstep(vec2(0.005), vec2(0.055), hitUV) * smoothstep(vec2(0.005), vec2(0.055), 1.0 - hitUV);
                    float distFade   = clamp(1.0 - max(sceneLinDepth - waterLinDepth, 0.0) / (far * 0.75), 0.0, 1.0);
                    float facingConfidence = 1.0 - smoothstep(-0.05, 0.15, reflView.z);
                    float ssrWeight = borderFade.x * borderFade.y * distFade * 0.88 * facingConfidence;
                    float reflectedFog = airPathFog(cameraPosition + waterPlayerPos,
                        cameraPosition + hitPlayerPos, length(hitPlayerPos - waterPlayerPos), wetnessFactor, stormFactor);
                    ssrWeight *= (1.0 - airBorderFog(hitPlayerPos, wetnessFactor, stormFactor)) * (1.0 - reflectedFog);
                    skyRefl = mix(skyRefl, hitLitColor * 0.82, ssrWeight);
                    ssrOcclusion = clamp(ssrWeight / 0.88, 0.0, 1.0);
                    break;
                }
                prevDepthDiff = depthDiff;
            } else {
                prevDepthDiff = -1.0;
            }
        }
    }
    #endif

    // Full-resolution pinpoint night star reflections (occluded by SSR terrain, clouds, caves, and horizon mist)
    if (vNightFactor > 0.01 && ssrOcclusion < 0.98 && skyOpenAccess > 0.02) {
        vec3 reflWorldStar = normalize(mat3(gbufferModelViewInverse) * fullRefl);
        vec3 reflStars = evaluateFullResReflectedStars(reflWorldStar, waterWorldPos, wetnessFactor, stormFactor);
        skyRefl += reflStars * (1.0 - ssrOcclusion) * skyOpenAccess * upwardWater;
    }

    if (!allowCelestialShimmer) {
        return skyRefl;
    }

    // 4. Physically-Grounded 3D Anisotropic GGX Water Specular Shimmer:
    // Uses true 3D view (V_world) and light (L_world) vectors with un-stretched 3D trochoidal wave normals
    // and physical Fresnel downward-view attenuation so:
    //  - No barcode/comb coordinate squashing ever occurs on the waves.
    //  - Steep downward views (shallow foreground water or 3rd-person overhead camera in the ocean) stay
    //    clean and transparent around/behind the player instead of shooting a stripe both ways.
    //  - Looking toward the sun horizon produces a natural, shimmering 3D wave-crest sun path in both styles and themes.
    float NdotV_flat = clamp(abs(dot(vUpViewDir, -viewDir)), 0.04, 1.0);
    vec3 glintOcclusion = shadowVis * (1.0 - ssrOcclusion) * lightScreenVis * skyLightOpening * sourceVisibility * skyOpenAccess;

    vec3 activeLightWorld = (sunActive >= moonActive) ? vSunWorldDir : vMoonWorldDir;
    vec2 sunHorizDir  = normalize(activeLightWorld.xz + vec2(1e-5));
    vec2 sunSideDir   = vec2(-sunHorizDir.y, sunHorizDir.x);

    float rawWTime = frameTimeCounter * WIND_SPEED;
    float wTime    = (ACTIVE_WATER_STYLE == 2) ? (rawWTime * 0.75) : rawWTime;
    vec2 dPdx = dFdx(waterWorldPos.xz);
    vec2 dPdy = dFdy(waterWorldPos.xz);
    float trueFp = max(length(dPdx), length(dPdy));

    vec3 bloomTintSun = (STYLE_SELECTION == 0)
        ? mix(vec3(0.84, 0.94, 0.86), sunColor, 0.45)
        : mix(vec3(0.64, 0.94, 1.02), sunColor, 0.35);
    vec3 bloomTintMoon = (STYLE_SELECTION == 0) ? vec3(0.75, 0.92, 0.88) : vec3(0.68, 0.90, 1.05);
    vec3 activeBloomTint = (sunActive >= moonActive) ? bloomTintSun : bloomTintMoon;
    vec3 activeCoreTint  = mix(vec3(1.00, 0.99, 0.92), (sunActive >= moonActive) ? sunColor : moonColor, 0.20);
    float celestialWeight = sunActive + moonActive * 0.78;

    // True 3D unit vector from water surface to camera in world space (V_world.y > 0 when above water)
    vec3 V_world = -normalize(waterPlayerPos);
    vec3 L_world = normalize(activeLightWorld);

    float vHorizLen = max(length(V_world.xz), 1e-4);
    float forwardSunAlign = clamp(dot(-V_world.xz / vHorizLen, sunHorizDir), 0.0, 1.0);

    // Physical grazing & steep-view gate:
    // Sun shimmer occurs at shallow-to-mid grazing angles toward the sun (V_world.y < 0.48) where Fresnel rises,
    // and naturally fades out when looking steeply down into transparent water (V_world.y > 0.36..0.54)
    // so 3rd-person overhead views in the ocean never draw a shimmer stripe through or behind the player!
    float grazingShimmerGate = (1.0 - smoothstep(0.36, 0.54, V_world.y))
                             * smoothstep(0.05, 0.35, forwardSunAlign)
                             * horizontalSurface;

    // Grazing wave-crest masking (Ross 2005 / Bruneton 2010):
    // At shallow horizon viewing angles, wave crests obscure wave troughs, tilting the effective visible normal
    // toward the viewer so a high sun still forms a continuous path from the horizon without requiring 35-deg waves.
    float grazingHorizon = (1.0 - smoothstep(0.04, 0.44, V_world.y)) * pow(forwardSunAlign, 1.5);
    float effLy = mix(L_world.y, max(V_world.y * 1.18, 0.10), grazingHorizon * 0.68);
    float effLHoriz = sqrt(max(1.0 - effLy * effLy, 0.01));
    vec3 effectiveL_world = vec3(sunHorizDir.x * effLHoriz, effLy, sunHorizDir.y * effLHoriz);

    // True 3D Half-Vector H_world
    vec3 H_world = normalize(V_world + effectiveL_world);

    // Evaluate natural, UN-STRETCHED 3D wave normals (combining gbuffers_water's viewNormal with fine detail facets)
    vec3 surfWorldNorm = normalize(mat3(gbufferModelViewInverse) * viewNormal);
    vec2 surfGradXZ    = -surfWorldNorm.xz / max(surfWorldNorm.y, 0.15);
    vec3 detWave       = waterShimmerDetailWaves(waterWorldPos.xz, wTime, min(trueFp * 0.50, 0.90));

    float waveBoost = ((ACTIVE_WATER_STYLE == 2) ? 2.6 : 3.2) * WATER_WAVE_HEIGHT;
    vec2 combGradXZ = (surfGradXZ + detWave.xy * 0.65) * waveBoost;
    vec3 shimmerNormW = normalize(vec3(-combGradXZ.x, 1.0, -combGradXZ.y));

    // Project 3D half-vector & wave normal difference onto horizontal sun-aligned tangent axes for Anisotropic GGX
    float NoH = clamp(dot(shimmerNormW, H_world), 0.0, 1.0);
    vec3 dH   = H_world - shimmerNormW * NoH;
    float hAcross = dot(dH.xz, sunSideDir);
    float hAlong  = dot(dH.xz, sunHorizDir);

    // Dual-lobe Anisotropic Trowbridge-Reitz / GGX Normal Distribution Function:
    vec2 axy1 = (ACTIVE_WATER_STYLE == 2) ? vec2(0.088, 0.24) : vec2(0.080, 0.23);
    float denom1 = (hAcross / axy1.x) * (hAcross / axy1.x) + (hAlong / axy1.y) * (hAlong / axy1.y) + NoH * NoH;
    float dGgxBloom = (1.0 / max(3.14159265 * axy1.x * axy1.y * denom1 * denom1, 1e-5)) * 0.052;

    vec2 axy2 = (ACTIVE_WATER_STYLE == 2) ? vec2(0.030, 0.100) : vec2(0.025, 0.092);
    float denom2 = (hAcross / axy2.x) * (hAcross / axy2.x) + (hAlong / axy2.y) * (hAlong / axy2.y) + NoH * NoH;
    float dGgxGlint = (1.0 / max(3.14159265 * axy2.x * axy2.y * denom2 * denom2, 1e-5)) * 0.015;

    // Modulate by natural 3D wave crests and sun-facing wave slopes so troughs stay dark water
    float sunSlopeRaw = -dot(surfGradXZ + detWave.xy * 0.60, sunHorizDir);
    float crestMask   = pow(clamp(detWave.z * 95.0 + 0.54, 0.0, 1.0), 1.30);
    float sunSlope    = clamp(sunSlopeRaw * 34.0 + 0.45, 0.0, 1.0);
    float waveMod     = crestMask * (0.32 + 0.68 * sunSlope) * grazingShimmerGate;

    float bloomLobe = dGgxBloom * waveMod;
    float glintLobe = dGgxGlint * pow(crestMask, 1.4) * sunSlope * grazingShimmerGate;

    // Gentle Fresnel compensation bounded at 0.18 (never 20x at steep downward angles!)
    float effWaterTexComp = (WATER_TEXTURE > 0.0) ? WATER_TEXTURE : ((ACTIVE_WATER_STYLE == 2) ? 0.62 : 0.0);
    float fresnelApprox   = clamp(0.05 + 0.78 * pow(1.0 - NdotV_flat, 3.8), 0.05, 0.80) * mix(1.0, 0.76, effWaterTexComp);
    float fresnelWeight   = 0.35 + 0.65 / max(fresnelApprox, 0.18);

    vec3 totalShimmer = (activeBloomTint * bloomLobe + activeCoreTint * glintLobe * 1.25)
                      * fresnelWeight * celestialWeight * glintOcclusion;

    return skyRefl + totalShimmer;
}

#include "/lib/flow_foam.glsl"

void shadeSurface() {
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
    if (isYunMengEndPortal(matTag)) {
        vec3 portalView = reconstructViewPos(vTexCoord, depth0);
        vec3 portalPlayer = (gbufferModelViewInverse * vec4(portalView, 1.0)).xyz;
        outColor0 = vec4(renderYunMengEndPortal(portalPlayer, portalPlayer), 1.0);
        return;
    }
    vec4 lmSample = texture(colortex2, vTexCoord);
    // Strict integer texelFetch material tag check for emissive eyes (0.36 or additive 0.46):
    // NEVER uses bilinear texture() or colortex2.a, eliminating 100% of silhouette-edge & particle false positives!
    ivec2 surfTexSize = textureSize(colortex1, 0);
    ivec2 surfCoord   = clamp(ivec2(vTexCoord * vec2(surfTexSize)), ivec2(0), surfTexSize - 1);
    float exactMatTag = texelFetch(colortex1, surfCoord, 0).a;
    if (exactMatTag > 0.335 && exactMatTag < 0.475) {
        // Keep linear eye radiance in the sweet spot (0.95) where ACES preserves 100% of the eye's saturated hue
        // instead of compressing all 3 channels to white!
        // Preserve the sclera vs. pupil hue & brightness contrast already prepared in gbuffers_spidereyes / gbuffers_entities
        vec3 eyeRadiance = albedo * 0.96;
        outColor0 = vec4(pow(max(eyeRadiance, vec3(0.0)), vec3(1.0 / 2.2)), 1.0);
        return;
    }
    float blockLight = lmSample.r;
    float skyLight   = lmSample.g;
    float vertexAo   = abs(matTag-0.90)<0.05 ? 1.0 : lmSample.b;
    float fluidGeometry=lmSample.a;
    float verticalWaterFace=fluidGeometry;
    if(isEyeInWater==0) {
        if(waterIsThinFlowTop(fluidGeometry)) verticalWaterFace=0.0;
        else if(waterIsSlopedTop(fluidGeometry)) verticalWaterFace=64.0/255.0;
    }

    vec3 viewPos   = reconstructViewPos(vTexCoord, depth0);
    vec3 playerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 worldPos  = playerPos + cameraPosition;
    float waterLinDepth = linearizeDepth(depth0);
    vec3 flowCross=cross(dFdx(playerPos),dFdy(playerPos));
    vec3 flowNormal=flowCross/max(length(flowCross),1e-6);
    float flowFootprint=max(length(dFdx(playerPos)),length(dFdy(playerPos)));
    float flowNeighborChange=abs(dFdx(fluidGeometry))+abs(dFdy(fluidGeometry));
    // Derivatives evaluated before the material branch for stable filtering.
    // On opaque terrain where depth1 == depth0, reuse viewPos directly to avoid
    // a redundant inverse-projection matrix multiply per pixel.
    vec3 bottomViewPos = (depth1 != depth0) ? reconstructViewPos(vTexCoord, depth1) : viewPos;
    vec3 bottomCross = cross(dFdx(bottomViewPos), dFdy(bottomViewPos));

    float rawNdotL = dot(viewNormal, vLightViewDir);
    bool isFoliageOrBamboo = (matTag > 0.20 && matTag < 0.80);
    bool isWaterSurface    = (abs(matTag - 0.90) < 0.05);
    bool isSmoothIce       = (abs(matTag - 0.82) < 0.005);
    bool isPackedIce       = (abs(matTag - 0.83) < 0.005);
    bool isIceBlock        = isSmoothIce || isPackedIce;
    bool isEntity          = (abs(matTag - 0.10) < 0.05);

    bool isTreeCanopy = (abs(matTag - 0.50) < 0.05 || abs(matTag - 0.75) < 0.05);
    float wrapNdotL = isTreeCanopy
        ? clamp((rawNdotL + 0.22) / 1.22, 0.0, 1.0)
        : (isWaterSurface ? clamp((rawNdotL + 0.65) / 1.65, 0.30, 1.0) : clamp((rawNdotL + 0.08) / 1.08, 0.0, 1.0));

    vec3 shadowVis = (wrapNdotL > 0.001)
        ? computeShadowVisibility(playerPos, viewNormal, wrapNdotL)
        : vec3(0.0);

    vec3 sunColorDay    = (STYLE_SELECTION == 0) ? vec3(1.22, 1.13, 0.98) : vec3(1.34, 1.22, 1.05);
    vec3 sunColorSunset = (STYLE_SELECTION == 0) ? vec3(1.18, 0.74, 0.48) : vec3(1.36, 0.76, 0.48);
    vec3 moonColorNight = (STYLE_SELECTION == 0) ? vec3(0.028, 0.040, 0.056) : vec3(0.030, 0.044, 0.068);

    float wetnessFactor, stormFactor, lightningFlash, skyLightOpening;
    evaluateSceneWeatherAndOpening(worldPos, wetnessFactor, stormFactor, lightningFlash, skyLightOpening);

    vec3 directLightColor = mix(moonColorNight, mix(sunColorDay, sunColorSunset, vTwilightFactor), vDaylightFactor);
    directLightColor *= skyLightOpening;
    float sourceVisibility = smoothstep(0.04, 0.20, dot(vLightViewDir, vUpViewDir));
    directLightColor *= sourceVisibility;

    float ambientFloor = (STYLE_SELECTION == 0)
        ? mix(mix(0.045, 0.060, wetnessFactor), mix(0.15, 0.13, stormFactor), vDaylightFactor)
        : mix(mix(0.048, 0.065, wetnessFactor), mix(0.16, 0.14, stormFactor), vDaylightFactor);

    vec3 clearSkyAmbient = (STYLE_SELECTION == 0)
        ? mix(vec3(0.013, 0.019, 0.028), vec3(0.24, 0.28, 0.31), vDaylightFactor)
        : mix(vec3(0.014, 0.021, 0.034), vec3(0.26, 0.35, 0.45), vDaylightFactor);
    vec3 rainSkyAmbient = (STYLE_SELECTION == 0)
        ? mix(vec3(0.012, 0.018, 0.026), vec3(0.22, 0.27, 0.29), vDaylightFactor)
        : mix(vec3(0.012, 0.018, 0.030), vec3(0.20, 0.26, 0.32), vDaylightFactor);
    vec3 stormSkyAmbient = (STYLE_SELECTION == 0)
        ? mix(vec3(0.009, 0.014, 0.020), vec3(0.12, 0.16, 0.17), vDaylightFactor)
        : mix(vec3(0.009, 0.014, 0.024), vec3(0.12, 0.16, 0.21), vDaylightFactor);
    vec3 skyAmbientColor = mix(clearSkyAmbient, mix(rainSkyAmbient, stormSkyAmbient, stormFactor), wetnessFactor);
    float bAmbScale = (0.42 * vDaylightFactor * vDaylightFactor) * (1.0 - wetnessFactor * 0.55) * BIOME_TINT_STRENGTH;
    skyAmbientColor = mix(skyAmbientColor, vec3(0.24, 0.48, 0.42) * bAmbScale * 2.4, clamp(inBambooJungle, 0.0, 1.0) * 0.30);
    skyAmbientColor = mix(skyAmbientColor, vec3(0.50, 0.38, 0.46) * bAmbScale * 2.4, clamp(inCherryGrove,  0.0, 1.0) * 0.28);
    skyAmbientColor = mix(skyAmbientColor, vec3(0.38, 0.46, 0.60) * bAmbScale * 2.4, clamp(inSnowyBiome,   0.0, 1.0) * 0.30);
    skyAmbientColor = mix(skyAmbientColor, vec3(0.52, 0.44, 0.32) * bAmbScale * 2.4, clamp(inAridBiome,    0.0, 1.0) * 0.32);
    skyAmbientColor = mix(skyAmbientColor, vec3(0.30, 0.38, 0.30) * bAmbScale * 2.4, clamp(inSwampBiome,   0.0, 1.0) * 0.30);
    float paleAmbW = evaluatePaleGardenWeight();
    if (paleAmbW > 0.001) {
        vec3 paleAmb = mix(vec3(0.016, 0.016, 0.018), vec3(0.24, 0.23, 0.22), vDaylightFactor);
        skyAmbientColor = mix(skyAmbientColor, paleAmb, paleAmbW * 0.85);
        directLightColor = mix(directLightColor, vec3(dot(directLightColor, vec3(0.2126, 0.7152, 0.0722))) * 0.82, paleAmbW * 0.70);
    }
    float endDimensionWeight = clamp(inTheEnd, 0.0, 1.0);

    if (isEyeInWater == 1) {
        vec3 uwTint = ((STYLE_SELECTION == 0) ? vec3(0.42, 0.68, 0.65) : vec3(0.34, 0.74, 0.82)) * evaluateBiomeWaterMod();
        directLightColor *= uwTint * 0.72;
        skyAmbientColor  *= uwTint * 0.68;
    }

    // Deepen vertex corner AO and add 4-tap Screen-Space Contact Crease AO so block steps (e.g. sand ledges)
    // exhibit crisp, sculptural 3D corner shadows even in full direct sunlight!
    float cornerAo = pow(clamp(vertexAo, 0.0, 1.0), 2.25);
    if (!isWaterSurface && waterLinDepth < 48.0) {
        vec2 aoStep = (1.35 / max(waterLinDepth, 1.2)) / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
        float dR = linearizeDepth(texture(depthtex0, vTexCoord + vec2( aoStep.x, 0.0)).r);
        float dL = linearizeDepth(texture(depthtex0, vTexCoord + vec2(-aoStep.x, 0.0)).r);
        float dU = linearizeDepth(texture(depthtex0, vTexCoord + vec2(0.0,  aoStep.y)).r);
        float dD = linearizeDepth(texture(depthtex0, vTexCoord + vec2(0.0, -aoStep.y)).r);
        float creaseX = max((waterLinDepth * 2.0) - (dR + dL), 0.0);
        float creaseY = max((waterLinDepth * 2.0) - (dU + dD), 0.0);
        float crease  = (creaseX + creaseY) / max(waterLinDepth * 0.045, 0.02);
        float distFadeAo = 1.0 - smoothstep(28.0, 48.0, waterLinDepth);
        float ssCreaseAo = 1.0 - clamp(smoothstep(0.12, 0.85, crease) * (1.0 - smoothstep(1.8, 3.5, crease)) * 0.36 * distFadeAo, 0.0, 0.36);
        cornerAo *= ssCreaseAo;
    }

    vec3 worldNorm = normalize(mat3(gbufferModelViewInverse) * viewNormal);
    float faceAxisShade = isWaterSurface ? 1.0 : (0.90 + 0.10 * clamp(worldNorm.y, 0.0, 1.0) - 0.05 * abs(worldNorm.x));
    float skyFacing = clamp(dot(viewNormal, vUpViewDir) * 0.5 + 0.5, 0.0, 1.0);
    float skyHemisphere = mix(0.54, 1.0, skyFacing) * faceAxisShade;
    vec3 ambientLight = skyAmbientColor * mix(ambientFloor, 1.0, skyLight * skyLight) * cornerAo * skyHemisphere;
    if (lightningFlash > 0.001 && isEyeInWater == 0) {
        vec3 flashColor = (STYLE_SELECTION == 0) ? vec3(0.58, 0.70, 0.78) : vec3(0.56, 0.72, 0.98);
        float flashExposure = skyLight * skyLight * (0.35 + 0.65 * skyFacing) * vertexAo;
        ambientLight += flashColor * (lightningFlash * flashExposure * 0.52);
    }
    // Smooth 3D Dynamic Hand-Held Light (Main Hand & Off-Hand):
    // The lightmap contains placed lighting and may also contain mod-injected
    // light. Those sources cannot be separated here; preserve it and combine
    // held illumination with max below, so equipping an item cannot erase it.
    float effectiveBlockLight = blockLight;
    float dynamicTorch = 0.0;
    float dynamicSpec  = 0.0;
    #if DYNAMIC_LIGHTING > 0
    float heldStrength = float(max(heldBlockLightValue, heldBlockLightValue2)) / 15.0;
    if (heldStrength > 0.001) {
        vec3 activeHandOrigin = evaluateHandPlayerOrigin();
        vec3 toLightPlayer = activeHandOrigin - playerPos;
        float handDist = length(toLightPlayer);

        float radius = 15.0 * heldStrength;
        float distNorm = clamp(handDist / max(radius, 0.001), 0.0, 1.0);
        // Scale normalized distance falloff by heldStrength so low-luminance blocks (e.g. End Portal Frame,
        // light level 1 -> heldStrength = 1/15) emit proportional level-1 light instead of full level-15 torch brightness.
        float smoothLinear = smoothstep(0.0, 1.0, (1.0 - distNorm) * heldStrength);

        #if DYNAMIC_LIGHTING == 1
        // Simple (Low preset): fast quadratic radial falloff without view-matrix normal transforms or specular pow
        float radialAtten = smoothLinear * smoothLinear * 1.05;
        dynamicTorch = radialAtten * vertexAo;
        #else
        // Medium & High: full-warmth dual-exponent radial falloff matching placed block light + 3D directional shading
        float radialAtten = pow(smoothLinear, 1.85) * 0.68 + pow(smoothLinear, 3.6) * 0.52;
        vec3 handLightDirView = normalize(mat3(gbufferModelView) * (toLightPlayer / max(handDist, 1e-4)));
        float handNdotL = isFoliageOrBamboo
            ? (0.88 + 0.18 * max(dot(viewNormal, handLightDirView), 0.0))
            : (isWaterSurface ? 0.92 : (0.82 + 0.24 * clamp((dot(viewNormal, handLightDirView) + 0.45) / 1.45, 0.0, 1.0)));
        bool isPlayerOrHeldItem = (abs(matTag - 0.10) < 0.015 || abs(matTag - 0.06) < 0.015);
        if (abs(matTag - 0.12) < 0.007) {
            handNdotL = 0.95;
            radialAtten = max(radialAtten, 0.82 * pow(heldStrength, 2.2));
        } else if (isPlayerOrHeldItem) {
            float nearPlayerW = 1.0 - smoothstep(0.65, 1.75, handDist);
            handNdotL = mix(handNdotL, 0.92, nearPlayerW);
            radialAtten = mix(radialAtten, max(radialAtten, 0.72 * pow(heldStrength, 2.2)), nearPlayerW);
        }
        #if DYNAMIC_LIGHTING >= 3
        // High (High/Ultra presets): subtle albedo micro-relief contrast + grazing rim + water surface specular glints
        float lumaRelief = clamp(1.0 + (dot(albedo, vec3(0.3333)) - 0.32) * 0.20, 0.90, 1.12);
        float rimGlow = (1.0 - clamp(abs(dot(viewNormal, -normalize(viewPos))), 0.0, 1.0)) * 0.12;
        dynamicTorch = radialAtten * (handNdotL * lumaRelief + rimGlow) * vertexAo;
        if (isWaterSurface || isIceBlock) {
            vec3 halfHand = normalize(-normalize(viewPos) + handLightDirView);
            dynamicSpec = pow(max(dot(viewNormal, halfHand), 0.0), 64.0) * radialAtten * 0.65;
        }
        #else
        dynamicTorch = radialAtten * handNdotL * vertexAo;
        #endif
        #endif
    }
    #endif

    float smoothBlock = smoothstep(0.0, 1.0, effectiveBlockLight);
    float torchFalloff = pow(smoothBlock, 1.85) * 0.68 + pow(smoothBlock, 3.6) * 0.52;
    float combinedTorch = max(torchFalloff, dynamicTorch);
    vec3 lanternTint = (STYLE_SELECTION == 0) ? vec3(1.32, 0.78, 0.38) : vec3(1.38, 0.80, 0.38);
    vec3 lanternLight = lanternTint * combinedTorch * 1.45;

    float directCornerAo = isWaterSurface ? 1.0 : (mix(0.42, 1.0, cornerAo) * faceAxisShade);
    vec3 totalLighting = ambientLight + directLightColor * wrapNdotL * shadowVis * directCornerAo + lanternLight;
    if (endDimensionWeight > 0.001) {
        // Distortion-Free 3D Diagonal Celestial & Cavern/Step Relief Lighting in The End:
        // - Does NOT use Iris's horizon-locked shadow map (so zero frustum-cutoff or player shadow distortion!).
        // - Combines full cornerAo (pow(vertexAo, 2.25) * ssCreaseAo) and directCornerAo with a 42-degree diagonal
        //   celestial light direction (-0.54, 0.56, -0.63) so caverns, overhangs, and back-facing terrace steps have
        //   deep, sculptural shadow while top terraces and light-facing risers are warmly illuminated!
        const vec3 endHaloDirWorld = vec3(-0.540, 0.560, -0.628);
        float rawEndDot    = dot(worldNorm, endHaloDirWorld);
        float endHaloNdotL = smoothstep(-0.28, 0.72, rawEndDot);
        float endUpFacing  = clamp(worldNorm.y * 0.5 + 0.5, 0.0, 1.0);
        float diagFaceMod  = isWaterSurface ? 1.0 : (0.80 + 0.28 * clamp(rawEndDot * 0.6 + 0.4, 0.0, 1.0));

        vec3 endShadowAmb  = (STYLE_SELECTION == 0) ? vec3(0.016, 0.024, 0.020) : vec3(0.014, 0.026, 0.030);
        vec3 endMidAmb     = (STYLE_SELECTION == 0) ? vec3(0.038, 0.045, 0.038) : vec3(0.036, 0.048, 0.050);
        vec3 endTerraceLit = (STYLE_SELECTION == 0) ? vec3(0.068, 0.064, 0.050) : vec3(0.064, 0.068, 0.062);

        vec3 endDomeLighting = mix(endShadowAmb, endMidAmb, endUpFacing) * cornerAo * diagFaceMod
                             + endTerraceLit * endHaloNdotL * smoothstep(-0.35, 0.55, worldNorm.y) * directCornerAo
                             + lanternLight;
        totalLighting = mix(totalLighting, endDomeLighting, endDimensionWeight);
    }
    vec3 litRadiance   = albedo * totalLighting;

    if (isWaterSurface && isEyeInWater == 0) {
        vec3 flowNormalWorld = normalize(mat3(gbufferModelViewInverse) * flowNormal);
        float spillwaySheet = waterIsSlopedTop(fluidGeometry)
            ? (1.0 - smoothstep(0.70, 0.985, abs(flowNormalWorld.y))) : 0.0;
        float columnMask = max(verticalWaterFace, spillwaySheet);

        // Apply bottom reconstruction and optical water absorption consistently across ALL water faces
        // (horizontal pools, sloped cascades, and vertical waterfall walls) so adjacent faces never mismatch.
        bool hasVisibleBottom = (depth1 > depth0 && depth1 < 0.999999);
        vec3 bottomViewNormal = vec3(0.0, 1.0, 0.0);
        vec3 bottomPlayerPos = playerPos;
        vec3 bottomWorldPos = worldPos;
        vec3 bottomNormalWorld = vec3(0.0, 1.0, 0.0);
        float verticalDrop = 32.0;
        float rayWaterDist = 32.0;

        if (hasVisibleBottom) {
            vec4 bottomOpaqueBank = texture(colortex13, vTexCoord);
            if (bottomOpaqueBank.a > 0.99) {
                bottomViewNormal = normalize(bottomOpaqueBank.xyz * 2.0 - 1.0);
            } else {
                bottomViewNormal = bottomCross / max(length(bottomCross), 1e-6);
                if (dot(bottomViewNormal, -bottomViewPos) < 0.0) bottomViewNormal = -bottomViewNormal;
            }
            bottomPlayerPos = (gbufferModelViewInverse * vec4(bottomViewPos, 1.0)).xyz;
            bottomWorldPos = bottomPlayerPos + cameraPosition;
            bottomNormalWorld = normalize(mat3(gbufferModelViewInverse) * bottomViewNormal);
            verticalDrop = max(worldPos.y - bottomWorldPos.y, 0.0);
            rayWaterDist = max(length(bottomPlayerPos - playerPos), 0.0);
        }

        vec3 reflectionColor = computeWaterSurfaceReflection(
            viewPos,
            viewNormal,
            waterLinDepth,
            skyLight,
            directLightColor,
            skyAmbientColor,
            ambientFloor,
            shadowVis,
            vec4(wetnessFactor, stormFactor, lightningFlash, skyLightOpening),
            waterIsSlopedTop(verticalWaterFace),
            true
        );
        float NdotV = clamp(abs(dot(viewNormal, normalize(-viewPos))), 0.0, 1.0);
        float fresnel = clamp(0.05 + 0.78 * pow(1.0 - NdotV, 3.8), 0.0, 0.80);
        if (verticalWaterFace < 0.5) {
            fresnel = mix(clamp(0.03 + 0.80 * pow(1.0 - NdotV, 3.8), 0.0, 0.80), fresnel, spillwaySheet);
        }

        // Keep nocturnal water dark and moody so rivers don't glow neon turquoise at midnight
        litRadiance *= mix(0.45, 1.0, vDaylightFactor);

        if (hasVisibleBottom) {
            // Unify optical depth across horizontal steps, sloped chutes, and vertical curtains:
            // bound multi-block air/drop gaps beneath elevated waterfall ledges while giving vertical walls
            // consistent optical body.
            float boundedPoolDepth = min(verticalDrop, rayWaterDist * 1.15 + 0.35);
            float columnEffectiveDepth = clamp(mix(rayWaterDist, boundedPoolDepth, 0.45), 0.55, 2.20);
            float effectiveWaterDepth = mix(boundedPoolDepth, columnEffectiveDepth, columnMask * 0.78);

            float bottomNdotL = max(dot(bottomViewNormal, vLightViewDir), 0.0);
            vec3 bottomShadow = computeShadowVisibility(bottomPlayerPos, bottomViewNormal, bottomNdotL);
            float bottomHemisphere = mix(0.65, 1.0, clamp(bottomNormalWorld.y * 0.5 + 0.5, 0.0, 1.0));
            vec3 bottomAmbient = skyAmbientColor * mix(ambientFloor, 1.0, skyLight * skyLight) * bottomHemisphere;
            vec3 bottomLighting = bottomAmbient + directLightColor * bottomNdotL * bottomShadow + lanternLight;
            vec3 lightingRatio = clamp(bottomLighting / max(totalLighting, vec3(0.025)), vec3(0.38), vec3(1.15));
            float bottomVisibility = exp(-effectiveWaterDepth * 0.14) * (1.0 - columnMask * 0.55);
            litRadiance *= mix(vec3(1.0), lightingRatio, bottomVisibility * 0.78);

            // Above-water riverbed caustics: evaluated on the unwarped riverbed (matching the underwater look)
            // BEFORE applySurfaceWaterAbsorption so caustics sit naturally inside the water volume beneath reflections!
            float bottomUpFacing = clamp(bottomNormalWorld.y, 0.0, 1.0);
            if (CAUSTICS_STRENGTH > 0.0 && dot(bottomShadow, vec3(0.3333)) > 0.001) {
                vec3 lightDirWorld = normalize(mat3(gbufferModelViewInverse) * vLightViewDir);
                float upwardFloor  = smoothstep(0.02, 0.70, bottomNormalWorld.y);
                float sunFloor     = smoothstep(0.00, 0.32, bottomNdotL);
                float depthWindow  = smoothstep(0.05, 0.85, effectiveWaterDepth) * exp(-effectiveWaterDepth * 0.16);
                float distFade     = exp(-length(bottomPlayerPos) * 0.024);
                float lunarWeight  = (float(abs(4 - (moonPhase & 7))) * 0.25) * 0.03;
                float timeGate     = mix(lunarWeight, 1.0, vDaylightFactor) * sourceVisibility * skyLightOpening;
                float riverCausticMask = 0.92 * upwardFloor * sunFloor * depthWindow * distFade * (1.0 - columnMask * 0.80) * timeGate;

                if (riverCausticMask > 0.001) {
                    // Anchor Y slightly toward the block floor so vertical seagrass blades don't scramble the caustic UV
                    vec3 causticFloorPos = vec3(bottomWorldPos.x, mix(bottomWorldPos.y, floor(bottomWorldPos.y + 0.05), 0.60), bottomWorldPos.z);
                    vec3 riverCaustics   = evaluateDynamicCaustics(causticFloorPos, lightDirWorld, frameTimeCounter * 0.42 * WIND_SPEED);
                    vec3 surfaceScatterTint = litRadiance * 0.95 + ((STYLE_SELECTION == 0) ? vec3(0.014, 0.026, 0.026) : vec3(0.012, 0.028, 0.034)) * vDaylightFactor;
                    litRadiance += surfaceScatterTint * riverCaustics * bottomShadow * riverCausticMask * 1.45;
                }
            }

            float scatteredDaylight = vDaylightFactor * (0.58 + 0.42 * dot(bottomShadow, vec3(0.333333)));
            vec3 absorbedRadiance = applySurfaceWaterAbsorption(litRadiance, effectiveWaterDepth, scatteredDaylight, skyLight);
            litRadiance = mix(absorbedRadiance, litRadiance, columnMask * 0.22);

            // Optical shallow-water & cascade landing scatter: keep luminous turquoise/celadon scatter active
            // where flowing water nears the ground so lower waterfall endings seamlessly match the pool below.
            float landingScatterMask = max(bottomUpFacing, columnMask * (1.0 - smoothstep(0.15, 1.25, verticalDrop)) * 0.75);
            float shallowShelf = exp(-effectiveWaterDepth * 0.68) * (1.0 - exp(- max(effectiveWaterDepth, 0.18) * 8.0)) * landingScatterMask;
            vec3 shallowTint = mix(((STYLE_SELECTION == 0) ? vec3(0.32, 0.66, 0.62) : vec3(0.10, 0.72, 0.82)) * evaluateBiomeWaterMod(), albedo * 1.35, 0.65 * clamp(BIOME_TINT_STRENGTH, 0.0, 1.25)) * mix(0.32, 1.0, vDaylightFactor);
            litRadiance = mix(litRadiance, litRadiance * 0.86 + shallowTint * totalLighting * 0.38, shallowShelf * 0.72);

        }
        else {
            float fallbackDepth = mix(32.0, 1.65, columnMask);
            litRadiance = applySurfaceWaterAbsorption(litRadiance, fallbackDepth, vDaylightFactor, skyLight);
        }

        float effWaterTexSurf = (WATER_TEXTURE > 0.0) ? WATER_TEXTURE : ((ACTIVE_WATER_STYLE == 2) ? 0.62 : 0.0);

        float foam = 0.0;
        if (FLOW_FOAM_STRENGTH > 0.0) {
            foam = flowingContactFoam(
                playerPos,
                worldPos,
                flowNormal,
                fluidGeometry,
                flowFootprint,
                flowNeighborChange,
                lmSample.b,
                verticalDrop
            );
        }

        // Gently soften mirror reflection over aerated swash and keep the authentic gtexture surface texture readable
        float effectiveFresnel = fresnel * (1.0 - foam * 0.35) * mix(1.0, 0.76, effWaterTexSurf);
        litRadiance = mix(litRadiance, reflectionColor, effectiveFresnel) + lanternTint * dynamicSpec;

        if (foam > 0.001) {
            vec3 foamColor = (STYLE_SELECTION == 0) ? vec3(0.74, 0.84, 0.80) : vec3(0.82, 0.93, 0.97);
            // Restrained nocturnal ambient floor so swash stays readable at night without glowing brightly
            vec3 nocturnalFoamFloor = ((STYLE_SELECTION == 0) ? vec3(0.045, 0.070, 0.078) : vec3(0.050, 0.085, 0.125))
                * mix(0.35, 1.0, skyLight) * vNightFactor;
            vec3 foamLight = skyAmbientColor * mix(0.40, 1.0, skyLight) * 1.18
                + directLightColor * (0.32 + 0.68 * max(dot(vUpViewDir, vLightViewDir), 0.0)) * (0.38 + 0.62 * shadowVis)
                + nocturnalFoamFloor
                + lanternLight * 0.58;
            litRadiance = mix(litRadiance, pow(foamColor, vec3(2.2)) * foamLight, foam);
        }
    } else if (isIceBlock && isEyeInWater == 0) {
        // Restrict sky/cloud/SSR ice reflections to upward-facing top surfaces (dot(viewNormal, vUpViewDir) > 0.85)
        // so looking down at the vertical side face of an ice block at a grazing angle never reflects bright sky/clouds.
        float horizontalIce = smoothstep(0.75, 0.95, dot(viewNormal, vUpViewDir));
        if (horizontalIce > 0.001) {
            vec3 iceReflection = computeWaterSurfaceReflection(
                viewPos,
                viewNormal,
                waterLinDepth,
                skyLight,
                directLightColor,
                skyAmbientColor,
                ambientFloor,
                shadowVis,
                vec4(wetnessFactor, stormFactor, lightningFlash, skyLightOpening),
                false,
                false
            );
            float NdotV = clamp(abs(dot(viewNormal, normalize(-viewPos))), 0.0, 1.0);
            float minIceRefl = isSmoothIce ? 0.035 : 0.015;
            float maxIceRefl = isSmoothIce ? 0.36  : 0.16;
            float iceFresnel = clamp(minIceRefl + (maxIceRefl - minIceRefl) * pow(1.0 - NdotV, 3.6), 0.0, maxIceRefl);
            float envAccess  = clamp(skyLight * 1.15 + effectiveBlockLight * 0.45, 0.15, 1.0);
            litRadiance = mix(litRadiance, iceReflection, iceFresnel * envAccess * horizontalIce);
        }
    }

    // Underwater caustics apply strictly when the camera is submerged (isEyeInWater == 1)
    // and only to surfaces at or below the water plane. Above-water riverbed caustics are
    // already evaluated inside the water surface branch above; shared wetness must never
    // project underwater caustic patterns onto land!
    if (!isEntity && isEyeInWater == 1 && !isWaterSurface) {
        vec3 lightDirWorld = normalize(mat3(gbufferModelViewInverse) * vLightViewDir);
        vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * viewNormal);
        // Strict direct-sunlight & upward-orientation gating: caustics only appear on sunlit upward surfaces
        // (shadowVis > 0 and facing the light source), never inside dark shadows, overhangs, or back-facing slopes.
        float upwardSurface = smoothstep(0.02, 0.70, worldNormal.y);
        float sunFacing     = smoothstep(0.00, 0.32, rawNdotL);
        float distAtten     = exp(-length(playerPos) * 0.022);
        float causticMask   = 0.85 * upwardSurface * sunFacing * distAtten;

        // Caustics are a daytime sunlight refraction phenomenon (fading out at night except for a tiny 3% full-moon whisper)
        float lunarCausticWeight = (float(abs(4 - (moonPhase & 7))) * 0.25) * 0.03;
        float causticTimeGate = mix(lunarCausticWeight, 1.0, vDaylightFactor) * sourceVisibility * skyLightOpening;
        if (causticMask > 0.001 && causticTimeGate > 0.001 && dot(shadowVis, vec3(0.3333)) > 0.001) {
            vec3 caustics = evaluateDynamicCaustics(worldPos, lightDirWorld, frameTimeCounter * 0.42 * WIND_SPEED);
            // Modulate the block albedo subtly without neon additive paint so caustics look like natural water refraction
            vec3 surfaceScatterTint = albedo * 0.90 + ((STYLE_SELECTION == 0) ? vec3(0.012, 0.022, 0.022) : vec3(0.010, 0.024, 0.028)) * vDaylightFactor;
            litRadiance += surfaceScatterTint * caustics * shadowVis * causticMask * causticTimeGate;
        }
    }

    // Procedural raindrop impact ripples on sky-exposed wet ground & water surfaces
    float liquidRainGate = clamp(rainStrength, 0.0, 1.0) * (1.0 - clamp(inSnowyBiome, 0.0, 1.0))
                         * (1.0 - clamp(inAridBiome, 0.0, 1.0)) * (1.0 - endDimensionWeight);
    if (liquidRainGate > 0.02 && isEyeInWater == 0 && !isEntity && !isFoliageOrBamboo && worldNorm.y > 0.84) {
        float rippleDistFade = 1.0 - smoothstep(14.0, 30.0, length(playerPos));
        float rainOpenSky    = smoothstep(0.84, 0.96, skyLight);
        float rippleMask     = liquidRainGate * rippleDistFade * rainOpenSky;
        if (rippleMask > 0.005) {
            float rippleVal = evaluateRainImpactRipples(worldPos.xz, frameTimeCounter * max(WIND_SPEED, 0.45));
            vec3 rippleTint = (STYLE_SELECTION == 0)
                ? mix(vec3(0.045, 0.065, 0.075), vec3(0.32, 0.38, 0.38), vDaylightFactor)
                : mix(vec3(0.045, 0.070, 0.095), vec3(0.30, 0.40, 0.48), vDaylightFactor);
            float surfaceGain = isWaterSurface ? 0.34 : 0.20;
            litRadiance += rippleTint * (rippleVal * surfaceGain * rippleMask);
        }
    }

    float shadowLuma = clamp(dot(shadowVis, vec3(0.3333)), 0.0, 1.0);
    // Shadow grading must fade with direct lighting too. Otherwise an unlit
    // east/west face still changes its ambient tint when the source swaps.
    shadowLuma = mix(1.0, shadowLuma, sourceVisibility);
    vec3 gradedRadiance = applyYunMengCanvasGrading(litRadiance, matTag, shadowLuma, blockLight);

    outColor0 = vec4(pow(max(gradedRadiance, vec3(0.0)), vec3(1.0 / 2.2)), 1.0);
}

void main() {
    shadeSurface();
}
