#include "/lib/temporal_jitter.glsl"
// Build 2 performance update: scalable cloud, shadow and shoreline settings.
/* =============================================================================
 * composite1.fsh â€” Unified 3D Volumetric Cloud Engine, Atmosphere & Night Sky
 * ============================================================================= */

#define STYLE_SELECTION 1             // [0 1] 0: Guofeng Ink, 1: Xianxia Mist
#define CLOUD_QUALITY 1               // [0 1 2 3] Low, Medium, High, Ultra
#define CLOUD_TYPE 0                  // [0 1 2 3] 0: Auto (By Style), 1: Shanshui 3D, 2: Cumulus 3D, 3: Off
#define NIGHT_AURORA 0                // [0 1 2 3] 0: Auto (By Theme & Style), 1: Xianxia Celestial, 2: Guofeng Jade Silk, 3: Off
#include "/lib/fog_options.glsl"
#include "/lib/atmospheric_options.glsl"
#define BIOME_TINT_STRENGTH 1.00      // [0.00 0.50 0.75 1.00 1.15 1.25 1.50]
#define SUN_SIZE 1.00                 // [0.50 0.75 1.00 1.25 1.50 2.00]
#define SUN_LENS_FLARE 1              // [0 1 2] Off, Soft, Full
#define WIND_SPEED 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]
#define WATER_REFLECTIONS 1           // [0 1 2] Sky Only, Fast SSR, Full SSR

noperspective in vec2 vTexCoord;
flat in vec3 vLightViewDir;
flat in vec3 vSunViewDir;
flat in vec3 vMoonViewDir;
flat in vec3 vSunWorldDir;
flat in vec3 vMoonWorldDir;
flat in vec3 vUpViewDir;
flat in vec3 vLightWorldDir;
flat in float vDaylightFactor;
flat in float vNoonFactor;
flat in float vSunsetFactor;
flat in float vNightFactor;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D colortex13;
uniform sampler2D shadowtex1;
uniform sampler2D noisetex;
uniform sampler2D celestialTex;
uniform sampler2D guofengMoonTex;
uniform sampler2D xianxiaMoonTex;
#include "/lib/shadow_coverage.glsl"
#include "/lib/water_optics.glsl"
#include "/lib/water_waves.glsl"

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform float viewHeight;
uniform float viewWidth;
uniform float far;
uniform float near;
uniform float fogStart;
uniform float fogEnd;
uniform float rainStrength;
uniform float rainFactor;
uniform float thunderStrength;
uniform vec4 lightningBoltPosition;
uniform vec3 skyColor;
uniform vec3 fogColor;
uniform float eyeAltitude;
uniform int frameCounter;
uniform int isEyeInWater;
uniform int moonPhase;

uniform float biomeTemp;
uniform float biomeRain;
uniform float inBambooJungle;
uniform float inMountainBiome;
uniform float inCherryGrove;
uniform float inSnowyBiome;
uniform float inAridBiome;
uniform float inSwampBiome;
uniform float inTheEnd;


uniform float eyeSkyFactor;
#ifndef YUNMENG_CLOUD_PREPASS
#define YUNMENG_CLOUD_LIGHT_CACHE
#include "/lib/water_environment.glsl"
#include "/lib/water_fall.glsl"
#endif
#include "/lib/cloud_field.glsl"
#include "/lib/end_portal.glsl"
#include "/lib/air_fog.glsl"

// Uses Iris's 3-second smoothed biome_category uniforms directly so standard temperate biomes
// (Oak Forest, Birch Forest, Dark Forest, Plains, Meadow, Taiga, River) keep the clean default sky
// and never falsely trigger Swamp green or red/pink skybox flickers.
void evaluateSmoothBiomeWeights(out float wBamboo, out float wMountain, out float wCherry,
                                out float wSnowy, out float wArid, out float wSwamp) {
    float bStr = clamp(BIOME_TINT_STRENGTH, 0.0, 1.5);
    wBamboo   = clamp(inBambooJungle  * bStr, 0.0, 1.0);
    wMountain = clamp(inMountainBiome * bStr, 0.0, 1.0);
    wCherry   = clamp(inCherryGrove   * bStr, 0.0, 1.0);
    wSnowy    = clamp(inSnowyBiome    * bStr, 0.0, 1.0);
    wArid     = clamp(inAridBiome     * bStr, 0.0, 1.0);
    wSwamp    = clamp(inSwampBiome    * bStr, 0.0, 1.0);
}


#ifdef YUNMENG_CLOUD_PREPASS
/* RENDERTARGETS: 8,9,10,11 */
/*
const int colortex8Format = RGBA16F;
*/
/*
const int colortex9Format = RGBA16F;
*/
const vec4 colortex8ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex9ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
layout(location = 1) out vec4 outWaterEnvironment;
layout(location = 2) out vec4 outCloudLight;
/*
const int colortex10Format = RGBA16F;
*/
const vec4 colortex10ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
layout(location = 3) out vec4 outFarCloudLight;
/*
const int colortex11Format = RGBA16F;
*/
// The prepass overwrites every texel, including invalid/padded regions.
const bool colortex11Clear = false;
const vec4 colortex11ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
#elif LIGHT_SHAFTS > 0
/* RENDERTARGETS: 0,7 */
layout(location = 1) out vec4 outAtmosphericShafts;
/*
const int colortex7Format = RGBA16F;
*/
const vec4 colortex7ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
#else
/* RENDERTARGETS: 0 */
#endif
layout(location = 0) out vec4 outColor0;

// Hash without Sine by David Hoskins (MIT License, https://www.shadertoy.com/view/4djSRW)
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

float smoothNoise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    // Quintic C2-continuous interpolation prevents lattice derivative creases
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash13(i + vec3(1.0, 1.0, 1.0));

    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z);
}

float silkyFbm3D(vec3 p) {
    float val = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 3; i++) {
        val += amp * smoothNoise3D(p);
        p = p * 2.02 + vec3(13.7, 29.3, 19.1);
        amp *= 0.5;
    }
    return val / 0.875;
}

float noise2D(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(
        mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x),
        mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}

float fbm2D(vec2 p) {
    float value = 0.0;
    float amp = 0.5;
    mat2 rot = mat2(0.80, -0.60, 0.60, 0.80);
    for (int i = 0; i < 4; i++) {
        value += amp * noise2D(p);
        p = rot * p * 2.03 + vec2(17.1, 31.7);
        amp *= 0.5;
    }
    return value;
}

vec4 sampleNoiseTexTiled(vec2 uv) {
    // Both bindings use the same PNG. Sample it once through the built-in
    // noise binding instead of fetching identical pixels from two samplers.
    return textureLod(noisetex, fract(uv), 0.0);
}

// Interleaved Gradient Noise by Jorge Jimenez (SIGGRAPH 2014) with temporal offset by Alan Wolfe
float interleavedGradientNoise(vec2 pixelCoord) {
    vec2 temporalOffset = vec2(float(frameCounter % 64) * 5.588238);
    return fract(52.9829189 * fract(dot(pixelCoord + temporalOffset, vec2(0.06711056, 0.00583715))));
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

bool isUnderwaterSurfaceCoveredByIce(vec2 uv, vec3 playerPos) {
    return texture(colortex13, uv).a > 0.5;
}


float henyeyGreensteinPhase(float cosTheta, float g) {
    float g2 = g * g;
    float denom = max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4);
    return (1.0 - g2) / (4.0 * 3.14159265 * pow(denom, 1.5));
}

void evaluateWeatherState(out float wetnessFactor, out float stormFactor, out float lightningFlash) {
    float rawWetness = clamp(mix(rainStrength, max(rainStrength, rainFactor), 0.60), 0.0, 1.0);
    wetnessFactor = rawWetness * rawWetness * (3.0 - 2.0 * rawWetness);

    float rawStorm = clamp(thunderStrength, 0.0, 1.0);
    stormFactor = (rawStorm * rawStorm * (3.0 - 2.0 * rawStorm)) * wetnessFactor;

    lightningFlash = clamp(lightningBoltPosition.w, 0.0, 1.0) * wetnessFactor;
}

// Evaluates directional light transmittance through the macro cloud field along vLightWorldDir.
// Allows sunlight/moonlight and volumetric shafts to shine through cloud openings during rain
// while naturally attenuating them under dense storm overcast.
float evaluateSkyLightOpening(vec3 camPos, float time, float rain, float storm) {
    int mode = (CLOUD_TYPE == 0) ? (STYLE_SELECTION == 0 ? 1 : 2) : CLOUD_TYPE;
    return cloudLightTransmission(camPos, vLightWorldDir, time, mode, rain, storm);
}

float computeLightningDirectionalBoost(vec3 worldRayDir) {
    if (lightningBoltPosition.w <= 0.01) return 0.65;
    float boltLen = length(lightningBoltPosition.xyz);
    if (boltLen <= 1e-3) return 0.65;
    vec3 boltDirWorld = lightningBoltPosition.xyz / boltLen;
    float align = clamp(dot(worldRayDir, boltDirWorld) * 0.5 + 0.5, 0.0, 1.0);
    return 0.45 + 0.85 * pow(align, 2.4);
}

float twilightAfterglow() {
    // Warmth survives sunset briefly, then fades out cleanly before night so the midnight horizon never turns brown.
    return smoothstep(-0.12, -0.02, vSunWorldDir.y)
         * (1.0 - smoothstep(0.03, 0.22, vSunWorldDir.y)) * vDaylightFactor;
}

void getLuminousCloudPalette(out vec3 cDeepFold, out vec3 cMidFold, out vec3 cWarmMid, out vec3 cSunCrest, out vec3 silverRimColor) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);

    if (STYLE_SELECTION == 0) {
        // Guofeng Ink (Shanshui): Airy celadon-jade mist undersides & warm Xuan-paper ivory crests;
        // deep nocturnal slate-charcoal clouds at midnight.
        vec3 dayDeep    = vec3(0.30, 0.41, 0.45);
        vec3 sunsetDeep = vec3(0.42, 0.32, 0.38);
        vec3 nightDeep  = vec3(0.076, 0.092, 0.124);

        vec3 dayMid     = vec3(0.58, 0.68, 0.70);
        vec3 sunsetMid  = vec3(0.74, 0.52, 0.42);
        vec3 nightMid   = vec3(0.105, 0.126, 0.168);

        vec3 dayWarm    = vec3(0.85, 0.89, 0.86);
        vec3 sunsetWarm = vec3(0.94, 0.68, 0.46);
        vec3 nightWarm  = vec3(0.134, 0.158, 0.206);

        vec3 dayCrest    = vec3(0.97, 0.96, 0.91);
        vec3 sunsetCrest = vec3(1.05, 0.82, 0.58);
        vec3 nightCrest  = vec3(0.166, 0.194, 0.248);

        cDeepFold = mix(nightDeep,  mix(dayDeep,  sunsetDeep,  vSunsetFactor), vDaylightFactor);
        cMidFold  = mix(nightMid,   mix(dayMid,   sunsetMid,   vSunsetFactor), vDaylightFactor);
        cWarmMid  = mix(nightWarm,  mix(dayWarm,  sunsetWarm,  vSunsetFactor), vDaylightFactor);
        cSunCrest = mix(nightCrest, mix(dayCrest, sunsetCrest, vSunsetFactor), vDaylightFactor);

        vec3 rainDeep  = mix(vec3(0.080, 0.096, 0.130), vec3(0.22, 0.27, 0.32), vDaylightFactor);
        vec3 rainMid   = mix(vec3(0.106, 0.126, 0.168), vec3(0.31, 0.37, 0.42), vDaylightFactor);
        vec3 rainWarm  = mix(vec3(0.132, 0.156, 0.204), vec3(0.41, 0.48, 0.52), vDaylightFactor);
        vec3 rainCrest = mix(vec3(0.160, 0.188, 0.242), vec3(0.52, 0.58, 0.62), vDaylightFactor);

        vec3 stormDeep  = mix(vec3(0.072, 0.088, 0.120), vec3(0.15, 0.19, 0.24), vDaylightFactor);
        vec3 stormMid   = mix(vec3(0.096, 0.116, 0.156), vec3(0.22, 0.27, 0.33), vDaylightFactor);
        vec3 stormWarm  = mix(vec3(0.120, 0.144, 0.190), vec3(0.30, 0.36, 0.42), vDaylightFactor);
        vec3 stormCrest = mix(vec3(0.148, 0.176, 0.228), vec3(0.39, 0.46, 0.52), vDaylightFactor);

        cDeepFold = mix(cDeepFold, mix(rainDeep,  stormDeep,  stormFactor), wetnessFactor);
        cMidFold  = mix(cMidFold,  mix(rainMid,   stormMid,   stormFactor), wetnessFactor);
        cWarmMid  = mix(cWarmMid,  mix(rainWarm,  stormWarm,  stormFactor), wetnessFactor);
        cSunCrest = mix(cSunCrest, mix(rainCrest, stormCrest, stormFactor), wetnessFactor);
        silverRimColor = mix(vec3(0.24, 0.34, 0.44), vec3(1.10, 0.96, 0.78), vDaylightFactor) * (1.0 - wetnessFactor * 0.65);
    } else {
        // Xianxia Mist (Cumulus): Rich cool cerulean-indigo shadows in daylight,
        // deep nocturnal slate-indigo clouds at midnight, and cohesive storm-slate rain canopies.
        vec3 dayDeep    = vec3(0.28, 0.38, 0.52);
        vec3 sunsetDeep = vec3(0.40, 0.30, 0.48);
        vec3 nightDeep  = vec3(0.076, 0.092, 0.126);

        vec3 dayMid     = vec3(0.56, 0.67, 0.79);
        vec3 sunsetMid  = vec3(0.78, 0.52, 0.52);
        vec3 nightMid   = vec3(0.106, 0.128, 0.172);

        vec3 dayWarm    = vec3(0.85, 0.92, 0.97);
        vec3 sunsetWarm = vec3(0.98, 0.68, 0.50);
        vec3 nightWarm  = vec3(0.136, 0.162, 0.212);

        vec3 dayCrest    = vec3(1.02, 1.00, 0.98);
        vec3 sunsetCrest = vec3(1.12, 0.86, 0.62);
        vec3 nightCrest  = vec3(0.168, 0.198, 0.256);

        cDeepFold = mix(nightDeep,  mix(dayDeep,  sunsetDeep,  vSunsetFactor), vDaylightFactor);
        cMidFold  = mix(nightMid,   mix(dayMid,   sunsetMid,   vSunsetFactor), vDaylightFactor);
        cWarmMid  = mix(nightWarm,  mix(dayWarm,  sunsetWarm,  vSunsetFactor), vDaylightFactor);
        cSunCrest = mix(nightCrest, mix(dayCrest, sunsetCrest, vSunsetFactor), vDaylightFactor);

        vec3 rainDeep  = mix(vec3(0.080, 0.096, 0.132), vec3(0.20, 0.26, 0.34), vDaylightFactor);
        vec3 rainMid   = mix(vec3(0.106, 0.128, 0.172), vec3(0.29, 0.37, 0.46), vDaylightFactor);
        vec3 rainWarm  = mix(vec3(0.132, 0.158, 0.208), vec3(0.39, 0.48, 0.57), vDaylightFactor);
        vec3 rainCrest = mix(vec3(0.162, 0.190, 0.246), vec3(0.50, 0.59, 0.68), vDaylightFactor);

        vec3 stormDeep  = mix(vec3(0.072, 0.088, 0.122), vec3(0.14, 0.19, 0.26), vDaylightFactor);
        vec3 stormMid   = mix(vec3(0.096, 0.116, 0.158), vec3(0.21, 0.27, 0.36), vDaylightFactor);
        vec3 stormWarm  = mix(vec3(0.122, 0.146, 0.194), vec3(0.29, 0.37, 0.46), vDaylightFactor);
        vec3 stormCrest = mix(vec3(0.150, 0.178, 0.232), vec3(0.38, 0.47, 0.56), vDaylightFactor);

        cDeepFold = mix(cDeepFold, mix(rainDeep,  stormDeep,  stormFactor), wetnessFactor);
        cMidFold  = mix(cMidFold,  mix(rainMid,   stormMid,   stormFactor), wetnessFactor);
        cWarmMid  = mix(cWarmMid,  mix(rainWarm,  stormWarm,  stormFactor), wetnessFactor);
        cSunCrest = mix(cSunCrest, mix(rainCrest, stormCrest, stormFactor), wetnessFactor);
        silverRimColor = mix(vec3(0.26, 0.38, 0.52), vec3(1.14, 1.04, 0.90), vDaylightFactor) * (1.0 - wetnessFactor * 0.65);
    }
    float afterglow = twilightAfterglow() * (1.0 - wetnessFactor * 0.85);
    vec3 duskTint = (STYLE_SELECTION == 0) ? vec3(0.62, 0.34, 0.23) : vec3(0.72, 0.35, 0.30);
    cWarmMid = mix(cWarmMid, duskTint * 0.72, afterglow * 0.30);
    cSunCrest = mix(cSunCrest, duskTint, afterglow * 0.38);

    // Full-Dome Biome Cloud Palette Replacement (Clear, Rain, & Storm):
    // Shift all 4 cloud registers (cDeepFold, cMidFold, cWarmMid, cSunCrest) and silverRimColor
    // into the active biome's color world across both clear and rainy weather so clouds never clash!
    float bCloudGate = mix(0.36, 1.0, vDaylightFactor) * mix(1.0, 0.78, wetnessFactor);
    float wRainDamp  = mix(1.0, 0.68, wetnessFactor) * mix(1.0, 0.76, stormFactor);
    float wBamboo, wMountain, wCherry, wSnowy, wArid, wSwamp;
    evaluateSmoothBiomeWeights(wBamboo, wMountain, wCherry, wSnowy, wArid, wSwamp);
    float altitudeMountainHint = smoothstep(110.0, 160.0, eyeAltitude);
    wMountain = clamp(max(wMountain, altitudeMountainHint * 0.55 * BIOME_TINT_STRENGTH), 0.0, 1.0);

    if (wBamboo > 0.001) {
        cDeepFold = mix(cDeepFold, mix(vec3(0.04, 0.09, 0.07), vec3(0.18, 0.42, 0.31) * wRainDamp, vDaylightFactor), wBamboo * 0.84 * bCloudGate);
        cMidFold  = mix(cMidFold,  mix(vec3(0.07, 0.14, 0.11), vec3(0.38, 0.66, 0.50) * wRainDamp, vDaylightFactor), wBamboo * 0.80 * bCloudGate);
        cWarmMid  = mix(cWarmMid,  mix(vec3(0.10, 0.18, 0.15), vec3(0.62, 0.84, 0.70) * wRainDamp, vDaylightFactor), wBamboo * 0.74 * bCloudGate);
        cSunCrest = mix(cSunCrest, mix(vec3(0.13, 0.22, 0.18), vec3(0.78, 0.94, 0.82) * wRainDamp, vDaylightFactor), wBamboo * 0.68 * bCloudGate);
        silverRimColor = mix(silverRimColor, vec3(0.66, 0.90, 0.76) * mix(0.28, 1.0, vDaylightFactor), wBamboo * 0.70 * bCloudGate);
    }
    if (wMountain > 0.001) {
        cDeepFold = mix(cDeepFold, mix(vec3(0.05, 0.07, 0.09), vec3(0.32, 0.40, 0.46) * wRainDamp, vDaylightFactor), wMountain * 0.78 * bCloudGate);
        cMidFold  = mix(cMidFold,  mix(vec3(0.08, 0.10, 0.13), vec3(0.54, 0.62, 0.68) * wRainDamp, vDaylightFactor), wMountain * 0.74 * bCloudGate);
        cWarmMid  = mix(cWarmMid,  mix(vec3(0.11, 0.14, 0.17), vec3(0.74, 0.80, 0.84) * wRainDamp, vDaylightFactor), wMountain * 0.68 * bCloudGate);
        cSunCrest = mix(cSunCrest, mix(vec3(0.14, 0.18, 0.21), vec3(0.88, 0.92, 0.95) * wRainDamp, vDaylightFactor), wMountain * 0.62 * bCloudGate);
        silverRimColor = mix(silverRimColor, vec3(0.80, 0.86, 0.92) * mix(0.28, 1.0, vDaylightFactor), wMountain * 0.65 * bCloudGate);
    }
    if (wCherry > 0.001) {
        cDeepFold = mix(cDeepFold, mix(vec3(0.08, 0.06, 0.10), vec3(0.46, 0.32, 0.44) * wRainDamp, vDaylightFactor), wCherry * 0.86 * bCloudGate);
        cMidFold  = mix(cMidFold,  mix(vec3(0.12, 0.09, 0.14), vec3(0.72, 0.52, 0.66) * wRainDamp, vDaylightFactor), wCherry * 0.82 * bCloudGate);
        cWarmMid  = mix(cWarmMid,  mix(vec3(0.16, 0.12, 0.18), vec3(0.90, 0.72, 0.82) * wRainDamp, vDaylightFactor), wCherry * 0.76 * bCloudGate);
        cSunCrest = mix(cSunCrest, mix(vec3(0.20, 0.15, 0.22), vec3(0.98, 0.84, 0.90) * wRainDamp, vDaylightFactor), wCherry * 0.70 * bCloudGate);
        silverRimColor = mix(silverRimColor, vec3(0.96, 0.78, 0.86) * mix(0.28, 1.0, vDaylightFactor), wCherry * 0.72 * bCloudGate);
    }
    if (wSnowy > 0.001) {
        cDeepFold = mix(cDeepFold, mix(vec3(0.07, 0.08, 0.12), vec3(0.42, 0.48, 0.58) * wRainDamp, vDaylightFactor), wSnowy * 0.82 * bCloudGate);
        cMidFold  = mix(cMidFold,  mix(vec3(0.10, 0.12, 0.17), vec3(0.66, 0.72, 0.82) * wRainDamp, vDaylightFactor), wSnowy * 0.78 * bCloudGate);
        cWarmMid  = mix(cWarmMid,  mix(vec3(0.13, 0.16, 0.21), vec3(0.82, 0.87, 0.94) * wRainDamp, vDaylightFactor), wSnowy * 0.72 * bCloudGate);
        cSunCrest = mix(cSunCrest, mix(vec3(0.16, 0.20, 0.26), vec3(0.92, 0.95, 0.99) * wRainDamp, vDaylightFactor), wSnowy * 0.66 * bCloudGate);
        silverRimColor = mix(silverRimColor, vec3(0.88, 0.92, 0.98) * mix(0.28, 1.0, vDaylightFactor), wSnowy * 0.70 * bCloudGate);
    }
    if (wArid > 0.001) {
        cDeepFold = mix(cDeepFold, mix(vec3(0.08, 0.07, 0.05), vec3(0.48, 0.38, 0.25) * wRainDamp, vDaylightFactor), wArid * 0.86 * bCloudGate);
        cMidFold  = mix(cMidFold,  mix(vec3(0.12, 0.10, 0.08), vec3(0.74, 0.59, 0.39) * wRainDamp, vDaylightFactor), wArid * 0.82 * bCloudGate);
        cWarmMid  = mix(cWarmMid,  mix(vec3(0.16, 0.13, 0.10), vec3(0.90, 0.75, 0.52) * wRainDamp, vDaylightFactor), wArid * 0.76 * bCloudGate);
        cSunCrest = mix(cSunCrest, mix(vec3(0.20, 0.17, 0.12), vec3(0.98, 0.86, 0.64) * wRainDamp, vDaylightFactor), wArid * 0.70 * bCloudGate);
        silverRimColor = mix(silverRimColor, vec3(0.98, 0.82, 0.56) * mix(0.28, 1.0, vDaylightFactor), wArid * 0.72 * bCloudGate);
    }
    if (wSwamp > 0.001) {
        cDeepFold = mix(cDeepFold, mix(vec3(0.04, 0.07, 0.04), vec3(0.22, 0.30, 0.18) * wRainDamp, vDaylightFactor), wSwamp * 0.88 * bCloudGate);
        cMidFold  = mix(cMidFold,  mix(vec3(0.07, 0.10, 0.07), vec3(0.38, 0.46, 0.30) * wRainDamp, vDaylightFactor), wSwamp * 0.84 * bCloudGate);
        cWarmMid  = mix(cWarmMid,  mix(vec3(0.10, 0.13, 0.09), vec3(0.54, 0.62, 0.44) * wRainDamp, vDaylightFactor), wSwamp * 0.78 * bCloudGate);
        cSunCrest = mix(cSunCrest, mix(vec3(0.13, 0.17, 0.12), vec3(0.68, 0.74, 0.56) * wRainDamp, vDaylightFactor), wSwamp * 0.72 * bCloudGate);
        silverRimColor = mix(silverRimColor, vec3(0.70, 0.78, 0.56) * mix(0.28, 1.0, vDaylightFactor), wSwamp * 0.74 * bCloudGate);
    }

    float wPaleGarden = evaluatePaleGardenWeight();
    if (wPaleGarden > 0.001) {
        vec3 paleDeep  = mix(vec3(0.068, 0.068, 0.072), vec3(0.25, 0.24, 0.23), vDaylightFactor);
        vec3 paleMid   = mix(vec3(0.095, 0.095, 0.100), vec3(0.37, 0.36, 0.35), vDaylightFactor);
        vec3 paleWarm  = mix(vec3(0.118, 0.118, 0.124), vec3(0.46, 0.44, 0.43), vDaylightFactor);
        vec3 paleCrest = mix(vec3(0.145, 0.145, 0.152), vec3(0.55, 0.53, 0.51), vDaylightFactor);
        cDeepFold = mix(cDeepFold, paleDeep,  wPaleGarden * 0.96);
        cMidFold  = mix(cMidFold,  paleMid,   wPaleGarden * 0.96);
        cWarmMid  = mix(cWarmMid,  paleWarm,  wPaleGarden * 0.96);
        cSunCrest = mix(cSunCrest, paleCrest, wPaleGarden * 0.94);
        silverRimColor = mix(silverRimColor, vec3(0.58, 0.56, 0.54) * mix(0.28, 1.0, vDaylightFactor), wPaleGarden * 0.92);
    }
}

void applyCelestialCloudGlow(vec3 worldRayDir, float thinnessFactor, inout vec3 cloudColor) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);
    float clearFactor = pow(clamp(1.0 - wetnessFactor * 0.96, 0.0, 1.0), 2.0) * (1.0 - stormFactor * 0.96);

    float cosSun  = max(dot(worldRayDir, vSunWorldDir), 0.0);
    float cosMoon = max(dot(worldRayDir, vMoonWorldDir), 0.0);

    float pgGlowDamp = 1.0 - evaluatePaleGardenWeight() * 0.86;
    clearFactor *= pgGlowDamp;
    if (vDaylightFactor > 0.01 && clearFactor > 0.001) {
        float sunZoneWide = pow(cosSun, (STYLE_SELECTION == 0 ? 5.0 : 4.0)) * vDaylightFactor;
        float sunZoneMid  = pow(cosSun, (STYLE_SELECTION == 0 ? 14.0 : 10.0)) * vDaylightFactor;
        float sunZoneCore = pow(cosSun, (STYLE_SELECTION == 0 ? 42.0 : 32.0)) * vDaylightFactor;

        float cBam, cMtn, cChr, cSnw, cArd, cSwp;
        evaluateSmoothBiomeWeights(cBam, cMtn, cChr, cSnw, cArd, cSwp);
        vec3 dayGlowWide = (STYLE_SELECTION == 0)
            ? mix(vec3(0.98, 0.76, 0.46), vec3(1.06, 0.58, 0.30), vSunsetFactor)
            : mix(vec3(1.04, 0.86, 0.58), vec3(1.12, 0.64, 0.36), vSunsetFactor);
        vec3 dayGlowCore = (STYLE_SELECTION == 0) ? vec3(1.08, 0.90, 0.60) : vec3(1.16, 0.96, 0.70);

        // Harmonize solar cloud silver-lining with active biome skybox palette
        dayGlowWide = mix(dayGlowWide, vec3(0.76, 0.84, 0.58), cSwp * 0.65);
        dayGlowWide = mix(dayGlowWide, vec3(0.68, 0.88, 0.72), cBam * 0.60);
        dayGlowWide = mix(dayGlowWide, vec3(0.96, 0.74, 0.84), cChr * 0.65);
        dayGlowWide = mix(dayGlowWide, vec3(0.86, 0.90, 0.96), cSnw * 0.60);
        dayGlowWide = mix(dayGlowWide, vec3(0.78, 0.84, 0.88), cMtn * 0.50);

        cloudColor = mix(cloudColor, max(cloudColor, dayGlowWide * clearFactor), sunZoneWide * 0.48 * clearFactor);
        cloudColor += dayGlowWide * (sunZoneMid * 0.42) * thinnessFactor * clearFactor;
        cloudColor += mix(dayGlowCore, dayGlowWide * 1.12, max(max(cSwp, cBam), max(cChr, cSnw)) * 0.55) * (sunZoneCore * 0.58) * thinnessFactor * clearFactor;
    }

    if (vNightFactor > 0.01 && clearFactor > 0.001) {
        float moonWideZone = pow(cosMoon, 5.0) * vNightFactor * clearFactor;
        float moonRimZone  = pow(cosMoon, 24.0) * vNightFactor * clearFactor;
        vec3 moonRimTint   = (STYLE_SELECTION == 0) ? vec3(0.58, 0.68, 0.60) : vec3(0.42, 0.64, 0.92);
        cloudColor += moonRimTint * (moonWideZone * 0.16 + moonRimZone * 0.38 * thinnessFactor) * clearFactor;
    }

    if (lightningFlash > 0.001) {
        float dirBoost = computeLightningDirectionalBoost(worldRayDir);
        vec3 boltTint  = (STYLE_SELECTION == 0) ? vec3(0.62, 0.76, 0.84) : vec3(0.60, 0.78, 1.08);
        cloudColor += boltTint * (lightningFlash * dirBoost * (0.28 + 0.38 * thinnessFactor));
    }
}

vec3 evaluateUnifiedSky(vec3 worldRayDir, vec3 viewRayDir) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);

    float VdotU = clamp(worldRayDir.y, -1.0, 1.0);
    float VdotS = dot(viewRayDir, vSunViewDir);
    float VdotM = dot(viewRayDir, vMoonViewDir);

    float altitudeMountainHint = smoothstep(110.0, 160.0, eyeAltitude);
    float bambooWeight, mountainWeight, cherryWeight, snowyWeight, aridWeight, swampWeight;
    evaluateSmoothBiomeWeights(bambooWeight, mountainWeight, cherryWeight, snowyWeight, aridWeight, swampWeight);
    mountainWeight = clamp(max(mountainWeight, altitudeMountainHint * 0.55 * BIOME_TINT_STRENGTH), 0.0, 1.0);

    vec3 zenithCol, midCol, horizonCol;

    if (STYLE_SELECTION == 0) {
        vec3 noonZenith    = vec3(0.28, 0.48, 0.58);
        vec3 noonMid       = vec3(0.46, 0.60, 0.64);
        vec3 noonHorizon   = vec3(0.64, 0.70, 0.68);

        vec3 sunsetZenith  = vec3(0.18, 0.28, 0.42);
        vec3 sunsetMid     = vec3(0.68, 0.44, 0.34);
        vec3 sunsetHorizon = vec3(0.84, 0.54, 0.36);

        vec3 nightZenith   = vec3(0.058, 0.072, 0.102);
        vec3 nightMid      = vec3(0.086, 0.106, 0.144);
        vec3 nightHorizon  = vec3(0.128, 0.154, 0.198);

        zenithCol  = mix(nightZenith,  mix(noonZenith,  sunsetZenith,  vSunsetFactor), vDaylightFactor);
        midCol     = mix(nightMid,     mix(noonMid,     sunsetMid,     vSunsetFactor), vDaylightFactor);
        horizonCol = mix(nightHorizon, mix(noonHorizon, sunsetHorizon, vSunsetFactor), vDaylightFactor);

        vec3 rainZenith   = mix(vec3(0.082, 0.098, 0.134), vec3(0.22, 0.28, 0.33), vDaylightFactor);
        vec3 rainMid      = mix(vec3(0.108, 0.128, 0.170), vec3(0.30, 0.37, 0.42), vDaylightFactor);
        vec3 rainHorizon  = mix(vec3(0.142, 0.168, 0.216), vec3(0.34, 0.41, 0.45), vDaylightFactor);

        vec3 stormZenith  = mix(vec3(0.074, 0.090, 0.124), vec3(0.15, 0.20, 0.25), vDaylightFactor);
        vec3 stormMid     = mix(vec3(0.098, 0.118, 0.160), vec3(0.22, 0.28, 0.34), vDaylightFactor);
        vec3 stormHorizon = mix(vec3(0.132, 0.158, 0.206), vec3(0.26, 0.32, 0.38), vDaylightFactor);

        zenithCol  = mix(zenithCol,  mix(rainZenith,  stormZenith,  stormFactor), wetnessFactor);
        midCol     = mix(midCol,     mix(rainMid,     stormMid,     stormFactor), wetnessFactor);
        horizonCol = mix(horizonCol, mix(rainHorizon, stormHorizon, stormFactor), wetnessFactor);
    } else {
        vec3 noonZenith    = vec3(0.14, 0.44, 0.76);
        vec3 noonMid       = vec3(0.32, 0.64, 0.86);
        vec3 noonHorizon   = vec3(0.68, 0.84, 0.92);

        vec3 sunsetZenith  = vec3(0.14, 0.22, 0.52);
        vec3 sunsetMid     = vec3(0.78, 0.44, 0.48);
        vec3 sunsetHorizon = vec3(0.98, 0.64, 0.42);

        vec3 nightZenith   = vec3(0.056, 0.070, 0.102);
        vec3 nightMid      = vec3(0.084, 0.104, 0.144);
        vec3 nightHorizon  = vec3(0.126, 0.152, 0.198);

        zenithCol  = mix(nightZenith,  mix(noonZenith,  sunsetZenith,  vSunsetFactor), vDaylightFactor);
        midCol     = mix(nightMid,     mix(noonMid,     sunsetMid,     vSunsetFactor), vDaylightFactor);
        horizonCol = mix(nightHorizon, mix(noonHorizon, sunsetHorizon, vSunsetFactor), vDaylightFactor);

        vec3 rainZenith   = mix(vec3(0.080, 0.096, 0.134), vec3(0.20, 0.27, 0.35), vDaylightFactor);
        vec3 rainMid      = mix(vec3(0.106, 0.128, 0.172), vec3(0.28, 0.37, 0.46), vDaylightFactor);
        vec3 rainHorizon  = mix(vec3(0.140, 0.168, 0.218), vec3(0.32, 0.41, 0.50), vDaylightFactor);

        vec3 stormZenith  = mix(vec3(0.072, 0.088, 0.124), vec3(0.14, 0.19, 0.26), vDaylightFactor);
        vec3 stormMid     = mix(vec3(0.096, 0.118, 0.160), vec3(0.21, 0.27, 0.36), vDaylightFactor);
        vec3 stormHorizon = mix(vec3(0.130, 0.156, 0.206), vec3(0.25, 0.32, 0.40), vDaylightFactor);

        zenithCol  = mix(zenithCol,  mix(rainZenith,  stormZenith,  stormFactor), wetnessFactor);
        midCol     = mix(midCol,     mix(rainMid,     stormMid,     stormFactor), wetnessFactor);
        horizonCol = mix(horizonCol, mix(rainHorizon, stormHorizon, stormFactor), wetnessFactor);
    }

    // (Removed raw skyColor/fogColor ratio multiplier to prevent red flickers & forest greening)

    // Full-Dome Biome Skybox Palette Replacement:
    // Each biome genuinely transforms the entire sky dome (horizonCol, midCol, AND zenithCol)
    // into its own distinct color palette across clear, rain, and storm weather.
    float biomeWeatherKeep = 1.0 - wetnessFactor * 0.25;
    float skyRainDim       = mix(1.0, 0.56, wetnessFactor) * mix(1.0, 0.72, stormFactor);
    float biomeDomeStrength = mix(0.32, 1.0, smoothstep(0.05, 0.65, vDaylightFactor)) * biomeWeatherKeep;

    // 1. Bamboo / Jungle: Lush tropical emerald-jade dome (Green > Blue across horizon, mid, and zenith)
    if (bambooWeight > 0.001) {
        vec3 bamHor = mix(vec3(0.042, 0.088, 0.072), ((STYLE_SELECTION == 0) ? vec3(0.48, 0.78, 0.58) : vec3(0.40, 0.82, 0.62)) * skyRainDim, vDaylightFactor);
        vec3 bamMid = mix(vec3(0.030, 0.068, 0.058), ((STYLE_SELECTION == 0) ? vec3(0.28, 0.62, 0.46) : vec3(0.22, 0.66, 0.50)) * skyRainDim, vDaylightFactor);
        vec3 bamZen = mix(vec3(0.020, 0.048, 0.044), ((STYLE_SELECTION == 0) ? vec3(0.16, 0.44, 0.32) : vec3(0.12, 0.46, 0.36)) * skyRainDim, vDaylightFactor);
        horizonCol = mix(horizonCol, bamHor, bambooWeight * 0.88 * biomeDomeStrength);
        midCol     = mix(midCol,     bamMid, bambooWeight * 0.86 * biomeDomeStrength);
        zenithCol  = mix(zenithCol,  bamZen, bambooWeight * 0.84 * biomeDomeStrength);
    }

    // 2. Mountain / Windswept: Crisp high-altitude slate-silver dome
    if (mountainWeight > 0.001) {
        vec3 mtnHor = mix(vec3(0.058, 0.072, 0.096), ((STYLE_SELECTION == 0) ? vec3(0.70, 0.76, 0.78) : vec3(0.66, 0.74, 0.82)) * skyRainDim, vDaylightFactor);
        vec3 mtnMid = mix(vec3(0.044, 0.056, 0.078), ((STYLE_SELECTION == 0) ? vec3(0.48, 0.56, 0.60) : vec3(0.44, 0.54, 0.66)) * skyRainDim, vDaylightFactor);
        vec3 mtnZen = mix(vec3(0.032, 0.042, 0.062), ((STYLE_SELECTION == 0) ? vec3(0.30, 0.38, 0.44) : vec3(0.26, 0.36, 0.48)) * skyRainDim, vDaylightFactor);
        horizonCol = mix(horizonCol, mtnHor, mountainWeight * 0.82 * biomeDomeStrength);
        midCol     = mix(midCol,     mtnMid, mountainWeight * 0.78 * biomeDomeStrength);
        zenithCol  = mix(zenithCol,  mtnZen, mountainWeight * 0.75 * biomeDomeStrength);
    }

    // 3. Cherry Grove: Full sakura rose-plum / blossom-lavender sky dome (no sky-blue upper dome)
    if (cherryWeight > 0.001) {
        vec3 chrHor = mix(vec3(0.082, 0.060, 0.096), ((STYLE_SELECTION == 0) ? vec3(0.92, 0.70, 0.78) : vec3(0.95, 0.68, 0.82)) * skyRainDim, vDaylightFactor);
        vec3 chrMid = mix(vec3(0.062, 0.044, 0.078), ((STYLE_SELECTION == 0) ? vec3(0.74, 0.52, 0.64) : vec3(0.78, 0.50, 0.68)) * skyRainDim, vDaylightFactor);
        vec3 chrZen = mix(vec3(0.044, 0.030, 0.058), ((STYLE_SELECTION == 0) ? vec3(0.50, 0.34, 0.46) : vec3(0.52, 0.32, 0.50)) * skyRainDim, vDaylightFactor);
        horizonCol = mix(horizonCol, chrHor, cherryWeight * 0.90 * biomeDomeStrength);
        midCol     = mix(midCol,     chrMid, cherryWeight * 0.88 * biomeDomeStrength);
        zenithCol  = mix(zenithCol,  chrZen, cherryWeight * 0.86 * biomeDomeStrength);
    }

    // 4. Snowy / Glacial: Crisp winter frost-silver & pale periwinkle-ice sky dome
    if (snowyWeight > 0.001) {
        vec3 snwHor = mix(vec3(0.068, 0.080, 0.110), ((STYLE_SELECTION == 0) ? vec3(0.84, 0.88, 0.92) : vec3(0.86, 0.88, 0.96)) * skyRainDim, vDaylightFactor);
        vec3 snwMid = mix(vec3(0.052, 0.062, 0.088), ((STYLE_SELECTION == 0) ? vec3(0.66, 0.72, 0.78) : vec3(0.68, 0.72, 0.84)) * skyRainDim, vDaylightFactor);
        vec3 snwZen = mix(vec3(0.038, 0.046, 0.068), ((STYLE_SELECTION == 0) ? vec3(0.46, 0.52, 0.60) : vec3(0.46, 0.50, 0.66)) * skyRainDim, vDaylightFactor);
        horizonCol = mix(horizonCol, snwHor, snowyWeight * 0.88 * biomeDomeStrength);
        midCol     = mix(midCol,     snwMid, snowyWeight * 0.85 * biomeDomeStrength);
        zenithCol  = mix(zenithCol,  snwZen, snowyWeight * 0.82 * biomeDomeStrength);
    }

    // 5. Arid / Desert / Savanna / Badlands: Full desert sand-gold & warm ochre sky dome (R > G > B everywhere)
    if (aridWeight > 0.001) {
        vec3 ardHor = mix(vec3(0.078, 0.064, 0.048), ((STYLE_SELECTION == 0) ? vec3(0.92, 0.74, 0.46) : vec3(0.96, 0.76, 0.48)) * skyRainDim, vDaylightFactor);
        vec3 ardMid = mix(vec3(0.058, 0.048, 0.036), ((STYLE_SELECTION == 0) ? vec3(0.74, 0.58, 0.36) : vec3(0.78, 0.60, 0.38)) * skyRainDim, vDaylightFactor);
        vec3 ardZen = mix(vec3(0.042, 0.034, 0.026), ((STYLE_SELECTION == 0) ? vec3(0.50, 0.40, 0.26) : vec3(0.52, 0.42, 0.28)) * skyRainDim, vDaylightFactor);
        horizonCol = mix(horizonCol, ardHor, aridWeight * 0.90 * biomeDomeStrength);
        midCol     = mix(midCol,     ardMid, aridWeight * 0.88 * biomeDomeStrength);
        zenithCol  = mix(zenithCol,  ardZen, aridWeight * 0.86 * biomeDomeStrength);
    }

    // 6. Swamp & Mangrove Swamp: Full murky willow-moss / peat-olive sky dome (Green & Olive > Blue from horizon to zenith!)
    if (swampWeight > 0.001) {
        vec3 swpHor = mix(vec3(0.044, 0.064, 0.042), ((STYLE_SELECTION == 0) ? vec3(0.48, 0.56, 0.36) : vec3(0.46, 0.58, 0.38)) * skyRainDim, vDaylightFactor);
        vec3 swpMid = mix(vec3(0.032, 0.048, 0.030), ((STYLE_SELECTION == 0) ? vec3(0.34, 0.42, 0.26) : vec3(0.32, 0.44, 0.28)) * skyRainDim, vDaylightFactor);
        vec3 swpZen = mix(vec3(0.022, 0.034, 0.020), ((STYLE_SELECTION == 0) ? vec3(0.20, 0.28, 0.16) : vec3(0.18, 0.30, 0.18)) * skyRainDim, vDaylightFactor);
        horizonCol = mix(horizonCol, swpHor, swampWeight * 0.92 * biomeDomeStrength);
        midCol     = mix(midCol,     swpMid, swampWeight * 0.90 * biomeDomeStrength);
        zenithCol  = mix(zenithCol,  swpZen, swampWeight * 0.88 * biomeDomeStrength);
    }

    // 7. Pale Garden: Full desaturated ashen pewter-slate dome at all hours (including sunrise/moonrise/sunset)
    float paleGardenW = evaluatePaleGardenWeight();
    if (paleGardenW > 0.001) {
        vec3 paleDayHor = mix(vec3(0.46, 0.44, 0.42), vec3(0.50, 0.45, 0.41), vSunsetFactor * 0.45);
        vec3 paleDayMid = mix(vec3(0.36, 0.35, 0.34), vec3(0.39, 0.36, 0.34), vSunsetFactor * 0.40);
        vec3 paleDayZen = mix(vec3(0.26, 0.26, 0.27), vec3(0.28, 0.26, 0.26), vSunsetFactor * 0.35);
        vec3 paleHorizon = mix(vec3(0.088, 0.088, 0.092), paleDayHor, vDaylightFactor);
        vec3 paleMid     = mix(vec3(0.068, 0.068, 0.072), paleDayMid, vDaylightFactor);
        vec3 paleZenith  = mix(vec3(0.048, 0.048, 0.052), paleDayZen, vDaylightFactor);
        horizonCol = mix(horizonCol, paleHorizon, paleGardenW * 0.98);
        midCol     = mix(midCol,     paleMid,     paleGardenW * 0.98);
        zenithCol  = mix(zenithCol,  paleZenith,  paleGardenW * 0.98);
    }

    // Extend the continuous sky dome gradient smoothly down to VdotU = -0.18 so elevated cameras
    // looking down toward distant ocean/terrain horizons never see a flat horizontal cutoff line at VdotU = 0.0!
    float upFactor = clamp(VdotU, 0.0, 1.0);
    float skyElev  = clamp((VdotU + 0.18) / 1.18, 0.0, 1.0);
    float midCurve = pow(1.0 - skyElev, 2.2);
    float subH = clamp((-VdotU - 0.08) * 1.45, 0.0, 1.0) * (1.0 - paleGardenW * 0.96);
    float horCurve = (VdotU >= -0.08)
        ? pow(1.0 - clamp((VdotU + 0.08) / 0.86, 0.0, 1.0), 2.8)
        : pow(1.0 - subH, 2.0);

    vec3 sky = mix(zenithCol, midCol, midCurve);
    sky = mix(sky, horizonCol, horCurve);

    if (VdotU < -0.08) {
        float subHorizonHold = (1.0 - smoothstep(-0.52, -0.08, VdotU)) * (1.0 - paleGardenW * 0.96);
        vec3 nadirMist = mix(horizonCol * 0.88 + midCol * 0.14, horizonCol * 0.92, vDaylightFactor);
        sky = mix(horizonCol, nadirMist, subHorizonHold);
    }

    vec2 rayXZ = worldRayDir.xz / max(length(worldRayDir.xz), 0.001);
    vec2 sunXZ = vSunWorldDir.xz / max(length(vSunWorldDir.xz), 0.001);
    float sunsetSide = pow(max(dot(rayXZ, sunXZ), 0.0), 1.6);
    float biomeDuskDamp = 1.0 - max(paleGardenW * 0.96, max(swampWeight * 0.70, cherryWeight * 0.55));
    float duskBand = exp(-pow((VdotU + 0.02) * 2.2, 2.0)) * sunsetSide * biomeDuskDamp;
    vec3 duskHorizon = (STYLE_SELECTION == 0) ? vec3(0.62, 0.29, 0.15) : vec3(0.72, 0.30, 0.21);
    sky = mix(sky, duskHorizon, twilightAfterglow() * duskBand * (1.0 - wetnessFactor * 0.85) * 0.36);

    float rayHorizonGate = smoothstep(-0.26, 0.04, VdotU);
    float sunElevGate    = smoothstep(-0.24, 0.08, vSunWorldDir.y) * rayHorizonGate;
    float moonElevGate   = smoothstep(-0.24, 0.08, vMoonWorldDir.y) * rayHorizonGate;

    float sunGlare  = pow(clamp(VdotS, 0.0, 1.0), (STYLE_SELECTION == 0 ? 18.0 : 14.0)) * (STYLE_SELECTION == 0 ? 0.15 : 0.18) * sunElevGate;
    float moonGlare = pow(clamp(VdotM, 0.0, 1.0), 14.0) * 0.12 * moonElevGate;
    vec3 skyChromaGlare = clamp(sky / max(dot(sky, vec3(0.2126, 0.7152, 0.0722)), 0.045), vec3(0.55), vec3(1.45));
    float glareBiomeW   = clamp(max(max(max(bambooWeight, mountainWeight), max(cherryWeight, snowyWeight)), max(aridWeight, swampWeight)), 0.0, 1.0);
    vec3 sunGlareCol = (STYLE_SELECTION == 0)
        ? mix(vec3(0.98, 0.76, 0.42), vec3(1.04, 0.50, 0.24), vSunsetFactor)
        : mix(vec3(1.00, 0.85, 0.58), vec3(1.10, 0.58, 0.30), vSunsetFactor);
    sunGlareCol = mix(sunGlareCol, sunGlareCol * skyChromaGlare, glareBiomeW * 0.72);
    vec3 moonGlareCol = (STYLE_SELECTION == 0) ? vec3(0.58, 0.66, 0.58) : vec3(0.42, 0.64, 0.88);
    moonGlareCol = mix(moonGlareCol, moonGlareCol * skyChromaGlare, glareBiomeW * 0.70);

    float clearSkyGlare = pow(clamp(1.0 - wetnessFactor * 0.98, 0.0, 1.0), 2.0) * (1.0 - stormFactor * 0.98) * (1.0 - paleGardenW * 0.94);
    sky += (sunGlareCol * sunGlare + moonGlareCol * moonGlare) * clearSkyGlare;

    if (lightningFlash > 0.001) {
        float dirBoost = computeLightningDirectionalBoost(worldRayDir);
        vec3 flashSkyCol = (STYLE_SELECTION == 0) ? vec3(0.48, 0.60, 0.68) : vec3(0.46, 0.62, 0.88);
        sky += flashSkyCol * (lightningFlash * dirBoost * (0.22 + 0.24 * (1.0 - upFactor * 0.5)));
    }
    if (inTheEnd > 0.001) {
        sky = mix(sky, evaluateYunMengEndBaseSky(worldRayDir), clamp(inTheEnd, 0.0, 1.0));
    }
    return sky;
}

float applyTexturedCelestialBodies(inout vec3 skyRadiance, vec3 worldRayDir) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);
    float overcastTrans = pow(clamp(1.0 - wetnessFactor * 0.98, 0.0, 1.0), 2.2) * (1.0 - stormFactor * 0.98);
    if (overcastTrans <= 0.002) return 0.0;

    // Evaluate active biome weights & Pale Garden state so Sun & Moon harmonize naturally with every biome skybox
    float bBam, bMtn, bChr, bSnw, bArd, bSwp;
    evaluateSmoothBiomeWeights(bBam, bMtn, bChr, bSnw, bArd, bSwp);
    float bPale = evaluatePaleGardenWeight();
    float biomeAtmWeight = clamp(max(max(max(bBam, bMtn), max(bChr, bSnw)), max(max(bArd, bSwp), bPale)), 0.0, 1.0);

    vec3 bgSky       = max(skyRadiance, vec3(0.001));
    float bgLuma     = dot(bgSky, vec3(0.2126, 0.7152, 0.0722));
    vec3 skyChroma   = clamp(bgSky / max(bgLuma, 0.045), vec3(0.55), vec3(1.45));

    // Shared size control with per-style fitting for the detailed artwork.
    const float sunStyleScale = 1.10;
    float sunAngularScale  = 0.082 * SUN_SIZE * sunStyleScale;
    float moonAngularScale = 0.088 * SUN_SIZE;
    float celestialDiscMask = 0.0;

    // Never slice the Sun or Moon in mid-air at worldRayDir.y = 0.0!
    // Because applyTexturedCelestialBodies only runs on unoccluded sky pixels (depth0 >= 0.999999),
    // actual terrain and water naturally occlude the rising/setting Sun and Moon just like Vanilla Minecraft.
    float rayHorizonVis  = smoothstep(-0.36, -0.14, worldRayDir.y);
    if (rayHorizonVis <= 0.001) return 0.0;

    float sunHaze  = mix(0.72, 1.0, smoothstep(-0.08, 0.22, vSunWorldDir.y));
    float moonHaze = mix(0.74, 1.0, smoothstep(-0.08, 0.22, vMoonWorldDir.y));
    float horizonMistVeil = (1.0 - smoothstep(-0.04, 0.24, worldRayDir.y)) * (0.28 + 0.24 * biomeAtmWeight + 0.26 * bPale);
    float sunHorizonVis  = smoothstep(-0.28, -0.10, vSunWorldDir.y) * rayHorizonVis * sunHaze;
    float moonHorizonVis = smoothstep(-0.28, -0.10, vMoonWorldDir.y) * rayHorizonVis * moonHaze;

    float cosSun = dot(worldRayDir, vSunWorldDir);
    float sunSupportRadius = min(0.096 * SUN_SIZE * sunStyleScale * 2.8, 0.99);
    if (cosSun > sqrt(1.0 - sunSupportRadius * sunSupportRadius) && sunHorizonVis > 0.001) {
        // Keep the artwork upright in the world sky; orbit/light directions
        // remain unchanged. The fallback only handles an overhead singularity.
        vec3 poleAxis = abs(vSunWorldDir.y) > 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
        vec3 sunRight = normalize(cross(vSunWorldDir, poleAxis));
        vec3 sunUp    = normalize(cross(sunRight, vSunWorldDir));
        vec2 sunUV    = vec2(dot(worldRayDir, sunRight), dot(worldRayDir, sunUp)) / (0.096 * SUN_SIZE * sunStyleScale);
        float rSun    = length(sunUV);

        // Animate only the light around the artwork. Stable atlas coordinates
        // keep the painted disc and celestial bird legible rather than rotating them.
        float solarFlow = sin(sunUV.x * 3.2 + sunUV.y * 2.6 + frameTimeCounter * 0.13)
                        * sin(sunUV.y * 4.4 - sunUV.x * 1.8 - frameTimeCounter * 0.09);
        float coronaRadius = rSun + solarFlow * 0.025;
        float coronaDistance = max(coronaRadius - 0.99, 0.0);
        float outerCorona = (exp(-coronaDistance * coronaDistance * 10.0) * 0.28
            + exp(-coronaDistance * 2.0) * 0.065)
            * (1.0 - smoothstep(1.2, 2.8, rSun))
            * (0.96 + 0.04 * solarFlow) * sunHorizonVis * (1.0 - bPale * 0.55);

        vec3 baseCorona = (STYLE_SELECTION == 0)
            ? mix(vec3(0.98, 0.72, 0.38), vec3(1.02, 0.48, 0.22), vSunsetFactor)
            : mix(vec3(1.02, 0.82, 0.46), vec3(1.08, 0.56, 0.26), vSunsetFactor);

        // Harmonize corona with active biome skybox so it never clashes against Swamp, Jungle, Cherry, Snowy, or Pale Garden skies
        vec3 biomeCoronaTarget = baseCorona * mix(vec3(1.0), skyChroma, 0.65);
        vec3 coronaColor = mix(baseCorona, biomeCoronaTarget, biomeAtmWeight * 0.78);
        if (bPale > 0.001) {
            float cLum = dot(coronaColor, vec3(0.2126, 0.7152, 0.0722));
            coronaColor = mix(coronaColor, vec3(cLum) * vec3(1.02, 0.98, 0.94), bPale * 0.82);
        }
        skyRadiance += coronaColor * outerCorona * overcastTrans;

        if (rSun < 2.0) {
            vec2 atlasUV;
            // Padded sun trial retains the original two-cell layout.
            float sunArtworkScale = 0.41;
            vec2 sunArtworkCenter = vec2(0.5);
            vec2 localSunUV = vec2(sunUV.x, -sunUV.y) * sunArtworkScale + sunArtworkCenter;
            if (all(greaterThanEqual(localSunUV, vec2(0.0))) && all(lessThanEqual(localSunUV, vec2(1.0)))) {
                vec2 sunCellSize = vec2(textureSize(celestialTex, 0)) * vec2(0.5, 1.0);
                localSunUV = clamp(localSunUV, 0.5 / sunCellSize, 1.0 - 0.5 / sunCellSize);
                if (STYLE_SELECTION == 0) {
                    atlasUV = vec2(localSunUV.x * 0.5, localSunUV.y);
                } else {
                    atlasUV = vec2(0.5 + localSunUV.x * 0.5, localSunUV.y);
                }

                vec4 texSun = texture(celestialTex, atlasUV);
                float sunAlpha = texSun.a * overcastTrans * sunHorizonVis;

                if (sunAlpha > 0.001) {
                    vec3 sunArtwork = texSun.rgb;
                    vec3 sunsetTint = (STYLE_SELECTION == 0)
                        ? mix(vec3(1.0), vec3(1.12, 0.58, 0.36), vSunsetFactor)
                        : mix(vec3(1.0), vec3(1.14, 0.64, 0.38), vSunsetFactor);
                    sunArtwork *= sunsetTint;

                    // Biome-adaptive atmospheric transmittance & edge integration on the Sun disc:
                    // Preserves the crisp painted center while seating the disc & rim naturally into the biome sky
                    float sunRimFactor = smoothstep(0.52, 0.98, rSun);
                    vec3 biomeSunFilter = mix(vec3(1.0), skyChroma, (0.24 + 0.28 * sunRimFactor) * biomeAtmWeight);
                    sunArtwork *= biomeSunFilter;

                    if (bPale > 0.001) {
                        float sLum = dot(sunArtwork, vec3(0.2126, 0.7152, 0.0722));
                        sunArtwork = mix(sunArtwork, vec3(sLum) * vec3(1.04, 0.99, 0.93), bPale * 0.72);
                    }

                    // Atmospheric veil ("inscatter") from the local sky dome across low-horizon & misty biomes
                    float atmInscatter = clamp(horizonMistVeil + (0.10 + 0.16 * sunRimFactor) * (biomeAtmWeight * 0.75 + wetnessFactor * 0.65), 0.0, 0.58);
                    sunArtwork = mix(sunArtwork, max(bgSky * 1.18, sunArtwork * 0.82), atmInscatter);

                    float discBleed = exp(-max(rSun - 0.45, 0.0) * 3.2) * (STYLE_SELECTION == 0 ? 0.18 : 0.16);
                    skyRadiance = mix(skyRadiance, sunArtwork, sunAlpha);
                    skyRadiance += coronaColor * discBleed * sunAlpha * (1.0 - texSun.a) * (0.96 + solarFlow * 0.04);

                    celestialDiscMask = max(celestialDiscMask, clamp(sunAlpha * 1.15 * (1.0 - wetnessFactor * 0.95), 0.0, 1.0));
                }
            }
        }
    }

    float cosMoon = dot(worldRayDir, vMoonWorldDir);
    if (cosMoon > 0.85 && moonHorizonVis > 0.001) {
        vec3 poleAxis = abs(vMoonWorldDir.y) > 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
        vec3 moonRight = normalize(cross(vMoonWorldDir, poleAxis));
        vec3 moonUp    = normalize(cross(moonRight, vMoonWorldDir));

        float activeMoonScale = (STYLE_SELECTION == 1) ? (0.096 * SUN_SIZE) : moonAngularScale;
        vec2 moonUV    = vec2(dot(worldRayDir, moonRight), dot(worldRayDir, moonUp)) / activeMoonScale;
        float rMoon    = length(moonUV);

        int mPhase = moonPhase & 7;
        float phaseIllumFrac = (mPhase == 0) ? 1.00 : ((mPhase == 4) ? 0.015 : ((mPhase == 1 || mPhase == 7) ? 0.85 : ((mPhase == 2 || mPhase == 6) ? 0.50 : 0.15)));
        float phaseDirX      = (mPhase >= 1 && mPhase <= 3) ? -1.0 : ((mPhase >= 5 && mPhase <= 7) ? 1.0 : 0.0);
        float dirBias        = 1.0 + 0.28 * phaseDirX * clamp(moonUV.x / max(rMoon, 0.25), -1.0, 1.0);

        float wideLunarAura = exp(-rMoon * 1.35) * (1.0 - smoothstep(1.0, 2.8, rMoon)) * 0.10;
        float limbDiffusion = exp(-max(rMoon - 0.94, 0.0) * 5.5) * (1.0 - smoothstep(1.0, 2.1, rMoon)) * 0.13;
        float totalHalo = (wideLunarAura + limbDiffusion) * mix(0.22, 1.0, phaseIllumFrac)
            * dirBias * moonHorizonVis * overcastTrans;

        // Warm Xuan-jade / silk-amber lunar halo for the updated Guofeng Moon; spirit-cyan for Xianxia
        vec3 baseHaloTint = (STYLE_SELECTION == 0)
            ? mix(vec3(0.64, 0.72, 0.64), vec3(0.82, 0.76, 0.58), 0.45)
            : vec3(0.46, 0.76, 0.92);
        vec3 haloTint = mix(baseHaloTint, baseHaloTint * mix(vec3(1.0), skyChroma, 0.65), biomeAtmWeight * 0.75);
        if (bPale > 0.001) {
            float hLum = dot(haloTint, vec3(0.2126, 0.7152, 0.0722));
            haloTint = mix(haloTint, vec3(hLum) * vec3(1.0, 1.0, 1.02), bPale * 0.82);
        }
        skyRadiance += haloTint * totalHalo;

        // Sample the 4x2 eight-phase moon atlas using dynamic textureSize so the 2048x1024 Guofeng Moon
        // (with its lower-left/right cloud scrollwork) and 256x128 Xianxia Moon both sample at 100% native resolution
        float moonUVScale = (STYLE_SELECTION == 0) ? 0.365 : (30.0 / 64.0);
        vec2 localUV = moonUV * moonUVScale + 0.5;
        localUV.y = 1.0 - localUV.y;
        if (all(greaterThanEqual(localUV, vec2(0.0))) && all(lessThan(localUV, vec2(1.0)))) {
            ivec2 texDims = (STYLE_SELECTION == 0) ? textureSize(guofengMoonTex, 0) : textureSize(xianxiaMoonTex, 0);
            ivec2 cellDims = texDims / ivec2(4, 2);
            ivec2 cell = ivec2(mPhase & 3, mPhase >> 2);
            ivec2 pixel = cell * cellDims + clamp(ivec2(localUV * vec2(cellDims)), ivec2(0), cellDims - ivec2(1));
            vec4 moon = (STYLE_SELECTION == 0) ? texelFetch(guofengMoonTex, pixel, 0)
                                              : texelFetch(xianxiaMoonTex, pixel, 0);
            float opacity = moon.a * moonHorizonVis * overcastTrans;
            if (opacity > 0.001) {
                vec3 moonArtwork = moon.rgb;
                float moonLum = dot(moonArtwork, vec3(0.2126, 0.7152, 0.0722));

                // Darker pixels (the painted teal cloud motif, crater basins, and earthshine limb) absorb more
                // of the surrounding night/twilight/biome sky medium so the moon looks embedded in the atmosphere,
                // while the warm cream moonlit face stays crisp and luminous.
                float darkFeatureFactor = 1.0 - smoothstep(0.32, 0.78, moonLum);
                float moonRimFactor     = smoothstep(0.65, 1.08, rMoon);

                vec3 biomeMoonFilter = mix(vec3(1.0), skyChroma, (0.18 + 0.22 * moonRimFactor) * biomeAtmWeight);
                moonArtwork *= biomeMoonFilter;

                if (bPale > 0.001) {
                    moonArtwork = mix(moonArtwork, vec3(moonLum) * vec3(1.02, 1.00, 0.98), bPale * 0.65);
                }

                // Daylight/twilight & horizon atmospheric inscatter: during day/dawn/dusk or near misty horizons,
                // the sky medium gently veils the shadowed features and blends the disc into the sky dome
                float daySkyVeil  = vDaylightFactor * (0.28 + 0.44 * darkFeatureFactor);
                float atmMoonVeil = clamp(daySkyVeil + horizonMistVeil * 0.85 + darkFeatureFactor * 0.16 + moonRimFactor * 0.12 * biomeAtmWeight, 0.0, 0.74);
                vec3 skySeatTarget = max(bgSky * 1.08, moonArtwork * 0.78);
                moonArtwork = mix(moonArtwork, skySeatTarget, atmMoonVeil);

                // Soft warm lunar bloom around the painted disc & cloud scrolls
                float moonBloom = exp(-max(rMoon - 0.55, 0.0) * 3.4) * 0.14 * mix(0.25, 1.0, phaseIllumFrac);
                skyRadiance = mix(skyRadiance, moonArtwork, opacity);
                skyRadiance += haloTint * moonBloom * opacity;
                celestialDiscMask = max(celestialDiscMask, opacity);
            }
        }
    }

    return celestialDiscMask;
}

#include "/lib/aurora.glsl"

// Celestial artwork is behind the emissive columns. Native stars are already
// behind the artwork. Above the layer, columns are added after the lower clouds.
float applyCelestialsAndAurora(inout vec3 sky, vec3 ray, float time, int mode) {
    float discMask = applyTexturedCelestialBodies(sky, ray);
    if (cameraPosition.y < AURORA_BASE_Y)
        sky += renderNightYunMengAurora(ray, time, mode, 1.0 - discMask);
    return discMask;
}

/* =============================================================================
 * UNIFIED 3D VOLUMETRIC CLOUDS AT A CONSISTENT WORLD HEIGHT
 * Technique references are recorded in THIRD_PARTY_NOTICES.txt.
 * 1. World-height cloud layer:
 *    Shared flat geometry for visible clouds and integrated cloud lighting.
 *    Existing distance haze and extinction blend distant clouds into the sky.
 * 2. Hierarchical Modeling (Large Shapes Before Fine Detail):
 *    - Macro Weather Map establishes broad cloud massifs, varied formation heights,
 *      and generous open sky channels that evolve slowly over time and weather.
 *    - Base Shape combines smooth C2 3D noise with spherical cellular billows and
 *      style-specific vertical profiles (flowing horizontal strata in Guofeng Ink
 *      vs. tall, sculpted convective cumulus towers in Xianxia Mist).
 *    - Restrained 3D Edge Erosion carves soft billow margins without eroding cores.
 * 3. Volumetric Lighting:
 *    - Directional self-shadowing + 2-octave multiple scattering approximation +
 *      anisotropic phase + sky/horizon bounce reveals 3D volume day and night.
 * ============================================================================= */
// Cloud geometry shares the world-height convention used by cloud lighting.
// A finite slab supports views below, inside and above the layer.
bool intersectCloudLayer(vec3 origin, vec3 direction, float baseAlt, float topAlt,
                         float maxDistance, out float tStart, out float tEnd) {
    tStart = 0.0;
    tEnd = maxDistance;
    if (abs(direction.y) < 1e-6) {
        return origin.y > baseAlt && origin.y < topAlt;
    }
    float baseHit = (baseAlt - origin.y) / direction.y;
    float topHit = (topAlt - origin.y) / direction.y;
    tStart = max(min(baseHit, topHit), 0.0);
    tEnd = min(max(baseHit, topHit), maxDistance);
    return tEnd > tStart;
}

float sampleWorldCloudVolume(vec3 tracePos, float time, int mode,
    float rain, float storm, float stepSize, out float height, out float detail) {
    return cloudDensity(tracePos, tracePos.y, time, mode, rain, storm, stepSize, height, detail);
}

vec4 renderYunMengVolumetricClouds(vec3 rayDirWorld, vec3 viewRayDir, vec3 camPos, float time, vec3 bgSkyColor, float celestialDiscMask, float maxSceneDist, int activeCloudMode, bool reflectionTrace) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);

    float baseAlt, maxTopAlt;
    cloudBounds(activeCloudMode, baseAlt, maxTopAlt);
    float maxTraceDist = max(CLOUD_RENDER_DISTANCE, 2400.0);

    // Spherical Cloud Dome Horizon Curvature (works both below and above the cloud layer):
    float belowCloudWeight = clamp((baseAlt - camPos.y) / 48.0, 0.0, 1.0);
    float aboveCloudWeight = clamp((camPos.y - maxTopAlt) / 64.0, 0.0, 1.0);
    float horizonFactor    = pow(clamp(1.0 - abs(rayDirWorld.y) * 1.5, 0.0, 1.0), 1.65);
    float horizonWrap      = CLOUD_HORIZON_CURVE * horizonFactor * (belowCloudWeight - aboveCloudWeight * 0.65);
    vec3 cloudRayDir       = normalize(vec3(rayDirWorld.x, rayDirWorld.y + horizonWrap, rayDirWorld.z));

    float maxDistClamp = min(maxSceneDist, maxTraceDist);
    float maxSpan = (ACTIVE_CLOUD_FORM == 1) ? min(760.0, maxTraceDist * 0.38) : min(880.0, maxTraceDist * 0.44);

    float tStart, tEnd;
    if (!intersectCloudLayer(camPos, cloudRayDir, baseAlt, maxTopAlt, maxDistClamp, tStart, tEnd)) {
        return vec4(0.0);
    }
    tStart = max(tStart, 0.0);
    if (tStart >= maxSceneDist || tEnd <= tStart || tStart >= maxTraceDist) return vec4(0.0);
    tEnd = min(tEnd, min(maxSceneDist, min(tStart + maxSpan, maxTraceDist)));

    // Never fade out horizontal or downward rays when flying near, inside, or above the cloud layer!
    float localOverheadTop = maxTopAlt - 12.0;
    float nearOrAboveLayer = smoothstep(baseAlt - 42.0, baseAlt - 2.0, camPos.y);
    float belowGrazing     = smoothstep(0.012, 0.105, cloudRayDir.y);
    float grazingFade      = mix(belowGrazing, 1.0, nearOrAboveLayer);

    #if CLOUD_QUALITY == 0
    const int STEPS = 20;
    #elif CLOUD_QUALITY == 1
    const int STEPS = 32;
    #elif CLOUD_QUALITY == 2
    const int STEPS = 48;
    #else
    const int STEPS = 64;
    #endif
    const int REFLECTION_STEPS = (WATER_REFLECTIONS >= 2) ? max(STEPS / 2, 10) : max(STEPS / 4, 8);
    int baseSteps  = (ACTIVE_CLOUD_FORM == 2) ? min(STEPS, 24) : ((ACTIVE_CLOUD_FORM == 1) ? min(STEPS, 32) : STEPS);
    int traceSteps = reflectionTrace ? REFLECTION_STEPS : baseSteps;
    float totalSpan = tEnd - tStart;

    #if (CLOUD_SHAPE == 2) || (CLOUD_SHAPE == 0 && SKY_STYLE == 1)
    // Exact Dual-Slab Intersection for Lower Main Voxel Layer [baseAlt, baseAlt + 4.6]
    // and Upper Translucent Voxel Layer [baseAlt + 28.0, baseAlt + 32.2] so zero steps are wasted in the gap!
    float tL0, tL1, tU0, tU1;
    bool hasL = intersectCloudLayer(camPos, cloudRayDir, baseAlt, baseAlt + 4.6, maxDistClamp, tL0, tL1);
    bool hasU = intersectCloudLayer(camPos, cloudRayDir, baseAlt + 28.0, baseAlt + 32.2, maxDistClamp, tU0, tU1);
    if (hasL) {
        tL0 = max(tL0, 0.0);
        tL1 = min(tL1, min(maxDistClamp, tL0 + maxSpan));
        hasL = (tL1 > tL0) && (tL0 < maxDistClamp);
    }
    if (hasU) {
        tU0 = max(tU0, 0.0);
        tU1 = min(tU1, min(maxDistClamp, tU0 + maxSpan));
        hasU = (tU1 > tU0) && (tU0 < maxDistClamp);
    }
    if (!hasL && !hasU) return vec4(0.0);
    bool lowerFirst = !hasU || (hasL && tL0 <= tU0);
    float tA0 = lowerFirst ? tL0 : tU0;
    float tA1 = lowerFirst ? tL1 : tU1;
    bool hasA = lowerFirst ? hasL : hasU;
    float tB0 = lowerFirst ? tU0 : tL0;
    float tB1 = lowerFirst ? tU1 : tL1;
    bool hasB = lowerFirst ? hasU : hasL;
    int halfSteps = max(traceSteps / 2, 1);
    #endif

    // Use stable low-amplitude spatial offset so non-TAA modes (Subtle/Smooth AA) never show 1-pixel checkerboard stipple
    float dither = 0.15 + 0.70 * hash12(gl_FragCoord.xy);

    float cosLight = dot(viewRayDir, vLightViewDir);
    float directSourceVis = smoothstep(0.06, 0.24, vLightWorldDir.y);
    float nightAmbientVis = vNightFactor * 0.86;
    float effectiveLightVis = max(directSourceVis, nightAmbientVis);

    float hgForward = henyeyGreensteinPhase(cosLight, 0.65) * 1.40;
    float hgBack    = henyeyGreensteinPhase(cosLight, -0.25) * 0.45;
    float phaseFunction = (hgForward + hgBack) * directSourceVis * pow(clamp(1.0 - wetnessFactor * 0.96, 0.0, 1.0), 2.0) * (1.0 - stormFactor * 0.96);

    vec3 cDeepFold, cMidFold, cWarmMid, cSunCrest, silverRimColor;
    getLuminousCloudPalette(cDeepFold, cMidFold, cWarmMid, cSunCrest, silverRimColor);

    // Seat cloud palette into the local sky medium (bgSkyColor) so clouds naturally belong to any biome or weather skybox:
    float bgLum = dot(bgSkyColor, vec3(0.2126, 0.7152, 0.0722));
    vec3 bgNorm = bgSkyColor / max(bgLum, 0.035);
    vec3 skyTintRatio = clamp(mix(vec3(1.0), bgNorm, 0.42 + 0.28 * wetnessFactor), vec3(0.62), vec3(1.38));
    cDeepFold  = mix(cDeepFold  * skyTintRatio, bgSkyColor * 0.64, 0.34 + 0.24 * wetnessFactor);
    cMidFold   = mix(cMidFold   * skyTintRatio, bgSkyColor * 0.90, 0.26 + 0.22 * wetnessFactor);
    cWarmMid   = mix(cWarmMid   * mix(vec3(1.0), skyTintRatio, 0.75), bgSkyColor * 1.12, 0.18 + 0.20 * wetnessFactor);
    cSunCrest  = mix(cSunCrest  * mix(vec3(1.0), skyTintRatio, 0.55), bgSkyColor * 1.26, 0.12 + 0.18 * wetnessFactor);

    float absRayY = abs(cloudRayDir.y);
    float verticalOpticalProjection = mix(max(absRayY, 0.10), 1.0, 0.16);
    float baseOpticalScale = ((ACTIVE_CLOUD_FORM == 2)
        ? 0.078
        : ((ACTIVE_CLOUD_FORM == 1) ? 0.068 : ((activeCloudMode == 1) ? 0.052 : 0.058))) * verticalOpticalProjection;

    float topDownView = smoothstep(baseAlt - 6.0, baseAlt + 8.0, camPos.y)
                      * (1.0 - smoothstep(-0.18, 0.02, rayDirWorld.y));

    vec3 accumColor = vec3(0.0);
    float accumTransmittance = 1.0;

    float cachedShadowOD = 0.0;
    bool hasShadowSample = false;
    vec3 activeCelestialDir = (vDaylightFactor > 0.25) ? vSunWorldDir : vMoonWorldDir;
    vec3 shadowDir = normalize(mix(vec3(0.0, 1.0, 0.0), activeCelestialDir, 0.68));
    vec2 lightHorizDir = normalize(activeCelestialDir.xz + vec2(1e-4, 0.0));

    for (int i = 0; i < STEPS; i++) {
        if (i >= traceSteps) break;
        #if (CLOUD_SHAPE == 2) || (CLOUD_SHAPE == 0 && SKY_STYLE == 1)
        bool inSecondSlab = (i >= halfSteps);
        if (inSecondSlab && !hasB) break;
        if (!inSecondSlab && !hasA) continue;
        int localIdx   = inSecondSlab ? (i - halfSteps) : i;
        int localCount = inSecondSlab ? (traceSteps - halfSteps) : (hasB ? halfSteps : traceSteps);
        float segStart = inSecondSlab ? tB0 : tA0;
        float segSpan  = inSecondSlab ? (tB1 - tB0) : (tA1 - tA0);
        float f0 = float(localIdx) / float(max(localCount, 1));
        float f1 = float(localIdx + 1) / float(max(localCount, 1));
        float stepSize = (f1 - f0) * segSpan;
        float tSample  = segStart + mix(f0, f1, dither) * segSpan;
        #else
        float f0 = float(i) / float(traceSteps);
        float f1 = float(i + 1) / float(traceSteps);
        float w0 = mix(f0, f0 * f0, 0.30);
        float w1 = mix(f1, f1 * f1, 0.30);
        float stepSize = (w1 - w0) * totalSpan;
        float tSample  = tStart + mix(w0, w1, dither) * totalSpan;
        #endif
        vec3 rawPos    = camPos + cloudRayDir * tSample;
        float distXZ   = length(rawPos.xz - camPos.xz);
        if (distXZ > maxTraceDist) break;

        // Full 3D side-wall & upper-dome reveal across viewing sky (1.0 for 3D Voxel modes; 0.36..0.80 on ground for Soft Volumetric)
        vec2 baseEntryXZ   = camPos.xz + cloudRayDir.xz * tStart;
        float groundPara   = 0.36 + 0.44 * pow(clamp(1.0 - absRayY, 0.0, 1.0), 1.35);
        float parallaxKeep = (ACTIVE_CLOUD_FORM == 2)
            ? 1.0
            : mix(groundPara, 1.0, smoothstep(baseAlt - 28.0, baseAlt + 12.0, camPos.y));
        vec3 tracePos = vec3(mix(baseEntryXZ.x, rawPos.x, parallaxKeep), rawPos.y, mix(baseEntryXZ.y, rawPos.z, parallaxKeep));

        float localHeightNorm, detailBillow;
        float cloudDensity = sampleWorldCloudVolume(tracePos, time, activeCloudMode, wetnessFactor, stormFactor, stepSize, localHeightNorm, detailBillow);

        if (cloudDensity > 0.001) {
            // 2-Scale 3D Volumetric Sun Shadowing: near 3D sun-step + precomputed column optical depth cache
            #if CLOUD_QUALITY == 0
            cachedShadowOD = cloudDensity * (1.0 - localHeightNorm * 0.65);
            #else
            if (!hasShadowSample || (i & 3) == 0) {
                float dummyH, dummyD;
                vec3 sunStep = vec3(shadowDir.x * 24.0, max(shadowDir.y, 0.30) * 16.0, shadowDir.z * 24.0);
                float nearSun = sampleWorldCloudVolume(tracePos + sunStep, time, activeCloudMode, wetnessFactor, stormFactor, max(stepSize * 1.4, 24.0), dummyH, dummyD);
                #ifdef YUNMENG_CLOUD_LIGHT_CACHE
                float colOD = cachedCloudOpticalDepth(tracePos + sunStep * 1.5, vLightWorldDir, time, activeCloudMode, wetnessFactor, stormFactor) * 0.22;
                cachedShadowOD = nearSun * 0.64 + colOD * 0.36;
                #else
                cachedShadowOD = nearSun;
                #endif
                hasShadowSample = true;
            }
            #endif
            float sunOccl    = max(cachedShadowOD - cloudDensity * 0.18, 0.0) * 0.82;
            float heightOccl = pow(clamp(1.0 - localHeightNorm, 0.0, 1.0), 1.35) * 0.68;
            float shadowOD   = heightOccl + sunOccl;

            float tau = shadowOD * ((activeCloudMode == 1) ? 1.25 : (1.35 + stormFactor * 0.55)) * effectiveLightVis;
            float multiScatter = exp(-tau) * 0.60 + exp(-tau * 0.32) * 0.40;
            float powder       = 1.0 - 0.35 * exp(-cloudDensity * 3.2);
            float wispBright   = 0.12 * exp(-cloudDensity * 2.4);
            float lightTrans   = clamp(0.16 + 0.84 * multiScatter * powder + wispBright, 0.0, 1.0);

            vec3 colorSample;
            #if (CLOUD_SHAPE == 2) || (CLOUD_SHAPE == 0 && SKY_STYLE == 1)
            // Crisp 4-Face 3D Minecraft Voxel Shading (Sunlit Top, Sunlit vs Shaded Vertical Walls, Smooth Flat Underside)
            float envMod = mix(0.80, 1.0, vDaylightFactor) * mix(1.0, 0.68, wetnessFactor) * mix(1.0, 0.74, stormFactor);
            bool viewingFromAbove = (camPos.y > tracePos.y + 1.2) && (cloudRayDir.y < 0.0);
            if (detailBillow > 0.50) {
                vec2 wallNormalXZ = (detailBillow < 0.67) ? vec2(1.0, 0.0)
                                  : ((detailBillow < 0.77) ? vec2(-1.0, 0.0)
                                  : ((detailBillow < 0.87) ? vec2(0.0, 1.0) : vec2(0.0, -1.0)));
                float wallSunDot = dot(wallNormalXZ, lightHorizDir);
                vec3 litWallCol  = mix(cWarmMid, cSunCrest, 0.58);
                vec3 shdWallCol  = mix(cDeepFold, cMidFold, 0.38);
                colorSample      = mix(shdWallCol, litWallCol, smoothstep(-0.18, 0.22, wallSunDot));
            } else if (localHeightNorm > 0.68 || viewingFromAbove || topDownView > 0.35) {
                colorSample = mix(cWarmMid, cSunCrest, 0.88);
            } else {
                colorSample = mix(cDeepFold, cMidFold, 0.68);
            }
            colorSample *= envMod * mix(0.84, 1.0, lightTrans);
            #else
            float sunWall           = clamp((cloudDensity - cachedShadowOD) * 0.90 + 0.52, 0.0, 1.0);
            float canopyTopLight    = topDownView * accumTransmittance * 0.46;
            float reliefScale       = 1.0 - wetnessFactor * 0.42;
            float reliefMod         = ((sunWall - 0.50) * 0.34 + (detailBillow - 0.50) * 0.22) * reliefScale;
            float verticalLight     = clamp(smoothstep(0.06, 0.58, localHeightNorm + reliefMod) + canopyTopLight, 0.0, 1.0);
            float directionalRelief = clamp(0.28 + (sunWall * 0.52 + (detailBillow - 0.50) * 0.26) * reliefScale, 0.0, 1.0);
            float cloudShading      = clamp((0.06 + 0.60 * verticalLight + 0.34 * directionalRelief) * lightTrans
                + canopyTopLight * 0.30, 0.0, 1.0);
            cloudShading *= mix(0.76, 1.0, vDaylightFactor) * mix(1.0, 0.65, wetnessFactor) * mix(1.0, 0.72, stormFactor);

            float t1 = clamp(cloudShading * 1.95, 0.0, 1.0);
            float t2 = clamp((cloudShading - 0.24) * 1.85, 0.0, 1.0);
            float t3 = clamp((cloudShading - 0.50) * 2.15, 0.0, 1.0);
            t1 = t1 * t1 * (3.0 - 2.0 * t1);
            t2 = t2 * t2 * (3.0 - 2.0 * t2);
            t3 = t3 * t3 * (3.0 - 2.0 * t3);

            colorSample = mix(cDeepFold, cMidFold, t1);
            colorSample = mix(colorSample, cWarmMid,  t2);
            colorSample = mix(colorSample, cSunCrest, t3);
            #endif

            // Embed cloud undersides & thin edges into the surrounding sky medium (bgSkyColor)
            float baseBounce = (1.0 - smoothstep(0.0, 0.38, localHeightNorm)) * (0.28 + 0.22 * wetnessFactor) * (1.0 - topDownView * 0.75);
            float edgeSeat   = (1.0 - smoothstep(0.05, 0.65, cloudDensity)) * (0.22 + 0.18 * wetnessFactor);
            colorSample = mix(colorSample, bgSkyColor * 1.02, clamp(baseBounce + edgeSeat, 0.0, 0.58));

            float thinTrans = exp(-shadowOD * 1.45);
            float rimMask = celestialDiscMask * (1.0 - celestialDiscMask) * 3.5;
            float wetRimBreak = (1.0 - smoothstep(0.18, 0.72, cloudDensity)) * smoothstep(0.0, 0.90, cosLight) * wetnessFactor * 0.72;
            float silverBoost = (phaseFunction + rimMask * (1.0 - wetnessFactor) + wetRimBreak) * thinTrans;
            float rimScale = (activeCloudMode == 1) ? 0.28 : 0.42;
            colorSample += silverRimColor * clamp(silverBoost * rimScale, 0.0, 0.65);

            applyCelestialCloudGlow(rayDirWorld, thinTrans, colorSample);

            // Seamless Horizon & Atmospheric Extinction:
            // Starts closer (90m) and stronger in rain/mist so clouds melt smoothly into every biome skybox!
            float aerialHaze = 1.0 - exp(-max(distXZ - 90.0, 0.0) * mix(0.0022, 0.0034, wetnessFactor));
            float elevMist   = (1.0 - smoothstep(0.02, 0.28, absRayY)) * (0.32 + 0.24 * wetnessFactor);
            float highSkyAuroraProtect = smoothstep(0.16, 0.36, rayDirWorld.y) * vNightFactor * (1.0 - wetnessFactor);
            float hazeColorBlend = mix(0.96, 0.42, highSkyAuroraProtect);
            colorSample = mix(colorSample, bgSkyColor, clamp((aerialHaze + elevMist) * hazeColorBlend, 0.0, 0.96));

            float distanceEnvelope = (1.0 - smoothstep(maxTraceDist * 0.55, maxTraceDist * 0.98, distXZ))
                                   * (1.0 - aerialHaze * mix(0.45, 0.65, highSkyAuroraProtect));
            float rawStepOD        = cloudDensity * stepSize * baseOpticalScale * distanceEnvelope;
            float stepOpticalDepth = min(rawStepOD, 4.0);
            float stepAlpha  = 1.0 - exp(-stepOpticalDepth);
            float stepWeight = accumTransmittance * stepAlpha;

            accumColor += colorSample * stepWeight;
            accumTransmittance *= (1.0 - stepAlpha);

            if (accumTransmittance < 0.018) {
                accumTransmittance = 0.0;
                break;
            }
        }
    }

    float totalAlpha = 1.0 - accumTransmittance;
    if (totalAlpha <= 0.001) return vec4(0.0);

    vec3 finalCloudColor = accumColor / max(totalAlpha, 1e-4);

    float startDistFade   = 1.0 - smoothstep(maxTraceDist * 0.60, maxTraceDist * 0.96, tStart);
    float maxCloudOpacity = mix(0.98, 1.0, wetnessFactor);
    float shapeGamma      = 1.0;
    float finalCloudAlpha = clamp(pow(totalAlpha, shapeGamma) * maxCloudOpacity * grazingFade * startDistFade, 0.0, 1.0);

    return vec4(finalCloudColor, finalCloudAlpha);
}

float terrainSkyBlend(vec3 playerPos) {
    float rain, storm, flash;
    evaluateWeatherState(rain, storm, flash);
    return airBorderFog(playerPos, rain, storm);
}

vec4 computeValleyMistAndBorderFog(vec3 worldPos, vec3 playerPos, float viewDist, vec3 skyAtRay, vec3 worldRayDir, vec3 viewRayDir) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);
    float borderWeight = airBorderFog(playerPos, wetnessFactor, stormFactor);
    float pathWeight   = airPathFog(cameraPosition, worldPos, viewDist, wetnessFactor, stormFactor);
    float combinedFog  = 1.0 - (1.0 - borderWeight) * (1.0 - pathWeight);

    // Anchor valley/path mist to the lower atmospheric horizon band so elevated hilltops and cherry trees
    // fade into cohesive valley mist rather than looking see-through against the upper sky dome,
    // while smoothly matching skyAtRay right at the unloaded chunk border.
    vec3 mistWorldRay = normalize(vec3(worldRayDir.x, clamp(worldRayDir.y * 0.65, -0.02, 0.24), worldRayDir.z));
    vec3 mistViewRay  = normalize(transpose(mat3(gbufferModelViewInverse)) * mistWorldRay);
    vec3 horizonMistColor = evaluateUnifiedSky(mistWorldRay, mistViewRay);
    if (inTheEnd > 0.001) {
        // Isotropic abyssal horizon mist color in The End so downward rays (worldRayDir.xz -> 0)
        // never project the directional sky bloom into a nadir cone under the player!
        vec3 isotropicEndMist = (STYLE_SELECTION == 0)
            ? vec3(0.034, 0.056, 0.045)
            : vec3(0.026, 0.072, 0.076);
        horizonMistColor = mix(horizonMistColor, isotropicEndMist, clamp(inTheEnd, 0.0, 1.0));
    }
    float elevMatch = smoothstep(-0.01, 0.08, worldRayDir.y);
    float skyMatchW = max(smoothstep(0.08, 0.70, borderWeight),
                      max(smoothstep(0.22, 0.80, combinedFog),
                      max(elevMatch * 0.85,
                      max(vSunsetFactor * 0.85, evaluatePaleGardenWeight() * 0.98))));
    vec3 finalFogCol = mix(horizonMistColor, skyAtRay, skyMatchW);
    return vec4(finalFogCol, clamp(combinedFog, 0.0, 1.0));
}

vec3 applyAtmosphericPrecipitation(vec3 sceneRadiance, vec3 unifiedSky, vec3 worldRayDir, float viewDist) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);

    // Subtle distant rain-curtain shimmer across far hills & valleys (>16m) so zoomed-in views show drifting rain sheets
    float distantRainGate = clamp(rainStrength, 0.0, 1.0) * (1.0 - clamp(inSnowyBiome, 0.0, 1.0))
                          * (1.0 - clamp(inAridBiome, 0.0, 1.0)) * smoothstep(16.0, 42.0, viewDist)
                          * smoothstep(-0.22, 0.14, worldRayDir.y) * (1.0 - smoothstep(0.35, 0.72, worldRayDir.y));
    if (distantRainGate > 0.01) {
        float azim = atan(worldRayDir.z, worldRayDir.x);
        float slant = (SKY_STYLE == 1) ? 0.03 : 0.12;
        float sheetU = azim * 18.0 + worldRayDir.y * (18.0 * slant);
        float sheetV = worldRayDir.y * 8.0 + frameTimeCounter * (2.6 + 1.2 * stormFactor) * max(WIND_SPEED, 0.4);
        float curtainA = 0.5 + 0.5 * sin(sheetU * 1.35 + sin(sheetV * 0.45) * 0.8);
        float curtainB = 0.5 + 0.5 * sin(sheetU * 2.90 - frameTimeCounter * 0.35 + sheetV * 0.25);
        float fineLines = pow(curtainA * 0.55 + curtainB * 0.45, 2.2);
        vec3 curtainCol = mix(unifiedSky * 1.10, vec3(0.42, 0.49, 0.54) * mix(0.18, 0.88, vDaylightFactor), 0.45);
        sceneRadiance = mix(sceneRadiance, max(sceneRadiance, curtainCol), fineLines * distantRainGate * (0.09 + 0.06 * stormFactor));
    }

    vec4 weatherSample = texture(colortex3, vTexCoord);
    if (weatherSample.a <= 0.002) return sceneRadiance;

    vec3 unpacked     = weatherSample.rgb / max(weatherSample.a, 1e-4);
    float streakLuma  = clamp(unpacked.r, 0.40, 1.0);
    float blockLight  = clamp(unpacked.g, 0.0, 1.0);
    float snowWeight  = clamp(unpacked.b, 0.0, 1.0);

    vec3 rainMistTint = (STYLE_SELECTION == 0)
        ? mix(vec3(0.08, 0.13, 0.17), vec3(0.54, 0.62, 0.62), vDaylightFactor)
        : mix(vec3(0.08, 0.14, 0.24), vec3(0.50, 0.62, 0.74), vDaylightFactor);
    rainMistTint *= mix(1.0, 0.72, stormFactor * vDaylightFactor);

    vec3 baseRainColor = mix(unifiedSky * 1.12, rainMistTint, 0.48) * (0.78 + 0.38 * streakLuma);
    vec3 baseSnowColor = mix(unifiedSky * 0.55 + rainMistTint * 0.75, vec3(0.92, 0.95, 0.97) * mix(0.24, 0.92, vDaylightFactor), 0.65) * streakLuma;
    vec3 precipColor   = mix(baseRainColor, baseSnowColor, snowWeight);

    vec3 lanternTint = vec3(1.25, 0.78, 0.38) * pow(blockLight, 2.0) * 0.85;
    precipColor += lanternTint;

    if (lightningFlash > 0.001) {
        float dirBoost = computeLightningDirectionalBoost(worldRayDir);
        vec3 flashTint = (STYLE_SELECTION == 0) ? vec3(0.60, 0.72, 0.80) : vec3(0.58, 0.76, 1.04);
        precipColor += flashTint * (lightningFlash * dirBoost * 0.45);
    }

    float effectiveAlpha = clamp(weatherSample.a * mix(0.68, 0.90, snowWeight), 0.0, 0.68);
    return mix(sceneRadiance, max(sceneRadiance * 0.85, precipColor), effectiveAlpha);
}

#ifndef YUNMENG_CLOUD_PREPASS
vec3 computeUnderwaterLightShafts(vec3 viewPos, vec3 lightDirWorld, float cosTheta) {
    #if LIGHT_SHAFTS == 0
    return vec3(0.0);
    #else
    const int UW_STEPS = (LIGHT_SHAFTS >= 2) ? 14 : 8;
    float sourceVisibility = smoothstep(0.05, 0.22, lightDirWorld.y);
    if (sourceVisibility <= 0.0 || ATMOSPHERIC_SHAFT_STRENGTH <= 0.0) return vec3(0.0);
    const int cloudMode = (CLOUD_TYPE == 0) ? (STYLE_SELECTION == 0 ? 1 : 2) : CLOUD_TYPE;
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);
    float dither = interleavedGradientNoise(gl_FragCoord.xy);

    float maxDist = min(length(viewPos), 36.0);
    vec3 rayDirView = normalize(viewPos);
    vec3 stepVecView = rayDirView * (maxDist / float(UW_STEPS));
    vec3 currentViewPos = stepVecView * (dither + 0.2);

    vec3 refractSunWorld = normalize(vec3(lightDirWorld.x * 0.65, max(abs(lightDirWorld.y), 0.55), lightDirWorld.z * 0.65));

    float accumBeams = 0.0;
    for (int i = 0; i < UW_STEPS; i++) {
        vec3 samplePlayerPos = (gbufferModelViewInverse * vec4(currentViewPos, 1.0)).xyz;
        vec3 sampleWorldPos  = samplePlayerPos + cameraPosition;

        vec4 shadowViewPos = shadowModelView * vec4(samplePlayerPos, 1.0);
        vec4 shadowClipPos = shadowProjection * shadowViewPos;
        shadowClipPos.xyz  = distortShadowClipPos(shadowClipPos.xyz);
        vec3 shadowUV      = shadowClipPos.xyz * 0.5 + 0.5;

        float shadowVis = 1.0;
        if (shadowUV.x > 0.0 && shadowUV.x < 1.0 && shadowUV.y > 0.0 && shadowUV.y < 0.999) {
            float sDepth = texture(shadowtex1, shadowUV.xy).r;
            shadowVis = step(shadowUV.z - 0.0008, sDepth);
        }
        if (shadowVis > 0.0) {
            // Offset slightly by depth along the ray so looking straight into the refracted sun vector
            // integrates across wave phases instead of locking onto a single dark wave trough at the beam center.
            vec2 wavePlaneUV = sampleWorldPos.xz - refractSunWorld.xz * (sampleWorldPos.y / refractSunWorld.y)
                             + vec2(sampleWorldPos.y * 0.14, -sampleWorldPos.y * 0.11);
            float t = frameTimeCounter;

            float wA = sin(wavePlaneUV.x * 1.15 + wavePlaneUV.y * 0.75 - t * 1.6);
            float wB = cos(wavePlaneUV.x * 0.85 - wavePlaneUV.y * 1.35 + t * 1.3);
            float wC = sin((wavePlaneUV.x + wavePlaneUV.y) * 1.95 - t * 2.1);
            float causticLens = pow(clamp(1.0 - abs(wA * 0.5 + wB * 0.5 + wC * 0.25), 0.0, 1.0), 2.4);

            float distAtten = exp(-length(currentViewPos) * 0.045);
            float cloudTransmission = cloudLightTransmission(sampleWorldPos, lightDirWorld,
                frameTimeCounter, cloudMode, wetnessFactor, stormFactor);
            accumBeams += shadowVis * cloudTransmission * causticLens * distAtten;
        }
        currentViewPos += stepVecView;
    }

    accumBeams /= float(UW_STEPS);

    vec3 worldRayDir = normalize(mat3(gbufferModelViewInverse) * rayDirView);
    float upLookBoost = smoothstep(-0.45, 0.85, worldRayDir.y) * 0.65 + 0.35;
    float sunAlign    = henyeyGreensteinPhase(dot(worldRayDir, refractSunWorld), 0.55);

    float beamStrength = accumBeams * (0.75 + sunAlign * 0.55) * upLookBoost
                       * mix(0.25, 1.0, vDaylightFactor) * float(LIGHT_SHAFTS) * ATMOSPHERIC_SHAFT_STRENGTH;
    beamStrength *= sourceVisibility;

    if (STYLE_SELECTION == 0) {
        return vec3(0.56, 0.78, 0.72) * clamp(beamStrength * 0.75, 0.0, 0.65);
    } else {
        return vec3(0.28, 0.88, 0.86) * clamp(beamStrength * 1.05, 0.0, 0.82);
    }
    #endif
}

vec3 computeVolumetricLightShafts(vec3 viewPos, float depth0, float cosTheta, float sceneLuma, float horizonFogWeight) {
    #if LIGHT_SHAFTS == 0
    return vec3(0.0);
    #else
    const int cloudMode = (CLOUD_TYPE == 0) ? (STYLE_SELECTION == 0 ? 1 : 2) : CLOUD_TYPE;
    const float MAX_SHAFT_RANGE = cloudMode == 3
        ? ((LIGHT_SHAFTS >= 2) ? 176.0 : 128.0)
        : ((LIGHT_SHAFTS >= 2) ? 760.0 : 580.0);
    float fullViewDist = length(viewPos);
    float sourceVisibility = smoothstep(0.06, 0.24, vLightWorldDir.y);
    if (fullViewDist <= 0.001 || sourceVisibility <= 0.0 || ATMOSPHERIC_SHAFT_STRENGTH <= 0.0) return vec3(0.0);
    // Held items are foreground geometry, outside the atmospheric volume.
    if (abs(texture(colortex1, vTexCoord).a - 0.12) < 0.007) return vec3(0.0);

    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);
    float cloudBase, cloudTop;
    cloudBounds(cloudMode, cloudBase, cloudTop);

    vec3 rayDirView = viewPos / max(fullViewDist, 1e-5);
    vec3 rayDirPlayer = normalize(mat3(gbufferModelViewInverse) * rayDirView);
    vec3 rayOriginPlayer = gbufferModelViewInverse[3].xyz;
    vec3 camWorld = cameraPosition + rayOriginPlayer;

    // Match the exact spherical horizon curvature used by renderYunMengVolumetricClouds
    // so the top of every light shaft at Y = cloudBase aligns pixel-for-pixel with the visible cloud hole!
    float belowCloudWeight = clamp((cloudBase - camWorld.y) / 48.0, 0.0, 1.0);
    float aboveCloudWeight = clamp((camWorld.y - cloudTop) / 64.0, 0.0, 1.0);
    float horizonFactor    = pow(clamp(1.0 - abs(rayDirPlayer.y) * 1.5, 0.0, 1.0), 1.65);
    float horizonWrap      = CLOUD_HORIZON_CURVE * horizonFactor * (belowCloudWeight - aboveCloudWeight * 0.65);
    vec3 curvedCloudRay    = normalize(vec3(rayDirPlayer.x, rayDirPlayer.y + horizonWrap, rayDirPlayer.z));

    // Bound sky raymarching at the cloud base so 100% of samples resolve the sub-cloud crepuscular beams!
    float maxRayDist = (depth0 >= 0.999999 && cloudMode != 3) ? MAX_SHAFT_RANGE : min(fullViewDist, MAX_SHAFT_RANGE);
    if (cloudMode != 3 && camWorld.y < cloudBase && curvedCloudRay.y > 0.015) {
        float tToCloudBase = (cloudBase - camWorld.y) / curvedCloudRay.y;
        maxRayDist = min(maxRayDist, tToCloudBase + 4.0);
    }
    if (maxRayDist <= 0.001) return vec3(0.0);

    const int RAY_STEPS = ATMOSPHERIC_SHAFT_QUALITY==0 ? 12
        : (ATMOSPHERIC_SHAFT_QUALITY==1 ? 18 : (ATMOSPHERIC_SHAFT_QUALITY==2 ? 24 : 32));
    float dither = hash12(gl_FragCoord.xy);

    float minRayDist = min(1.25, maxRayDist * 0.15);
    vec3 shadowOrigin = (shadowProjection * (shadowModelView * vec4(rayOriginPlayer, 1.0))).xyz;
    vec3 shadowDirection = (shadowProjection * (shadowModelView * vec4(rayDirPlayer, 0.0))).xyz;
    vec3 lightStepShadowClip = (shadowProjection * (shadowModelView * vec4(vLightWorldDir, 0.0))).xyz;
    float oneMeterShadowZ = max(abs(lightStepShadowClip.z) * 0.1, 1e-5);

    float cloudScatter = 0.0;
    float litScatter = 0.0;
    for (int i = 0; i < RAY_STEPS; i++) {
        float u0 = float(i) / float(RAY_STEPS);
        float u1 = float(i + 1) / float(RAY_STEPS);
        // Stratified linear + quadratic distribution resolves both near-camera window shafts
        // and distant (100..750m) cloud-hole crepuscular beams with high sharpness!
        float f0 = mix(u0, u0 * u0, 0.45);
        float f1 = mix(u1, u1 * u1, 0.45);
        float cellStart = mix(minRayDist, maxRayDist, f0);
        float cellEnd   = mix(minRayDist, maxRayDist, f1);
        float stepLen   = cellEnd - cellStart;
        float sampleDistance = mix(cellStart, cellEnd, dither);

        vec3 shadowClipPos = distortShadowClipPos(shadowOrigin + shadowDirection * sampleDistance);
        vec3 shadowUV = shadowClipPos * 0.5 + 0.5;

        float isUnoccluded = 1.0;
        if (all(greaterThan(shadowUV, vec3(0.001))) && all(lessThan(shadowUV, vec3(0.999)))) {
            float shadowMapDepth = texture(shadowtex1, shadowUV.xy).r;
            isUnoccluded = step(shadowUV.z - 0.0005, shadowMapDepth);

            if (isUnoccluded < 0.5) {
                float casterDist = max((shadowUV.z - shadowMapDepth) / oneMeterShadowZ, 0.0);
                vec3 casterPlayerPos = (rayOriginPlayer + rayDirPlayer * sampleDistance) + vLightWorldDir * casterDist;
                if (length(casterPlayerPos.xz) < 0.65 && casterPlayerPos.y > -1.80 && casterPlayerPos.y < 0.35) {
                    isUnoccluded = 1.0;
                }
            }
            isUnoccluded = mix(1.0, isUnoccluded, shadowCoverageWeight(shadowUV));
        }
        if (isUnoccluded <= 0.0) continue;

        vec3 sampleWorld = camWorld + rayDirPlayer * sampleDistance;
        vec3 sampleCloudWorld = camWorld + curvedCloudRay * sampleDistance;
        float holeTransmission = cachedCloudShaftTransmittance(sampleCloudWorld, vLightWorldDir,
            frameTimeCounter, cloudMode, wetnessFactor, stormFactor);

        float worldY = sampleWorld.y;
        float mistDensity = exp(-max(worldY - SEA_OF_CLOUDS_ALTITUDE, 0.0) * 0.012);
        float radialWeight = exp(-sampleDistance / 16.0) * (stepLen / 4.5);
        if (cloudMode == 3) radialWeight += exp(-sampleDistance / 70.0) * (stepLen / 360.0);
        float densityWeight = (0.78 + 0.22 * mistDensity) * radialWeight;
        float visibility = isUnoccluded * holeTransmission;
        litScatter += visibility * densityWeight;

        // Crepuscular cloud-hole beams: integrate along curvedCloudRay below cloudBase
        // so beam width strictly matches the cloud hole size and moves with cloudWind!
        float cloudY = sampleCloudWorld.y;
        float airLayer = 1.0 - smoothstep(cloudBase - 6.0, cloudBase + 3.0, cloudY);
        float valleyBoost = 1.0 + 0.45 * exp(-max(cloudY - SEA_OF_CLOUDS_ALTITUDE, 0.0) * 0.018);
        float airDensity = exp(-max(cloudY - 64.0, 0.0) / 210.0) * airLayer * valleyBoost;
        cloudScatter += visibility * airDensity * exp(-sampleDistance / 520.0) * (stepLen / 115.0);
    }

    float beamResponse = 1.0 - exp(-0.65 * litScatter * min(FOG_DENSITY, 1.35));

    // Smooth Anisotropic Mie Phase:
    // In clear weather (g = 0.54, cap = 2.5), beams focus cleanly around the sun/moon and through foliage.
    // In rain/thunder (g = 0.36, cap = 1.15), forward scattering is gently plateaued across the central cone
    // so crepuscular rays fan out evenly across the sky and valleys with ZERO dark hole and ZERO circular bullseye!
    float clearMie = min(henyeyGreensteinPhase(clamp(cosTheta, -1.0, 1.0), 0.54) * 11.0, (STYLE_SELECTION == 0) ? 2.5 : 2.8);
    float wetMie   = min(henyeyGreensteinPhase(clamp(cosTheta, -1.0, 1.0), 0.36) * 4.2, 1.15);
    float clearPhase = 0.24 + 0.76 * clearMie;
    float wetPhase   = 0.38 + 0.62 * wetMie;
    float phase      = mix(clearPhase, wetPhase, wetnessFactor);

    float enclosureGain = mix(1.20, 0.80, smoothstep(0.50, 0.95, eyeSkyFactor));

    float skyDamp = mix(1.0, 0.56, clamp(horizonFogWeight, 0.0, 1.0));
    float surfaceContrast = (1.0 - smoothstep(0.28, 0.76, sceneLuma) * 0.52) * skyDamp;

    float modeScale = (LIGHT_SHAFTS >= 2) ? 1.00 : 0.75;
    float timeScale = mix(0.88, 1.00, vDaylightFactor);
    float nearSurfaceFade = 1.0 - exp(-maxRayDist / 0.45);
    float exposedGain = mix(0.72, 0.58, wetnessFactor) * mix(1.0, 0.84, stormFactor);
    float structureGain = mix(1.0, exposedGain, smoothstep(0.35, 0.95, eyeSkyFactor));
    float distantOpenAir = smoothstep(12.0, 64.0, fullViewDist)
                         * smoothstep(0.35, 0.95, eyeSkyFactor);
    float localGain = cloudMode == 3 ? 1.0 : mix(1.0, mix(0.18, 0.08, wetnessFactor), distantOpenAir);

    float shaftIntensity = beamResponse * phase * enclosureGain * surfaceContrast *
                           ((STYLE_SELECTION == 0) ? 0.28 : 0.30) * modeScale * ATMOSPHERIC_SHAFT_STRENGTH * structureGain *
                           timeScale * nearSurfaceFade * sourceVisibility * localGain;

    float sBam, sMtn, sChr, sSnw, sArd, sSwp;
    evaluateSmoothBiomeWeights(sBam, sMtn, sChr, sSnw, sArd, sSwp);
    vec3 clearDayColor = (STYLE_SELECTION == 0)
        ? mix(vec3(1.02, 0.84, 0.56), vec3(1.08, 0.64, 0.38), vSunsetFactor) * 0.88
        : mix(vec3(1.05, 0.88, 0.60), vec3(1.12, 0.68, 0.40), vSunsetFactor) * 0.92;
    clearDayColor = mix(clearDayColor, vec3(0.62, 0.88, 0.72), sBam * 0.55);
    clearDayColor = mix(clearDayColor, vec3(0.68, 0.76, 0.54), sSwp * 0.60);
    clearDayColor = mix(clearDayColor, vec3(0.94, 0.72, 0.82), sChr * 0.55);
    clearDayColor = mix(clearDayColor, vec3(0.82, 0.88, 0.96), sSnw * 0.55);
    clearDayColor = mix(clearDayColor, vec3(0.76, 0.82, 0.88), sMtn * 0.48);

    vec3 stormDayColor = (STYLE_SELECTION == 0)
        ? vec3(0.62, 0.76, 0.82) * 0.90
        : vec3(0.54, 0.78, 0.96) * 0.94;
    stormDayColor = mix(stormDayColor, vec3(0.48, 0.74, 0.62), sBam * 0.55);
    stormDayColor = mix(stormDayColor, vec3(0.54, 0.62, 0.46), sSwp * 0.60);
    stormDayColor = mix(stormDayColor, vec3(0.76, 0.60, 0.70), sChr * 0.55);
    stormDayColor = mix(stormDayColor, vec3(0.72, 0.78, 0.88), sSnw * 0.55);

    vec3 dayShaftColor = mix(clearDayColor, stormDayColor, wetnessFactor * 0.78);
    dayShaftColor = mix(dayShaftColor, vec3(0.54, 0.52, 0.50), evaluatePaleGardenWeight() * 0.85);

    vec3 nightShaftColor = (STYLE_SELECTION == 0)
        ? vec3(0.56, 0.68, 0.62) * 0.84
        : vec3(0.48, 0.76, 1.02) * 0.90;

    float wetBeamBoost = mix(0.20, 0.30, wetnessFactor) * mix(1.0, 0.90, stormFactor);
    float cloudBeam = cloudMode == 3 ? 0.0 : (1.0 - exp(-cloudScatter * 0.92)) * phase
                    * wetBeamBoost * modeScale * surfaceContrast
                    * timeScale * sourceVisibility * ATMOSPHERIC_SHAFT_STRENGTH;
    vec3 shaftColor = mix(nightShaftColor, dayShaftColor, vDaylightFactor);
    return shaftColor * clamp(shaftIntensity + cloudBeam, 0.0, 0.28);
    #endif
}

#if SUN_LENS_FLARE > 0
float lensGhost(vec2 uv, vec2 center, vec2 aspect, float radius) {
    float r = length((uv - center) * aspect);
    float disc = exp(-r * r / (radius * radius));
    float rimDistance = (r - radius * 0.72) / (radius * 0.16);
    float rim = exp(-rimDistance * rimDistance);
    return disc * 0.55 + rim * 0.45;
}

vec3 renderSunLensFlare(vec2 uv) {
    vec4 sunClip = gbufferProjection * vec4(vSunViewDir, 0.0);
    if (sunClip.w <= 0.0 || vSunWorldDir.y <= -0.03) return vec3(0.0);
    vec2 sunUV = sunClip.xy / sunClip.w * 0.5 + 0.5 + cameraJitter(frameCounter, vec2(viewWidth, viewHeight));
    if (any(lessThan(sunUV, vec2(0.0))) || any(greaterThan(sunUV, vec2(1.0)))) return vec3(0.0);

    float edgeFade = smoothstep(0.0, 0.10, sunUV.x) * smoothstep(0.0, 0.10, sunUV.y) *
                     smoothstep(0.0, 0.10, 1.0 - sunUV.x) * smoothstep(0.0, 0.10, 1.0 - sunUV.y);
    if (edgeFade <= 0.001) return vec3(0.0);

    vec2 size = vec2(textureSize(depthtex0, 0));
    vec2 aspect = vec2(size.x / size.y, 1.0);
    vec2 relative = (uv - sunUV) * aspect;
    float r = length(relative);
    vec2 outwardVector = (sunUV - vec2(0.5)) * aspect + vec2(0.0001, 0.0);
    vec2 outward = outwardVector / max(length(outwardVector), 0.0001);
    float arc = smoothstep(-0.30, 0.48, dot(relative / max(r, 0.0001), outward));
    float ringRadius = (STYLE_SELECTION == 0) ? 0.14 : 0.17;
    float width = (STYLE_SELECTION == 0) ? 0.0045 : 0.0055;
    vec2 towardCenter = vec2(0.5) - sunUV;
    vec2 ghostCenterA = sunUV + towardCenter * 0.78;
    vec2 ghostCenterB = sunUV + towardCenter * 1.42;
    vec2 cameraArcCenter = vec2(0.5) + towardCenter * 0.65;
    float cameraRadius = (STYLE_SELECTION == 0) ? 0.095 : 0.11;
    float cameraWidth = width * 0.85;
    vec2 cameraRelative = (uv - cameraArcCenter) * aspect;
    float cameraR = length(cameraRelative);
    if (abs(r - ringRadius) > width * 4.0 &&
        abs(cameraR - cameraRadius) > cameraWidth * 4.0 &&
        length((uv - ghostCenterA) * aspect) > 0.14 &&
        length((uv - ghostCenterB) * aspect) > 0.14) return vec3(0.0);
    float skyVisibility = step(0.99999, texture(depthtex0, sunUV).r);
#if SUN_LENS_FLARE >= 2
    vec2 occlusionStep = 2.0 / size;
    skyVisibility += step(0.99999, texture(depthtex0, clamp(sunUV + vec2(occlusionStep.x, 0.0), 0.0, 1.0)).r);
    skyVisibility += step(0.99999, texture(depthtex0, clamp(sunUV - vec2(occlusionStep.x, 0.0), 0.0, 1.0)).r);
    skyVisibility += step(0.99999, texture(depthtex0, clamp(sunUV + vec2(0.0, occlusionStep.y), 0.0, 1.0)).r);
    skyVisibility += step(0.99999, texture(depthtex0, clamp(sunUV - vec2(0.0, occlusionStep.y), 0.0, 1.0)).r);
    skyVisibility *= 0.2;
#endif
    float visibility = skyVisibility * edgeFade * vDaylightFactor *
        smoothstep(-0.03, 0.10, vSunWorldDir.y) * (1.0 - max(rainStrength, rainFactor) * 0.95) * (1.0 - thunderStrength * 0.95);
    float flareRain, flareStorm, flareFlash;
    evaluateWeatherState(flareRain, flareStorm, flareFlash);
    int flareMode = (CLOUD_TYPE == 0) ? (STYLE_SELECTION == 0 ? 1 : 2) : CLOUD_TYPE;
    visibility *= cloudLightTransmission(cameraPosition, vSunWorldDir, frameTimeCounter, flareMode, flareRain, flareStorm);
    visibility *= (SUN_LENS_FLARE == 1) ? 0.28 : 0.70;
    if (visibility <= 0.001) return vec3(0.0);
    vec3 rainbowDistance = (vec3(r - ringRadius) + vec3(-width * 0.65, 0.0, width * 0.65)) / width;
    vec3 rainbow = exp(-rainbowDistance * rainbowDistance);
    vec3 tint = (STYLE_SELECTION == 0) ? vec3(0.72, 0.82, 0.70) : vec3(1.00, 0.84, 1.00);
    vec3 flare = rainbow * tint * arc * ((STYLE_SELECTION == 0) ? 0.12 : 0.17);

    vec3 cameraRainbowDistance = (vec3(cameraR - cameraRadius) +
        vec3(cameraWidth * 0.65, 0.0, -cameraWidth * 0.65)) / cameraWidth;
    vec3 cameraRainbow = exp(-cameraRainbowDistance * cameraRainbowDistance);
    float cameraArc = smoothstep(-0.30, 0.38,
        dot(cameraRelative / max(cameraR, 0.0001), -outward));
    flare += cameraRainbow * tint * cameraArc * ((STYLE_SELECTION == 0) ? 0.06 : 0.09);

    float ghostA = lensGhost(uv, ghostCenterA, aspect, 0.045);
    float ghostB = lensGhost(uv, ghostCenterB, aspect, 0.045);
    flare += ghostA * ((STYLE_SELECTION == 0) ? vec3(0.15, 0.20, 0.17) : vec3(0.23, 0.18, 0.27));
    flare += ghostB * ((STYLE_SELECTION == 0) ? vec3(0.13, 0.19, 0.17) : vec3(0.19, 0.23, 0.29));
    return flare * visibility * ((SUN_LENS_FLARE >= 2) ? 1.20 : 1.0);
}
#endif

#endif

#ifdef YUNMENG_CLOUD_PREPASS

void main() {
    outColor0 = vec4(0.0);
    outWaterEnvironment = vec4(0.0);
    outCloudLight = vec4(0.0);
    outFarCloudLight = vec4(0.0);
    int mode = (CLOUD_TYPE == 0) ? (STYLE_SELECTION == 0 ? 1 : 2) : CLOUD_TYPE;
    // Only the active world-map rectangle needs an extinction integration.
    ivec2 halfSize=max(ivec2(vec2(viewWidth,viewHeight)*0.5),ivec2(1));
    ivec2 mapSize=min(halfSize,ivec2(cloudLightCacheResolution()));
    if (mode!=3 && vLightWorldDir.y>0.01 && all(lessThan(ivec2(gl_FragCoord.xy),mapSize))) {
        vec2 mapOrigin=cloudLightCacheOrigin(vec2(mapSize),cameraPosition,vLightWorldDir);
        vec2 xz=mapOrigin+gl_FragCoord.xy/vec2(mapSize)*2048.0;
        float rain,storm,flash;
        evaluateWeatherState(rain,storm,flash);
        outCloudLight=vec4(cloudColumnOpticalDepth(vec3(xz.x,64.0,xz.y),vLightWorldDir,
            frameTimeCounter,mode,rain,storm),1.0);
    }
    ivec2 atlasSize=halfSize;
    ivec2 tileSize=min(mapSize,ivec2(atlasSize.x/2,atlasSize.y));
    if (mode!=3 && vLightWorldDir.y>0.01
        && cloudFarCacheWeight(vLightWorldDir)>0.0
        && tileSize.x>0 && tileSize.y>0
        && gl_FragCoord.x<float(tileSize.x*2) && gl_FragCoord.y<float(tileSize.y)) {
        float side=gl_FragCoord.x<float(tileSize.x) ? 1.0 : -1.0;
        vec2 localPixel=gl_FragCoord.xy-vec2(side<0.0 ? float(tileSize.x) : 0.0,0.0);
        vec2 mapOrigin=cloudFarCacheOrigin(vec2(mapSize),vec2(tileSize),cameraPosition,vLightWorldDir,side);
        vec2 xz=mapOrigin+localPixel/vec2(mapSize)*2048.0;
        float rain,storm,flash;
        evaluateWeatherState(rain,storm,flash);
        vec2 nearOrigin=cloudLightCacheOrigin(vec2(mapSize),cameraPosition,vLightWorldDir);
        vec2 nearPixel=(xz-nearOrigin)/2048.0*vec2(mapSize)-0.5;
        // Consumers use the near map's interior first. Its overlap is not
        // integrated again; four guard texels keep bilinear edge taps valid.
        if (any(lessThan(nearPixel,vec2(4.0)))
            || any(greaterThan(nearPixel,vec2(mapSize)-5.0))) {
            outFarCloudLight=vec4(cloudColumnOpticalDepth(vec3(xz.x,64.0,xz.y),vLightWorldDir,
                frameTimeCounter,mode,rain,storm),1.0);
        }
    }
    float depth = texture(depthtex0, vTexCoord).r;
    vec3 viewPos = reconstructViewPos(vTexCoord, depth);
    vec3 ray = normalize(viewPos);
    vec3 worldRay = normalize(mat3(gbufferModelViewInverse) * ray);
    vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
    if (isEyeInWater == 1) {
        bool surface = depth < 0.999999 && abs(texture(colortex1, vTexCoord).a - 0.90) < 0.05;
        if ((surface || (depth >= 0.999999 && texture(depthtex1, vTexCoord).r >= 0.999999)) && !isUnderwaterSurfaceCoveredByIce(vTexCoord, worldPos - cameraPosition)) {
            // Refract overhead sky & clouds through the multi-scale trochoidal wave field (waterSurfaceWaves)
            // so the underwater ceiling shares the exact organic wave facets of the surface without sine-band stripes.
            float t = frameTimeCounter * WIND_SPEED;
            vec2 waveCoord = surface ? worldPos.xz : (cameraPosition.xz + worldRay.xz * (8.0 / max(worldRay.y, 0.08)));
            float approxFootprint = surface ? clamp(length(viewPos) * 0.015, 0.02, 0.85) : 0.12;
            vec3 waveField = waterSurfaceWaves(waveCoord, t, approxFootprint);
            vec2 waveRefract = waveField.xy * 1.15 * smoothstep(0.02, 0.45, max(worldRay.y, 0.0));
            vec3 exitRay = normalize(vec3(worldRay.x + waveRefract.x, max(worldRay.y, 0.03), worldRay.z + waveRefract.y));
            if (worldRay.y > 0.0) {
                vec3 exitView = normalize(transpose(mat3(gbufferModelViewInverse)) * exitRay);
                vec3 environment = evaluateUnifiedSky(exitRay, exitView);
                applyCelestialsAndAurora(environment, exitRay, frameTimeCounter, NIGHT_AURORA);
                if (mode != 3) {
                    vec4 cloud = renderYunMengVolumetricClouds(exitRay, exitView,
                        cameraPosition, frameTimeCounter, environment, 0.0, 4200.0, mode, false);
                    environment = mix(environment, cloud.rgb, cloud.a);
                }
                if (cameraPosition.y >= AURORA_BASE_Y)
                    environment += renderNightYunMengAurora(exitRay, frameTimeCounter, NIGHT_AURORA, 0.0);
                outWaterEnvironment = vec4(environment, max(length(viewPos), 0.001));
            }
        }
        return;
    }
    vec2 reflectionUV=vTexCoord;
    float reflectionDepth=depth;
    // A thin water row can fall between half-resolution pixel centers. Preserve
    // a real water sample in the corresponding 2x2 full-resolution footprint.
    float centerReflTag = texture(colortex1, vTexCoord).a;
    if (depth>=0.999999 || (abs(centerReflTag-0.90)>=0.05 && abs(centerReflTag-0.825)>=0.015)) {
        ivec2 fullSize=textureSize(depthtex0,0);
        ivec2 base=ivec2(floor(vTexCoord*vec2(fullSize)-0.5));
        for (int y=0;y<2;++y) for (int x=0;x<2;++x) {
            ivec2 q=clamp(base+ivec2(x,y),ivec2(0),fullSize-1);
            float z=texelFetch(depthtex0,q,0).r;
            float qTag=texelFetch(colortex1,q,0).a;
            if (z<0.999999 && (abs(qTag-0.90)<0.05 || abs(qTag-0.825)<0.015)) {
                reflectionUV=(vec2(q)+0.5)/vec2(fullSize);reflectionDepth=z;
            }
        }
    }
    float activeReflTag = texture(colortex1, reflectionUV).a;
    if (reflectionDepth < 0.999999 && (abs(activeReflTag - 0.90) < 0.05 || abs(activeReflTag - 0.825) < 0.015)) {
        vec3 viewPos=reconstructViewPos(reflectionUV,reflectionDepth);
        vec3 ray=normalize(viewPos);
        vec3 worldPos=(gbufferModelViewInverse*vec4(viewPos,1.0)).xyz+cameraPosition;
        vec3 normal = normalize(texture(colortex1, reflectionUV).rgb * 2.0 - 1.0);
        vec3 reflectionNormalWorld = mat3(gbufferModelViewInverse) * normal;
        bool isIceRefl = abs(activeReflTag - 0.825) < 0.015;
        if (isIceRefl && reflectionNormalWorld.y <= 0.85) return;
        bool slopedTop = !isIceRefl && waterIsSlopedTop(texture(colortex2,reflectionUV).a);
        if (!slopedTop && reflectionNormalWorld.y > 0.85) {
            vec3 waterPlayer = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
            // Metadata is sampled at half resolution. Average its full-resolution
            // footprint before the nonlinear sky reflection, rather than choosing
            // one animated wave facet and magnifying its sky/cloud changes.
            ivec2 normalSize = textureSize(colortex1, 0);
            ivec2 normalBase = ivec2(floor(reflectionUV * vec2(normalSize) - 0.5));
            vec3 normalSum = vec3(0.0);
            float normalWeight = 0.0;
            for (int y = 0; y < 2; ++y) for (int x = 0; x < 2; ++x) {
                ivec2 q = clamp(normalBase + ivec2(x, y), ivec2(0), normalSize - 1);
                vec4 normalTag = texelFetch(colortex1, q, 0);
                if (abs(normalTag.a - 0.90) >= 0.05 && abs(normalTag.a - 0.825) >= 0.015) continue;
                vec3 tapNormal = normalize(normalTag.xyz * 2.0 - 1.0);
                if (dot(tapNormal, normal) < 0.8) continue;
                vec2 tapUV = (vec2(q) + 0.5) / vec2(normalSize);
                float tapDepth = texelFetch(depthtex0, q, 0).r;
                vec3 tapPlayer = (gbufferModelViewInverse * vec4(reconstructViewPos(tapUV, tapDepth), 1.0)).xyz;
                if (tapDepth >= 0.999999 || abs(tapPlayer.y - waterPlayer.y) > 0.25) continue;
                normalSum += tapNormal;
                normalWeight += 1.0;
            }
            // A lone valid tap is the original fragment. Keep its normal
            // exactly, including at shore and water-layer boundaries.
            if (normalWeight > 1.0) normal = normalize(normalSum);
        }
        vec3 reflectedView = normalize(reflect(ray, normal));
        vec3 reflectedWorld = normalize(mat3(gbufferModelViewInverse) * reflectedView);
        if (slopedTop || reflectionNormalWorld.y <= 0.85) {
            reflectedWorld = normalize(vec3(reflectedWorld.x, max(reflectedWorld.y, 0.22), reflectedWorld.z));
            reflectedView  = normalize(transpose(mat3(gbufferModelViewInverse)) * reflectedWorld);
        }
        vec3 environment = evaluateUnifiedSky(reflectedWorld, reflectedView);
        // Preserve the broad celestial glow used on water, without a sharp disc.
        vec3 reflectedAurora = renderWorldAurora(worldPos, reflectedWorld, frameTimeCounter, NIGHT_AURORA, 1.0, 1152.0);
        if (worldPos.y < AURORA_BASE_Y) environment += reflectedAurora;
        #if WATER_REFLECTIONS > 0
        if (mode != 3) {
            vec4 reflectedCloud = renderYunMengVolumetricClouds(reflectedWorld, reflectedView,
                worldPos, frameTimeCounter, environment, 0.0, 4200.0, mode, true);
            environment = mix(environment, reflectedCloud.rgb, reflectedCloud.a);
        }
        #endif
        if (worldPos.y >= AURORA_BASE_Y) environment += reflectedAurora;
        float waterY=(gbufferModelViewInverse*vec4(viewPos,1.0)).y;
        // Negative height is a stable horizontal-surface identifier at grazing
        // angles. Positive distance remains the sheet/above-eye fallback.
        float support=!slopedTop && reflectionNormalWorld.y>0.85 && waterY<0.0 ? min(waterY,-0.0001) : length(viewPos);
        outWaterEnvironment = vec4(environment, support);
    }
    if (mode == 3) return;
    bool belowLayer = cameraPosition.y < (CLOUD_ALTITUDE - 16.0) && worldPos.y < (CLOUD_ALTITUDE - 16.0);
    float trueFarBorder = smoothstep(far * 0.88, far * 0.98, length((worldPos - cameraPosition).xz)) * (1.0 - evaluatePaleGardenWeight());
    float rawBorder = depth >= 0.999999 ? 1.0 : min(terrainSkyBlend(worldPos - cameraPosition), trueFarBorder);
    // Only allow background horizon clouds at the true far chunk-unloading edge (>88% far border, never in Pale Garden mist)
    // so solid mid-ground hills and trees never look see-through with background clouds drawn over them.
    float backgroundBlend = depth >= 0.999999 ? 1.0 : smoothstep(0.88, 0.995, rawBorder);
    if (depth < 0.999999 && belowLayer && backgroundBlend <= 0.001) return;
    float maxDistance = (depth >= 0.999999 || (belowLayer && backgroundBlend > 0.001)) ? 4200.0 : length(viewPos);
    vec3 sky = evaluateUnifiedSky(worldRay, ray);
    vec4 cloud = renderYunMengVolumetricClouds(worldRay, ray, cameraPosition, frameTimeCounter, sky, 0.0, maxDistance, mode, false);
    // Premultiply before interpolation to avoid dark fringes at cloud/sky edges.
    float fogVisibility = (depth < 0.999999 && belowLayer) ? (backgroundBlend * backgroundBlend) : 1.0;
    outColor0 = vec4(cloud.rgb * cloud.a, cloud.a) * fogVisibility;
}
#else
uniform sampler2D colortex8;
vec4 resolveClouds(float depth, float viewDist) {
    ivec2 size = textureSize(colortex8, 0);
    vec2 pixel = vTexCoord * vec2(size) - 0.5;
    ivec2 center = ivec2(floor(pixel + 0.5));
    vec4 sum = vec4(0.0);
    float weights = 0.0;
    for (int y=-1; y<=1; ++y) for (int x=-1; x<=1; ++x) {
        ivec2 q = clamp(center + ivec2(x,y), ivec2(0), size-1);
        vec2 uv = (vec2(q)+0.5)/vec2(size);
        float sampleDepth = texture(depthtex0, uv).r;
        bool sky = depth >= 0.999999;
        if (sky != (sampleDepth >= 0.999999)) continue;
        float w = exp(-dot(vec2(q)-pixel, vec2(q)-pixel)*1.65);
        if (!sky) {
            float distance = length(reconstructViewPos(uv, sampleDepth));
            w *= exp(-abs(distance-viewDist)/max(viewDist*0.025, 0.5));
        }
        sum += texelFetch(colortex8, q, 0)*w;
        weights += w;
    }
    if (weights > 0.001) return sum / weights;
    // Never bleed a half-resolution sky cloud texel onto foreground tree/terrain silhouettes when below clouds!
    if (depth < 0.999999 && cameraPosition.y < (CLOUD_ALTITUDE - 16.0)) return vec4(0.0);
    return texelFetch(colortex8, clamp(center, ivec2(0), size-1), 0);

}
void main() {
#if LIGHT_SHAFTS > 0
    outAtmosphericShafts = vec4(0.0);
#endif
    vec4 sceneColor = texture(colortex0, vTexCoord);
    float depth0 = texture(depthtex0, vTexCoord).r;
    float sceneMaterial = texture(colortex1, vTexCoord).a;

    vec3 viewPos   = reconstructViewPos(vTexCoord, depth0);
    vec3 playerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 worldPos  = playerPos + cameraPosition;
    float viewDist = length(viewPos);

    vec3 viewRayDir  = normalize(viewPos);
    vec3 worldRayDir = normalize(mat3(gbufferModelViewInverse) * viewRayDir);
    float cosTheta   = dot(viewRayDir, vLightViewDir);

    vec3 finalRadiance = sceneColor.rgb;

    if (isEyeInWater == 1) {
        float upGradient = clamp(worldRayDir.y * 0.5 + 0.5, 0.0, 1.0);
        vec3 uwFogColor;
        float uwFogDensity;

        float bStrengthUW = clamp(BIOME_TINT_STRENGTH, 0.0, 1.5);
        float wSwampUW    = clamp(inSwampBiome   * bStrengthUW, 0.0, 1.0);
        float wSnowyUW    = clamp(inSnowyBiome   * bStrengthUW, 0.0, 1.0);
        float wBambooUW   = clamp(inBambooJungle * bStrengthUW, 0.0, 1.0);
        float wCherryUW   = clamp(inCherryGrove  * bStrengthUW, 0.0, 1.0);
        // Detect vanilla water_fog_color murkiness (Swamp #232317 & Mangrove Swamp #4D7A60 have G >= B, whereas default #050533 has B >> G)
        float vanillaSwampMurk = clamp((fogColor.g - fogColor.b * 0.82) * 4.5, 0.0, 1.0) * min(bStrengthUW, 1.25);
        float effSwampUW       = max(wSwampUW, vanillaSwampMurk);
        float fogPeakUW        = max(fogColor.r, max(fogColor.g, fogColor.b));
        float fogMinUW         = min(fogColor.r, min(fogColor.g, fogColor.b));
        float paleGardenUW     = (1.0 - smoothstep(0.04, 0.18, (fogPeakUW - fogMinUW) / max(fogPeakUW, 1e-4)))
                               * smoothstep(0.18, 0.35, fogPeakUW) * min(bStrengthUW, 1.25);

        if (STYLE_SELECTION == 0) {
            vec3 deepSumiTeal = vec3(0.10, 0.22, 0.24);
            vec3 upperCeladon = vec3(0.32, 0.52, 0.50);
            // Swamp / Mangrove Swamp murky Jiangnan tea-moss underwater fog
            deepSumiTeal = mix(deepSumiTeal, vec3(0.07, 0.13, 0.06), effSwampUW * 0.85);
            upperCeladon = mix(upperCeladon, vec3(0.22, 0.32, 0.16), effSwampUW * 0.85);
            // Snowy glacial indigo underwater fog
            deepSumiTeal = mix(deepSumiTeal, vec3(0.05, 0.12, 0.28), wSnowyUW * 0.65);
            upperCeladon = mix(upperCeladon, vec3(0.18, 0.34, 0.54), wSnowyUW * 0.65);
            // Bamboo & Cherry underwater tints
            upperCeladon = mix(upperCeladon, vec3(0.26, 0.56, 0.46), wBambooUW * 0.45);
            upperCeladon = mix(upperCeladon, vec3(0.38, 0.48, 0.54), wCherryUW * 0.42);
            // Pale Garden desaturated slate-ash underwater fog
            deepSumiTeal = mix(deepSumiTeal, vec3(0.10, 0.11, 0.12), paleGardenUW * 0.85);
            upperCeladon = mix(upperCeladon, vec3(0.26, 0.28, 0.29), paleGardenUW * 0.85);
            uwFogColor   = mix(deepSumiTeal, upperCeladon, pow(upGradient, 0.85)) * mix(0.22, 1.0, vDaylightFactor);
        } else {
            vec3 abyssalSapphire  = vec3(0.025, 0.16, 0.26);
            vec3 surfaceTurquoise = vec3(0.07, 0.38, 0.48);
            // Swamp / Mangrove Swamp murky olive-emerald underwater fog
            abyssalSapphire  = mix(abyssalSapphire,  vec3(0.045, 0.12, 0.055), effSwampUW * 0.85);
            surfaceTurquoise = mix(surfaceTurquoise, vec3(0.17,  0.31, 0.14),  effSwampUW * 0.85);
            // Snowy glacial cobalt underwater fog
            abyssalSapphire  = mix(abyssalSapphire,  vec3(0.02, 0.07, 0.28), wSnowyUW * 0.68);
            surfaceTurquoise = mix(surfaceTurquoise, vec3(0.08, 0.22, 0.56), wSnowyUW * 0.68);
            // Bamboo & Cherry underwater tints
            surfaceTurquoise = mix(surfaceTurquoise, vec3(0.10, 0.46, 0.40), wBambooUW * 0.45);
            surfaceTurquoise = mix(surfaceTurquoise, vec3(0.24, 0.38, 0.50), wCherryUW * 0.42);
            // Pale Garden desaturated ash underwater fog
            abyssalSapphire  = mix(abyssalSapphire,  vec3(0.08, 0.09, 0.10), paleGardenUW * 0.85);
            surfaceTurquoise = mix(surfaceTurquoise, vec3(0.22, 0.24, 0.25), paleGardenUW * 0.85);
            uwFogColor   = mix(abyssalSapphire, surfaceTurquoise, pow(upGradient, 0.82)) * mix(0.20, 1.0, vDaylightFactor);
        }
        // Blend subtle vanilla water_fog_color chroma so Warm Oceans and modded biomes shift naturally
        vec3 linVanillaUwFog = pow(max(fogColor, vec3(0.001)), vec3(2.2));
        uwFogColor = mix(uwFogColor, linVanillaUwFog * 1.30, 0.24 * min(bStrengthUW, 1.25));

        // Vanilla thickens underwater fog in Swamps & Mangrove Swamps (lowering underwater visibility distance)
        float vanillaUwPull = (fogEnd > 1.0 && fogEnd < 90.0) ? clamp((90.0 - fogEnd) / 65.0, 0.0, 1.0) : 0.0;
        uwFogDensity = mix(0.052, 0.108, max(effSwampUW * 0.88, max(paleGardenUW * 0.65, vanillaUwPull * 0.75)));

        // Retain diffuse underwater visibility in overcast, while its direct
        // shafts below use the spatially varying incident cloud transmission.
        float uwRain, uwStorm, uwFlash;
        evaluateWeatherState(uwRain, uwStorm, uwFlash);
        uwFogColor *= mix(1.0, 0.82, uwRain) * mix(1.0, 0.82, uwStorm);
        bool waterSurface = depth0 < 0.999999 && abs(sceneMaterial - 0.90) < 0.05;
        float lateralExit = waterSurface ? texture(colortex2, vTexCoord).a : 0.0;
        if ((waterSurface || (depth0 >= 0.999999 && texture(depthtex1, vTexCoord).r >= 0.999999)) && !isUnderwaterSurfaceCoveredByIce(vTexCoord, playerPos)) {
            vec4 environment = reconstructWaterEnvironment(vTexCoord, viewDist);
            // Continuous underwater ceiling transmission:
            // - Avoids the harsh circular Snell's window cutoff and avoids per-triangle polygon facets on slopes,
            // - While keeping a genuine watery tint, grazing internal reflection, and visible surface ripple pattern
            //   so the water surface overhead looks like real liquid rather than empty air!
            float upCos = clamp(worldRayDir.y, 0.0, 1.0);
            float grazingFresnel = pow(1.0 - upCos, 2.4);
            float distanceFade   = exp(-viewDist * 0.028);

            // Tint the transmitted sky slightly with the water ceiling's jade/turquoise body
            vec3 waterFilteredSky = mix(environment.rgb, environment.rgb * (STYLE_SELECTION == 0 ? vec3(0.76, 0.95, 0.92) : vec3(0.68, 0.92, 1.02)) + uwFogColor * 0.22, 0.35 + 0.40 * grazingFresnel);

            // Evaluate organic multi-scale trochoidal wave facets & delicate silver-aqua internal reflection glints on the ceiling underside
            vec2 ceilingUV = waterSurface ? worldPos.xz : (cameraPosition.xz + worldRayDir.xz * (8.0 / max(upCos, 0.08)));
            float ceilingFootprint = waterSurface
                ? max(length(dFdx(worldPos.xz)), length(dFdy(worldPos.xz)))
                : clamp(viewDist * 0.018, 0.03, 0.90);
            float t = frameTimeCounter * WIND_SPEED;
            vec3 ceilingWave = waterSurfaceWaves(ceilingUV, t, ceilingFootprint);
            vec3 ceilingNormal = normalize(vec3(-ceilingWave.x * 1.35, -1.0, -ceilingWave.y * 1.35));

            // Internal reflection and sunlit/moonlit facet glints across the underside of the waves
            vec3 halfVec = normalize(-worldRayDir + vec3(vLightWorldDir.x, -abs(vLightWorldDir.y), vLightWorldDir.z));
            float facetGlint = pow(max(dot(ceilingNormal, halfVec), 0.0), 18.0) * 0.42
                             + smoothstep(0.004, 0.028, ceilingWave.z) * 0.24;
            vec3 rippleHighlight = (STYLE_SELECTION == 0 ? vec3(0.44, 0.70, 0.66) : vec3(0.24, 0.74, 0.86))
                                 * mix(0.24, 1.0, vDaylightFactor) * facetGlint * (0.32 + 0.45 * grazingFresnel) * distanceFade;

            float skyTransmission = smoothstep(0.04, 0.60, upCos) * (1.0 - grazingFresnel * 0.50) * mix(0.62, 0.18, lateralExit) * distanceFade;
            finalRadiance = mix(finalRadiance, waterFilteredSky, environment.a * skyTransmission);
            finalRadiance += rippleHighlight * (1.0 - lateralExit * 0.65);
        }

        // Animated flowing waterfall sheet detail when standing inside a waterfall looking at its sloped/vertical walls
        vec3 faceCross = cross(dFdx(worldPos), dFdy(worldPos));
        vec3 faceNormal = faceCross / max(length(faceCross), 1e-6);
        float acrossCoord = worldPos.x + worldPos.z * 0.87;
        vec2 flowCoord = vec2(acrossCoord, worldPos.y);
        float footprint = max(length(dFdx(flowCoord)), length(dFdy(flowCoord)));
        if (lateralExit > 0.01) {
            float flow = waterFallField(worldPos, faceNormal, frameTimeCounter * WIND_SPEED).z;
            flow = mix(flow, 0.5, smoothstep(0.14, 0.55, footprint));
            float markings = smoothstep(0.28, 0.72, flow);
            float opacity = lateralExit * (STYLE_SELECTION == 0
                ? mix(0.45, 0.75, markings) : mix(0.42, 0.72, markings));
            vec3 sheetTint = uwFogColor * (STYLE_SELECTION == 0
                ? vec3(0.68, 0.92, 1.04) : vec3(0.76, 1.02, 1.16));
            sheetTint *= mix(0.62, 1.38, markings);
            finalRadiance = mix(finalRadiance, sheetTint, opacity);
        }

        // Natural underwater depth fog across both terrain and the water ceiling,
        // with Total Internal Reflection (TIR) grazing convergence on the water ceiling so the ceiling edge
        // blends seamlessly into distant underwater terrain without a horizon step.
        float upLookFogRelief = (1.0 - lateralExit) * smoothstep(0.15, 0.75, max(worldRayDir.y, 0.0)) * 0.32;
        float baseUwFog = clamp(1.0 - exp(-viewDist * uwFogDensity * (1.0 - upLookFogRelief)), 0.0, 0.96);
        float ceilingGrazingFog = pow(1.0 - smoothstep(0.02, 0.42, clamp(worldRayDir.y, 0.0, 1.0)), 1.5) * (1.0 - lateralExit);
        float uwFogFactor = (depth0 >= 0.999999)
            ? (0.96 - upLookFogRelief * 0.65)
            : (waterSurface ? mix(baseUwFog, 0.95, ceilingGrazingFog * 0.90) : baseUwFog);
        finalRadiance = mix(finalRadiance * 0.88, uwFogColor, uwFogFactor);
        finalRadiance += computeUnderwaterLightShafts(viewPos, vLightWorldDir, cosTheta);

        outColor0 = vec4(finalRadiance, 1.0);
        return;
    }

    int activeCloudMode = (CLOUD_TYPE == 0) ? (STYLE_SELECTION == 0 ? 1 : 2) : CLOUD_TYPE;

    vec3 unifiedSky = evaluateUnifiedSky(worldRayDir, viewRayDir);
    float celestialDiscMask = 0.0;
    float horizonFogWeight  = 1.0;

    vec3 skyAuroraLight = vec3(0.0);
    vec3 celestialArtAndStars = vec3(0.0);
    float endWeight = clamp(inTheEnd, 0.0, 1.0);
    if (depth0 >= 0.999999) {
        vec3 skyWithCelestials = unifiedSky;
        if (endWeight < 0.999) {
            float sunStarOcc  = smoothstep(0.9945, 0.9975, dot(worldRayDir, vSunWorldDir));
            float wetnessNow, stormNow, flashNow;
            evaluateWeatherState(wetnessNow, stormNow, flashNow);
            // Keep stars visible during twilight/sunset as well as night
            float starTwilightVis = (1.0 - smoothstep(-0.09, 0.01, vSunWorldDir.y)) * (1.0 - evaluatePaleGardenWeight() * 0.90);
            vec3 starAdd = sceneColor.rgb * starTwilightVis * (1.0 - wetnessNow * 0.96)
                         * (1.0 - sunStarOcc) * smoothstep(-0.20, -0.02, worldRayDir.y);
            skyWithCelestials += starAdd;
            celestialDiscMask = applyTexturedCelestialBodies(skyWithCelestials, worldRayDir);
            celestialArtAndStars = max(skyWithCelestials - unifiedSky, vec3(0.0)) * (1.0 - endWeight);
            if (cameraPosition.y < AURORA_BASE_Y) {
                skyAuroraLight = renderNightYunMengAurora(worldRayDir, frameTimeCounter, NIGHT_AURORA, 1.0 - celestialDiscMask) * (1.0 - endWeight);
                skyWithCelestials += skyAuroraLight;
            }
        }
        if (endWeight > 0.001) {
            vec3 endSkyDome = renderYunMengEndSkyDome(worldRayDir, viewRayDir, unifiedSky);
            skyWithCelestials = mix(skyWithCelestials, endSkyDome, endWeight);
        }
        finalRadiance = skyWithCelestials;
    } else {
        vec4 mistAndBorder = computeValleyMistAndBorderFog(worldPos, playerPos, viewDist, unifiedSky, worldRayDir, viewRayDir);
        // Held items are camera foreground, outside the world fog volume; emissive eyes pierce near/mid fog.
        if (abs(sceneMaterial-0.12)<0.007) mistAndBorder.a=0.0;
        if (sceneMaterial > 0.335 && sceneMaterial < 0.475) mistAndBorder.a *= smoothstep(18.0, 64.0, viewDist) * 0.35;
        horizonFogWeight = mistAndBorder.a;
        finalRadiance = mix(finalRadiance, mistAndBorder.rgb, mistAndBorder.a);
    }

    vec3 foregroundAurora = vec3(0.0);
    if ((cameraPosition.y >= AURORA_BASE_Y || depth0 < 0.999999) && endWeight < 0.99) {
        if (abs(sceneMaterial - 0.12) >= 0.007)
            foregroundAurora = renderWorldAurora(cameraPosition, worldRayDir, frameTimeCounter,
                NIGHT_AURORA, 1.0, depth0 >= 0.999999 ? 1152.0 : viewDist);
        if (cameraPosition.y < AURORA_BASE_Y) finalRadiance += foregroundAurora;
    }

    // Translucent Celestial Veil & Aurora Scattering:
    // Soften cloud opacity over the Sun/Moon disc and forward-scatter the Sun/Moon artwork and stars
    // through the clouds so they stay softly visible instead of getting harshly covered up!
    bool needsCloudTrace = (depth0 >= 0.999999) || (cameraPosition.y > CLOUD_ALTITUDE - 16.0) || (worldPos.y > CLOUD_ALTITUDE - 16.0)
                        || (terrainSkyBlend(playerPos) > 0.88 && length(playerPos.xz) > far * 0.88 && evaluatePaleGardenWeight() < 0.5);
    if (activeCloudMode != 3 && needsCloudTrace && endWeight < 0.99) {
        vec4 volClouds = resolveClouds(depth0, viewDist);
        // True Cloud-In-Front-Of-Celestial Depth Ordering with Thin-Edge Backlit Translucency:
        // Keep full cloud opacity (volClouds.a) so Wuxia Smooth and Voxel clouds clearly pass IN FRONT OF
        // the Sun atlas, Moon atlas, and stars, while allowing thin cloud margins (1.0 - volClouds.a) to
        // transmit a soft backlit glimpse of the celestial artwork!
        float effCloudAlpha = clamp(volClouds.a, 0.0, 1.0);
        vec3 effCloudPremul = volClouds.rgb;

        float thinMarginTrans = (1.0 - effCloudAlpha) * (1.0 - effCloudAlpha) * 0.38 + 0.08;
        vec3 celestialTrans = celestialArtAndStars * effCloudAlpha * thinMarginTrans;
        vec3 auroraScatter  = skyAuroraLight * effCloudAlpha * (0.38 + 0.38 * (1.0 - effCloudAlpha));
        finalRadiance = finalRadiance * (1.0 - effCloudAlpha) + effCloudPremul + celestialTrans + auroraScatter;
    }

    if (cameraPosition.y >= AURORA_BASE_Y) finalRadiance += foregroundAurora;

    vec3 shaftViewPos = viewPos;
    float shaftDepth = depth0;
    float shaftMaterial = sceneMaterial;
    if (abs(shaftMaterial - 0.16) < 0.02) {
        vec2 texel = 3.0 / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
        float bgDepth = max(
            max(texture(depthtex1, vTexCoord + vec2(texel.x, 0.0)).r,
                texture(depthtex1, vTexCoord - vec2(texel.x, 0.0)).r),
            max(texture(depthtex1, vTexCoord + vec2(0.0, texel.y)).r,
                texture(depthtex1, vTexCoord - vec2(0.0, texel.y)).r)
        );
        if (bgDepth > depth0) {
            shaftDepth = bgDepth;
            shaftViewPos = reconstructViewPos(vTexCoord, shaftDepth);
        }
    } else if (abs(shaftMaterial - 0.90) >= 0.05 && abs(shaftMaterial - 0.12) >= 0.007
               && abs(shaftMaterial - 0.10) >= 0.007) {
        // Visible entity fragments are opaque, including skin outer layers.
        // Their air ray must end at the model rather than a surface behind it.
        float opaqueDepth = texture(depthtex1, vTexCoord).r;
        if (opaqueDepth > depth0) {
            shaftDepth = opaqueDepth;
            shaftViewPos = reconstructViewPos(vTexCoord, shaftDepth);
        }
    }
    if (abs(shaftMaterial - 0.12) >= 0.007 && endWeight < 0.99) {
        finalRadiance = applyAtmosphericPrecipitation(finalRadiance, unifiedSky, worldRayDir, depth0 >= 0.999999 ? far : viewDist);
    }
    float sceneLuma = dot(finalRadiance, vec3(0.2126, 0.7152, 0.0722));
    vec3 lightShafts = (endWeight < 0.99)
        ? computeVolumetricLightShafts(shaftViewPos, shaftDepth, cosTheta, sceneLuma, horizonFogWeight) * (1.0 - endWeight)
        : vec3(0.0);
    finalRadiance += lightShafts;
#if LIGHT_SHAFTS > 0
    outAtmosphericShafts = vec4(lightShafts, 0.0);
#endif
#if SUN_LENS_FLARE > 0
    if (endWeight < 0.99) {
        finalRadiance += renderSunLensFlare(vTexCoord) * (1.0 - endWeight);
    }
#endif

    outColor0 = vec4(finalRadiance, 1.0);
}

#endif
