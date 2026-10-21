#include "/lib/temporal_jitter.glsl"
// Build 2 performance update: scalable cloud, shadow and shoreline settings.
/* =============================================================================
 * composite1.fsh â€” Unified 3D Volumetric Cloud Engine, Atmosphere & Night Sky
 * ============================================================================= */

#define STYLE_SELECTION 1             // [0 1] 0: Guofeng Ink, 1: Xianxia Mist
#define CLOUD_QUALITY 1               // [0 1 2 3] Low, Medium, High, Ultra
#define CLOUD_TYPE 0                  // [0 1 2 3] 0: Auto (By Style), 1: Shanshui 3D, 2: Cumulus 3D, 3: Off
#define NIGHT_AURORA 0                // [0 1 2 3] 0: Auto (By Style), 1: Xianxia Celestial, 2: Guofeng Jade Silk, 3: Off
#define FOG_DENSITY 1.00              // [0.25 0.50 0.75 1.00 1.15 1.25 1.50 1.80 2.20]
#include "/lib/atmospheric_options.glsl"
#define BIOME_TINT_STRENGTH 1.00      // [0.00 0.50 0.75 1.00 1.15 1.25 1.50]
#define SEA_OF_CLOUDS_ALTITUDE 76.0   // [56.0 68.0 76.0 88.0 104.0 120.0]
#define SEA_OF_CLOUDS_THICKNESS 22.0  // [12.0 18.0 22.0 28.0 36.0]
#define SUN_SIZE 1.00                 // [0.50 0.75 1.00 1.25 1.50 2.00]
#define SUN_LENS_FLARE 1              // [0 1 2] Off, Soft, Full
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
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex1;
uniform sampler2D noisetex;
uniform sampler2D celestialTex;
uniform sampler2D guofengMoonTex;
uniform sampler2D xianxiaMoonTex;
#include "/lib/shadow_coverage.glsl"
#include "/lib/water_optics.glsl"

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
uniform float fogEnd;
uniform float rainStrength;
uniform float rainFactor;
uniform float thunderStrength;
uniform vec4 lightningBoltPosition;
uniform vec3 skyColor;
uniform float eyeAltitude;
uniform int frameCounter;
uniform int isEyeInWater;
uniform int moonPhase;

uniform float inBambooJungle;
uniform float inMountainBiome;
uniform float inCherryGrove;
uniform float eyeSkyFactor;
#ifndef YUNMENG_CLOUD_PREPASS
#define YUNMENG_CLOUD_LIGHT_CACHE
#include "/lib/water_environment.glsl"
#endif
#include "/lib/cloud_field.glsl"


#ifdef YUNMENG_CLOUD_PREPASS
/* RENDERTARGETS: 8,9,10 */
/* const int colortex8Format = RGBA16F; */
/* const int colortex9Format = RGBA16F; */
const vec4 colortex8ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex9ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
layout(location = 1) out vec4 outWaterEnvironment;
layout(location = 2) out vec4 outCloudLight;
/* const int colortex10Format = RGBA16F; */
const vec4 colortex10ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
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
    // Warmth survives sunset briefly, then fades out before deep night.
    return smoothstep(-0.24, -0.06, vSunWorldDir.y)
         * (1.0 - smoothstep(0.03, 0.22, vSunWorldDir.y));
}

void getLuminousCloudPalette(out vec3 cDeepFold, out vec3 cMidFold, out vec3 cWarmMid, out vec3 cSunCrest, out vec3 silverRimColor) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);

    if (STYLE_SELECTION == 0) {
        // Guofeng Ink (Shanshui): QinglÃ¼ mineral jade-teal shadow folds & warm Xuan-paper ivory crests.
        // Night palette uses luminous moonlit silver-celadon so nocturnal clouds are clearly readable.
        vec3 dayDeep    = vec3(0.21, 0.31, 0.33);
        vec3 sunsetDeep = vec3(0.35, 0.27, 0.36);
        vec3 nightDeep  = vec3(0.055, 0.098, 0.150);

        vec3 dayMid     = vec3(0.55, 0.65, 0.66);
        vec3 sunsetMid  = vec3(0.68, 0.46, 0.38);
        vec3 nightMid   = vec3(0.135, 0.220, 0.295);

        vec3 dayWarm    = vec3(0.79, 0.84, 0.80);
        vec3 sunsetWarm = vec3(0.92, 0.65, 0.44);
        vec3 nightWarm  = vec3(0.240, 0.360, 0.445);

        vec3 dayCrest    = vec3(0.95, 0.94, 0.88);
        vec3 sunsetCrest = vec3(1.05, 0.80, 0.56);
        vec3 nightCrest  = vec3(0.370, 0.510, 0.590);

        cDeepFold = mix(nightDeep,  mix(dayDeep,  sunsetDeep,  vSunsetFactor), vDaylightFactor);
        cMidFold  = mix(nightMid,   mix(dayMid,   sunsetMid,   vSunsetFactor), vDaylightFactor);
        cWarmMid  = mix(nightWarm,  mix(dayWarm,  sunsetWarm,  vSunsetFactor), vDaylightFactor);
        cSunCrest = mix(nightCrest, mix(dayCrest, sunsetCrest, vSunsetFactor), vDaylightFactor);

        vec3 rainDeep  = mix(vec3(0.042, 0.075, 0.115), vec3(0.20, 0.28, 0.32), vDaylightFactor);
        vec3 rainMid   = mix(vec3(0.095, 0.158, 0.220), vec3(0.35, 0.44, 0.46), vDaylightFactor);
        vec3 rainWarm  = mix(vec3(0.170, 0.260, 0.335), vec3(0.51, 0.59, 0.59), vDaylightFactor);
        vec3 rainCrest = mix(vec3(0.260, 0.380, 0.465), vec3(0.68, 0.74, 0.72), vDaylightFactor);

        vec3 stormDeep  = mix(vec3(0.026, 0.048, 0.080), vec3(0.11, 0.17, 0.20), vDaylightFactor);
        vec3 stormMid   = mix(vec3(0.065, 0.112, 0.162), vec3(0.21, 0.28, 0.31), vDaylightFactor);
        vec3 stormWarm  = mix(vec3(0.125, 0.198, 0.268), vec3(0.34, 0.42, 0.44), vDaylightFactor);
        vec3 stormCrest = mix(vec3(0.200, 0.300, 0.385), vec3(0.49, 0.56, 0.56), vDaylightFactor);

        cDeepFold = mix(cDeepFold, mix(rainDeep,  stormDeep,  stormFactor), wetnessFactor);
        cMidFold  = mix(cMidFold,  mix(rainMid,   stormMid,   stormFactor), wetnessFactor);
        cWarmMid  = mix(cWarmMid,  mix(rainWarm,  stormWarm,  stormFactor), wetnessFactor);
        cSunCrest = mix(cSunCrest, mix(rainCrest, stormCrest, stormFactor), wetnessFactor);
        silverRimColor = mix(vec3(0.48, 0.66, 0.72), vec3(1.10, 0.96, 0.78), vDaylightFactor) * (1.0 - wetnessFactor * 0.50);
    } else {
        // Xianxia Mist (Cumulus): Rich cool cerulean-indigo shadows, sculpted pearl midtones,
        // selective bright sunlit/moonlit crowns, and deep thunderstorm bases.
        vec3 dayDeep    = vec3(0.17, 0.28, 0.43);
        vec3 sunsetDeep = vec3(0.36, 0.26, 0.48);
        vec3 nightDeep  = vec3(0.052, 0.096, 0.195);

        vec3 dayMid     = vec3(0.46, 0.59, 0.74);
        vec3 sunsetMid  = vec3(0.74, 0.48, 0.50);
        vec3 nightMid   = vec3(0.130, 0.225, 0.390);

        vec3 dayWarm    = vec3(0.85, 0.92, 0.97);
        vec3 sunsetWarm = vec3(0.98, 0.68, 0.50);
        vec3 nightWarm  = vec3(0.245, 0.390, 0.600);

        vec3 dayCrest    = vec3(1.02, 1.00, 0.98);
        vec3 sunsetCrest = vec3(1.12, 0.86, 0.62);
        vec3 nightCrest  = vec3(0.410, 0.590, 0.840);

        cDeepFold = mix(nightDeep,  mix(dayDeep,  sunsetDeep,  vSunsetFactor), vDaylightFactor);
        cMidFold  = mix(nightMid,   mix(dayMid,   sunsetMid,   vSunsetFactor), vDaylightFactor);
        cWarmMid  = mix(nightWarm,  mix(dayWarm,  sunsetWarm,  vSunsetFactor), vDaylightFactor);
        cSunCrest = mix(nightCrest, mix(dayCrest, sunsetCrest, vSunsetFactor), vDaylightFactor);

        vec3 rainDeep  = mix(vec3(0.038, 0.072, 0.148), vec3(0.18, 0.28, 0.42), vDaylightFactor);
        vec3 rainMid   = mix(vec3(0.090, 0.158, 0.285), vec3(0.33, 0.45, 0.59), vDaylightFactor);
        vec3 rainWarm  = mix(vec3(0.168, 0.275, 0.440), vec3(0.51, 0.63, 0.76), vDaylightFactor);
        vec3 rainCrest = mix(vec3(0.275, 0.420, 0.620), vec3(0.70, 0.80, 0.90), vDaylightFactor);

        vec3 stormDeep  = mix(vec3(0.022, 0.044, 0.098), vec3(0.08, 0.14, 0.24), vDaylightFactor);
        vec3 stormMid   = mix(vec3(0.058, 0.108, 0.205), vec3(0.18, 0.26, 0.39), vDaylightFactor);
        vec3 stormWarm  = mix(vec3(0.118, 0.202, 0.345), vec3(0.32, 0.43, 0.57), vDaylightFactor);
        vec3 stormCrest = mix(vec3(0.210, 0.335, 0.520), vec3(0.50, 0.62, 0.76), vDaylightFactor);

        cDeepFold = mix(cDeepFold, mix(rainDeep,  stormDeep,  stormFactor), wetnessFactor);
        cMidFold  = mix(cMidFold,  mix(rainMid,   stormMid,   stormFactor), wetnessFactor);
        cWarmMid  = mix(cWarmMid,  mix(rainWarm,  stormWarm,  stormFactor), wetnessFactor);
        cSunCrest = mix(cSunCrest, mix(rainCrest, stormCrest, stormFactor), wetnessFactor);
        silverRimColor = mix(vec3(0.52, 0.74, 1.00), vec3(1.14, 1.04, 0.90), vDaylightFactor) * (1.0 - wetnessFactor * 0.45);
    }
    float afterglow = twilightAfterglow() * (1.0 - wetnessFactor * 0.85);
    vec3 duskTint = (STYLE_SELECTION == 0) ? vec3(0.62, 0.34, 0.23) : vec3(0.72, 0.35, 0.30);
    cWarmMid = mix(cWarmMid, duskTint * 0.72, afterglow * 0.30);
    cSunCrest = mix(cSunCrest, duskTint, afterglow * 0.38);
}

void applyCelestialCloudGlow(vec3 worldRayDir, float thinnessFactor, inout vec3 cloudColor) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);
    float clearFactor = (1.0 - wetnessFactor * 0.75) * (1.0 - stormFactor * 0.75);

    float cosSun  = max(dot(worldRayDir, vSunWorldDir), 0.0);
    float cosMoon = max(dot(worldRayDir, vMoonWorldDir), 0.0);

    if (vDaylightFactor > 0.01 && clearFactor > 0.001) {
        float sunZoneWide = pow(cosSun, (STYLE_SELECTION == 0 ? 5.0 : 4.0)) * vDaylightFactor;
        float sunZoneMid  = pow(cosSun, (STYLE_SELECTION == 0 ? 14.0 : 10.0)) * vDaylightFactor;
        float sunZoneCore = pow(cosSun, (STYLE_SELECTION == 0 ? 42.0 : 32.0)) * vDaylightFactor;

        vec3 dayGlowWide = (STYLE_SELECTION == 0)
            ? mix(vec3(0.98, 0.76, 0.46), vec3(1.06, 0.58, 0.30), vSunsetFactor)
            : mix(vec3(1.04, 0.86, 0.58), vec3(1.12, 0.64, 0.36), vSunsetFactor);
        vec3 dayGlowCore = (STYLE_SELECTION == 0) ? vec3(1.08, 0.90, 0.60) : vec3(1.16, 0.96, 0.70);

        cloudColor = mix(cloudColor, max(cloudColor, dayGlowWide * clearFactor), sunZoneWide * 0.48 * clearFactor);
        cloudColor += dayGlowWide * (sunZoneMid * 0.42) * thinnessFactor * clearFactor;
        cloudColor += dayGlowCore * (sunZoneCore * 0.58) * thinnessFactor * clearFactor;
    }

    if (vNightFactor > 0.01 && clearFactor > 0.001) {
        float moonWideZone = pow(cosMoon, 5.0) * vNightFactor * clearFactor;
        float moonRimZone  = pow(cosMoon, 24.0) * vNightFactor * clearFactor;
        vec3 moonRimTint   = (STYLE_SELECTION == 0) ? vec3(0.40, 0.58, 0.64) : vec3(0.42, 0.64, 0.92);
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
    float bambooWeight   = clamp(inBambooJungle * BIOME_TINT_STRENGTH, 0.0, 1.0);
    float mountainWeight = clamp(max(inMountainBiome, altitudeMountainHint * 0.55) * BIOME_TINT_STRENGTH, 0.0, 1.0);
    float cherryWeight   = clamp(inCherryGrove * BIOME_TINT_STRENGTH, 0.0, 1.0);

    vec3 zenithCol, midCol, horizonCol;

    if (STYLE_SELECTION == 0) {
        vec3 noonZenith    = vec3(0.28, 0.48, 0.58);
        vec3 noonMid       = vec3(0.46, 0.60, 0.64);
        vec3 noonHorizon   = vec3(0.64, 0.70, 0.68);

        vec3 sunsetZenith  = vec3(0.18, 0.28, 0.42);
        vec3 sunsetMid     = vec3(0.68, 0.44, 0.34);
        vec3 sunsetHorizon = vec3(0.84, 0.54, 0.36);

        vec3 nightZenith   = vec3(0.015, 0.035, 0.065);
        vec3 nightMid      = vec3(0.038, 0.072, 0.120);
        vec3 nightHorizon  = vec3(0.075, 0.125, 0.185);

        zenithCol  = mix(nightZenith,  mix(noonZenith,  sunsetZenith,  vSunsetFactor), vDaylightFactor);
        midCol     = mix(nightMid,     mix(noonMid,     sunsetMid,     vSunsetFactor), vDaylightFactor);
        horizonCol = mix(nightHorizon, mix(noonHorizon, sunsetHorizon, vSunsetFactor), vDaylightFactor);

        vec3 rainZenith   = mix(vec3(0.020, 0.038, 0.064), vec3(0.22, 0.31, 0.34), vDaylightFactor);
        vec3 rainMid      = mix(vec3(0.038, 0.068, 0.102), vec3(0.32, 0.40, 0.42), vDaylightFactor);
        vec3 rainHorizon  = mix(vec3(0.062, 0.102, 0.142), vec3(0.30, 0.35, 0.35), vDaylightFactor);

        vec3 stormZenith  = mix(vec3(0.015, 0.028, 0.048), vec3(0.14, 0.20, 0.23), vDaylightFactor);
        vec3 stormMid     = mix(vec3(0.028, 0.050, 0.078), vec3(0.21, 0.28, 0.30), vDaylightFactor);
        vec3 stormHorizon = mix(vec3(0.046, 0.078, 0.112), vec3(0.17, 0.21, 0.23), vDaylightFactor);

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

        vec3 nightZenith   = vec3(0.015, 0.032, 0.078);
        vec3 nightMid      = vec3(0.040, 0.080, 0.160);
        vec3 nightHorizon  = vec3(0.078, 0.140, 0.245);

        zenithCol  = mix(nightZenith,  mix(noonZenith,  sunsetZenith,  vSunsetFactor), vDaylightFactor);
        midCol     = mix(nightMid,     mix(noonMid,     sunsetMid,     vSunsetFactor), vDaylightFactor);
        horizonCol = mix(nightHorizon, mix(noonHorizon, sunsetHorizon, vSunsetFactor), vDaylightFactor);

        vec3 rainZenith   = mix(vec3(0.018, 0.036, 0.080), vec3(0.18, 0.29, 0.44), vDaylightFactor);
        vec3 rainMid      = mix(vec3(0.036, 0.068, 0.135), vec3(0.29, 0.40, 0.54), vDaylightFactor);
        vec3 rainHorizon  = mix(vec3(0.060, 0.105, 0.188), vec3(0.30, 0.36, 0.43), vDaylightFactor);

        vec3 stormZenith  = mix(vec3(0.012, 0.025, 0.058), vec3(0.10, 0.16, 0.27), vDaylightFactor);
        vec3 stormMid     = mix(vec3(0.026, 0.050, 0.102), vec3(0.17, 0.25, 0.37), vDaylightFactor);
        vec3 stormHorizon = mix(vec3(0.045, 0.080, 0.148), vec3(0.16, 0.21, 0.28), vDaylightFactor);

        zenithCol  = mix(zenithCol,  mix(rainZenith,  stormZenith,  stormFactor), wetnessFactor);
        midCol     = mix(midCol,     mix(rainMid,     stormMid,     stormFactor), wetnessFactor);
        horizonCol = mix(horizonCol, mix(rainHorizon, stormHorizon, stormFactor), wetnessFactor);
    }

    float nightBiomeScale = mix(0.22, 1.0, vDaylightFactor) * (1.0 - wetnessFactor * 0.55);
    vec3 bambooJade   = ((STYLE_SELECTION == 0) ? vec3(0.54, 0.72, 0.66) : vec3(0.38, 0.72, 0.64)) * nightBiomeScale;
    vec3 mountainGray = ((STYLE_SELECTION == 0) ? vec3(0.72, 0.77, 0.78) : vec3(0.64, 0.74, 0.84)) * nightBiomeScale;
    vec3 cherryRose   = vec3(0.88, 0.72, 0.80) * nightBiomeScale;

    float biomeFade = 1.0 - wetnessFactor * 0.60;
    horizonCol = mix(horizonCol, bambooJade,   bambooWeight * 0.45 * biomeFade);
    horizonCol = mix(horizonCol, mountainGray, mountainWeight * 0.40 * biomeFade);
    horizonCol = mix(horizonCol, cherryRose,   cherryWeight * 0.35 * biomeFade);

    float upFactor = clamp(VdotU, 0.0, 1.0);
    float midCurve = pow(1.0 - upFactor, 2.2);
    // Above the horizon, transition smoothly to mid/zenith sky; below the horizon (where distant
    // terrain and unloaded chunk borders sit), maintain a deep, continuous atmospheric horizon mist cushion
    // so unloaded chunks dissolve into horizon haze rather than feeling like empty dark space.
    float horCurve = (VdotU >= 0.0)
        ? pow(1.0 - VdotU, 4.8)
        : pow(1.0 - clamp(-VdotU * 1.35, 0.0, 1.0), 2.2);

    vec3 sky = mix(zenithCol, midCol, midCurve);
    sky = mix(sky, horizonCol, horCurve);

    if (VdotU < 0.0) {
        // Smooth sub-horizon mist cushion holds horizonCol across the chunk-border band (VdotU in [-0.28, 0.0])
        // and tapers gently toward the nadir so neither horizon chunk borders nor above-cloud nadir views show a void.
        float subHorizonHold = (1.0 - smoothstep(-0.48, -0.08, VdotU));
        vec3 nadirMist = mix(horizonCol * 0.88 + midCol * 0.14, horizonCol * 0.92, vDaylightFactor);
        sky = mix(horizonCol, nadirMist, subHorizonHold);
    }

    vec2 rayXZ = worldRayDir.xz / max(length(worldRayDir.xz), 0.001);
    vec2 sunXZ = vSunWorldDir.xz / max(length(vSunWorldDir.xz), 0.001);
    float sunsetSide = pow(max(dot(rayXZ, sunXZ), 0.0), 2.0);
    float duskBand = exp(-abs(VdotU - 0.015) * 8.0) * sunsetSide;
    vec3 duskHorizon = (STYLE_SELECTION == 0) ? vec3(0.62, 0.29, 0.15) : vec3(0.72, 0.30, 0.21);
    sky = mix(sky, duskHorizon, twilightAfterglow() * duskBand * (1.0 - wetnessFactor * 0.85) * 0.48);

    float rayHorizonGate = smoothstep(-0.02, 0.12, VdotU);
    float sunElevGate    = smoothstep(-0.02, 0.12, vSunWorldDir.y) * rayHorizonGate;
    float moonElevGate   = smoothstep(-0.02, 0.12, vMoonWorldDir.y) * rayHorizonGate;

    float sunGlare  = pow(clamp(VdotS, 0.0, 1.0), (STYLE_SELECTION == 0 ? 18.0 : 14.0)) * (STYLE_SELECTION == 0 ? 0.15 : 0.18) * sunElevGate;
    float moonGlare = pow(clamp(VdotM, 0.0, 1.0), 14.0) * 0.12 * moonElevGate;
    vec3 sunGlareCol = (STYLE_SELECTION == 0)
        ? mix(vec3(0.98, 0.76, 0.42), vec3(1.04, 0.50, 0.24), vSunsetFactor)
        : mix(vec3(1.00, 0.85, 0.58), vec3(1.10, 0.58, 0.30), vSunsetFactor);
    vec3 moonGlareCol = (STYLE_SELECTION == 0) ? vec3(0.48, 0.62, 0.62) : vec3(0.42, 0.64, 0.88);

    float clearSkyGlare = (1.0 - wetnessFactor * 0.85) * (1.0 - stormFactor * 0.85);
    sky += (sunGlareCol * sunGlare + moonGlareCol * moonGlare) * clearSkyGlare;

    if (lightningFlash > 0.001) {
        float dirBoost = computeLightningDirectionalBoost(worldRayDir);
        vec3 flashSkyCol = (STYLE_SELECTION == 0) ? vec3(0.48, 0.60, 0.68) : vec3(0.46, 0.62, 0.88);
        sky += flashSkyCol * (lightningFlash * dirBoost * (0.22 + 0.24 * (1.0 - upFactor * 0.5)));
    }
    return sky;
}

float applyTexturedCelestialBodies(inout vec3 skyRadiance, vec3 worldRayDir) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);
    float overcastTrans = (1.0 - wetnessFactor * 0.92) * (1.0 - stormFactor * 0.90);
    if (overcastTrans <= 0.002) return 0.0;

    // Presentation size only: preserve the light/shadow source direction and
    // the user's shared size control. Ink needs a stronger visual presence.
    const float sunStyleScale = (STYLE_SELECTION == 0) ? 1.24 : 1.06;
    float sunAngularScale  = 0.082 * SUN_SIZE * sunStyleScale;
    float moonAngularScale = 0.080 * SUN_SIZE;
    float celestialDiscMask = 0.0;

    float rayHorizonVis  = smoothstep(-0.006, 0.006, worldRayDir.y);
    if (rayHorizonVis <= 0.001) return 0.0;

    float sunHaze = mix(0.62, 1.0, smoothstep(0.0, 0.16, vSunWorldDir.y));
    float moonHaze = mix(0.62, 1.0, smoothstep(0.0, 0.16, vMoonWorldDir.y));
    float sunHorizonVis = smoothstep(-sunAngularScale * 1.5, -sunAngularScale * 0.5,
                                    vSunWorldDir.y) * rayHorizonVis * sunHaze;
    float moonHorizonVis = smoothstep(-moonAngularScale * 1.5, -moonAngularScale * 0.5,
                                     vMoonWorldDir.y) * rayHorizonVis * moonHaze;

    const vec3 ORBIT_POLE = vec3(0.0, -0.6691306, 0.7431448);

    float cosSun = dot(worldRayDir, vSunWorldDir);
    float sunSupportRadius = min(0.096 * SUN_SIZE * sunStyleScale * 2.8, 0.99);
    if (cosSun > sqrt(1.0 - sunSupportRadius * sunSupportRadius) && sunHorizonVis > 0.001) {
        vec3 poleAxis = (abs(dot(vSunWorldDir, ORBIT_POLE)) > 0.92) ? vec3(1.0, 0.0, 0.0) : ORBIT_POLE;
        vec3 sunRight = normalize(cross(vSunWorldDir, poleAxis));
        vec3 sunUp    = normalize(cross(sunRight, vSunWorldDir));
        vec2 sunUV    = vec2(dot(worldRayDir, sunRight), dot(worldRayDir, sunUp)) / (0.096 * SUN_SIZE * sunStyleScale);
        float rSun    = length(sunUV);

        // Animate only the light around the artwork. Stable atlas coordinates
        // keep the painted disc and phoenix legible rather than rotating them.
        float solarFlow = sin(sunUV.x * 3.2 + sunUV.y * 2.6 + frameTimeCounter * 0.13)
                        * sin(sunUV.y * 4.4 - sunUV.x * 1.8 - frameTimeCounter * 0.09);
        float coronaRadius = rSun + solarFlow * 0.025;
        float outerCorona = exp(-max(coronaRadius - 0.54, 0.0) * 2.4)
            * (1.0 - smoothstep(0.54, 2.8, rSun))
            * ((STYLE_SELECTION == 0) ? 0.19 : 0.21)
            * (0.96 + 0.04 * solarFlow) * sunHorizonVis;
        vec3 coronaColor  = (STYLE_SELECTION == 0)
            ? mix(vec3(0.98, 0.72, 0.38), vec3(1.02, 0.48, 0.22), vSunsetFactor)
            : mix(vec3(1.02, 0.82, 0.46), vec3(1.08, 0.56, 0.26), vSunsetFactor);
        skyRadiance += coronaColor * outerCorona * overcastTrans;

        if (rSun < 1.18) {
            vec2 atlasUV;
            vec2 localSunUV = clamp(sunUV * 0.45 + 0.5, 0.005, 0.995);
            if (STYLE_SELECTION == 0) {
                atlasUV = vec2(localSunUV.x * 0.5, localSunUV.y);
            } else {
                atlasUV = vec2(0.5 + localSunUV.x * 0.5, localSunUV.y);
            }

            vec4 texSun = texture(celestialTex, atlasUV);
            float edgeFade = 1.0 - smoothstep((STYLE_SELECTION == 0) ? 0.74 : 0.84, 1.15, rSun);
            float paintedEdge = smoothstep(0.58, 1.05, rSun);
            edgeFade *= mix(1.0, (STYLE_SELECTION == 0) ? 0.66 : 0.88, paintedEdge);
            float sunAlpha = texSun.a * edgeFade * overcastTrans * sunHorizonVis;

            if (sunAlpha > 0.001) {
                vec3 sunArtwork = texSun.rgb;
                if (STYLE_SELECTION == 0) {
                    vec3 sunsetTint = mix(vec3(0.98, 0.94, 0.88), vec3(1.12, 0.58, 0.36), vSunsetFactor);
                    sunArtwork *= sunsetTint;

                    float discBleed = exp(-max(rSun - 0.44, 0.0) * 3.2) * 0.20;
                    vec3 bleedColor = mix(vec3(0.98, 0.74, 0.40), vec3(1.04, 0.50, 0.24), vSunsetFactor);
                    // Air light softens the painted perimeter; emission follows
                    // the artwork blend so an opaque texel cannot erase it.
                    sunArtwork = mix(sunArtwork, sunArtwork * 0.70 + skyRadiance * 0.30,
                                     paintedEdge * 0.55);
                    skyRadiance = mix(skyRadiance, sunArtwork, sunAlpha);
                    skyRadiance += bleedColor * discBleed * sunAlpha * (0.96 + solarFlow * 0.04);
                } else {
                    vec3 solarBrilliance = mix(vec3(0.98, 0.94, 0.86), vec3(1.14, 0.64, 0.38), vSunsetFactor);
                    sunArtwork *= solarBrilliance;

                    float solarBloom = exp(-max(rSun - 0.46, 0.0) * 3.3) * 0.18;
                    vec3 bloomColor  = mix(vec3(1.00, 0.80, 0.44), vec3(1.10, 0.58, 0.26), vSunsetFactor);
                    sunArtwork = mix(sunArtwork, sunArtwork * 0.84 + skyRadiance * 0.16,
                                     paintedEdge * 0.40);
                    skyRadiance = mix(skyRadiance, sunArtwork, sunAlpha);
                    skyRadiance += bloomColor * solarBloom * sunAlpha * (0.96 + solarFlow * 0.04);
                }

                celestialDiscMask = max(celestialDiscMask, clamp(sunAlpha * 1.15 * (1.0 - wetnessFactor * 0.95), 0.0, 1.0));
            }
        }
    }

    float cosMoon = dot(worldRayDir, vMoonWorldDir);
    if (cosMoon > 0.85 && moonHorizonVis > 0.001) {
        vec3 poleAxis  = (abs(dot(vMoonWorldDir, ORBIT_POLE)) > 0.92) ? vec3(1.0, 0.0, 0.0) : ORBIT_POLE;
        vec3 moonRight = normalize(cross(vMoonWorldDir, poleAxis));
        vec3 moonUp    = normalize(cross(moonRight, vMoonWorldDir));

        float activeMoonScale = (STYLE_SELECTION == 1) ? (0.096 * SUN_SIZE) : moonAngularScale;
        vec2 moonUV    = vec2(dot(worldRayDir, moonRight), dot(worldRayDir, moonUp)) / activeMoonScale;
        float rMoon    = length(moonUV);

        int mPhase = moonPhase & 7;
        float phaseIllumFrac = (mPhase == 0) ? 1.00 : ((mPhase == 4) ? 0.18 : ((mPhase == 1 || mPhase == 7) ? 0.78 : ((mPhase == 2 || mPhase == 6) ? 0.54 : 0.34)));
        float phaseDirX      = (mPhase >= 1 && mPhase <= 3) ? -1.0 : ((mPhase >= 5 && mPhase <= 7) ? 1.0 : 0.0);
        float dirBias        = 1.0 + 0.28 * phaseDirX * clamp(moonUV.x / max(rMoon, 0.25), -1.0, 1.0);

        float wideLunarAura = exp(-rMoon * 1.15) * smoothstep(4.2, 0.45, rMoon) * 0.16;
        float limbDiffusion = exp(-max(rMoon - 0.54, 0.0) * 3.2) * smoothstep(2.0, 0.54, rMoon) * 0.20;
        float totalHalo     = (wideLunarAura + limbDiffusion) * phaseIllumFrac * dirBias * moonHorizonVis * overcastTrans;

        vec3 haloTint = (STYLE_SELECTION == 0)
            ? vec3(0.56, 0.72, 0.70)
            : vec3(0.46, 0.76, 0.92);
        skyRadiance += haloTint * totalHalo;

        vec2 localUV = moonUV * 0.45 + 0.5;
        if (all(greaterThanEqual(localUV, vec2(0.0))) && all(lessThanEqual(localUV, vec2(1.0)))) {
            ivec2 tile = ivec2(mPhase & 3, mPhase >> 2);
            vec2 tileSize = vec2(512.0, 512.0);
            vec2 safeUV   = clamp(localUV, 0.5 / tileSize, 1.0 - 0.5 / tileSize);
            vec2 atlasUV  = (vec2(tile) + safeUV) / vec2(4.0, 2.0);

            vec4 texMoon = (STYLE_SELECTION == 1)
                ? texture(xianxiaMoonTex, atlasUV)
                : texture(guofengMoonTex, atlasUV);

            float edgeFade = smoothstep(1.16, 0.92, rMoon);
            float rawAlpha = texMoon.a * edgeFade * overcastTrans * moonHorizonVis;

            if (rawAlpha > 0.001) {
                vec3 litTint = (STYLE_SELECTION == 0) ? vec3(0.96, 0.95, 0.90) : vec3(0.92, 0.97, 1.00);
                vec3 targetMoon = max(skyRadiance + texMoon.rgb * 0.24, texMoon.rgb * litTint);

                float rimFeather = 1.0 - smoothstep(0.58, 0.96, rMoon) * 0.25;
                float effectiveAlpha = rawAlpha * rimFeather;

                skyRadiance = mix(skyRadiance, targetMoon, effectiveAlpha);
                celestialDiscMask = max(celestialDiscMask, clamp(effectiveAlpha * 1.05 * (1.0 - wetnessFactor * 0.95), 0.0, 1.0));
            }
        }
    }

    return celestialDiscMask;
}

vec3 renderNightWuxiaAurora(vec3 worldRayDir, float time, int auroraMode) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);
    if (auroraMode == 3 || vNightFactor <= 0.01 || worldRayDir.y <= 0.01) {
        return vec3(0.0);
    }

    int activeAuroraStyle = (auroraMode == 0) ? (STYLE_SELECTION == 1 ? 1 : 2) : auroraMode;
    float nightVis = vNightFactor * (1.0 - wetnessFactor * 0.94) * (1.0 - stormFactor * 0.95);
    if (nightVis <= 0.005) return vec3(0.0);

    const vec3 C_UP    = vec3( 0.34188,  0.86923, -0.35742);
    const vec3 C_RIGHT = vec3( 0.89842, -0.17852,  0.40122);
    const vec3 C_FWD   = vec3(-0.27525,  0.46118,  0.84354);

    float lat = dot(worldRayDir, C_UP);
    float xP  = dot(worldRayDir, C_RIGHT);
    float zP  = dot(worldRayDir, C_FWD);

    vec3 drift = vec3(time * 0.008, -time * 0.005, time * 0.006);
    float w1 = silkyFbm3D(worldRayDir * 2.4 + drift);
    float w2 = silkyFbm3D(worldRayDir * 2.4 + vec3(5.2, 1.3, 8.7) - drift * 0.8);

    vec3 warpedRay = worldRayDir * 3.6 + vec3(w1 - 0.5, w2 - 0.5, (w1 - w2) * 0.7) * 1.25;
    float flowA = silkyFbm3D(warpedRay);
    float flowB = silkyFbm3D(warpedRay * 2.05 + vec3(3.1, -2.4, 4.7));

    float meander1 = (w1 - 0.5) * 0.26 + 0.09 * sin(xP * 2.8 - zP * 1.9 + time * 0.010);
    float h1 = lat - meander1;

    float striation1 = silkyFbm3D(vec3(worldRayDir.x * 11.0 - worldRayDir.y * 2.5 + w1 * 1.8, worldRayDir.y * 4.0, worldRayDir.z * 11.0 + w2 * 1.8));
    float striation2 = silkyFbm3D(vec3(worldRayDir.x * 22.0 + w2 * 2.2, worldRayDir.y * 6.0, worldRayDir.z * 22.0 - w1 * 2.2));
    float curtainFolds = smoothstep(0.24, 0.82, striation1 * 0.62 + striation2 * 0.38);

    float lowerEdge1 = smoothstep(-0.025, 0.008, h1) * exp(-max(h1, 0.0) * 13.0) * (0.50 + 0.60 * flowA);
    float curtain1   = smoothstep(-0.015, 0.025, h1) * exp(-max(h1, 0.0) * 4.5) * (0.30 + 0.90 * curtainFolds) * smoothstep(0.25, 0.78, flowA);

    float meander2 = -(w2 - 0.5) * 0.28 + 0.11 * cos(xP * 2.2 + zP * 2.4 - time * 0.008) + 0.06;
    float h2 = lat - meander2;
    float nebulaBillows = smoothstep(0.32, 0.80, flowA * 0.52 + flowB * 0.48);
    float lowerEdge2 = smoothstep(-0.030, 0.012, h2) * exp(-max(h2, 0.0) * 10.0) * nebulaBillows;
    float curtain2   = exp(-(h2 * h2) / 0.038) * nebulaBillows * (0.45 + 0.55 * curtainFolds);

    vec3 starGrid  = worldRayDir * 155.0;
    vec3 starCell  = floor(starGrid);
    vec3 starFract = fract(starGrid) - 0.5;
    float starR2   = dot(starFract, starFract);
    float starSeed = hash13(starCell);
    float twinkle  = 0.65 + 0.35 * sin(time * 2.2 + starSeed * 62.8);
    float starPinprick = exp(-starR2 * 18.0) * step(0.962, starSeed) * twinkle * clamp(curtain1 + curtain2 * 1.4, 0.0, 1.0);

    vec3 colBottom, colMid, colUpper, colCrown, colStardust;
    float styleScale;
    if (activeAuroraStyle == 1) {
        colBottom   = vec3(0.14, 0.94, 1.00);
        colMid      = vec3(0.18, 0.56, 0.98);
        colUpper    = vec3(0.62, 0.26, 0.92);
        colCrown    = vec3(0.84, 0.32, 0.78);
        colStardust = vec3(0.88, 0.98, 1.00);
        styleScale  = 0.88;
    } else {
        colBottom   = vec3(0.28, 0.82, 0.74);
        colMid      = vec3(0.20, 0.56, 0.64);
        colUpper    = vec3(0.34, 0.32, 0.58);
        colCrown    = vec3(0.48, 0.34, 0.56);
        colStardust = vec3(0.96, 0.92, 0.82);
        styleScale  = 0.64;
    }

    float h1Norm = clamp(max(h1, 0.0) / 0.24, 0.0, 1.0);
    vec3 cBody1  = mix(colMid, colUpper, h1Norm);
    vec3 rgb1    = colBottom * (lowerEdge1 * 0.80) + cBody1 * (curtain1 * 0.85);

    float h2Norm = clamp((h2 + 0.15) / 0.35, 0.0, 1.0);
    vec3 cBody2  = mix(colMid, colCrown, h2Norm);
    vec3 rgb2    = colBottom * (lowerEdge2 * 0.45) + cBody2 * (curtain2 * 0.70);

    vec3 stardustRgb = colStardust * (starPinprick * 1.30);

    float horizonFade = smoothstep(0.02, 0.15, clamp(worldRayDir.y, 0.0, 1.0));
    return (rgb1 + rgb2 + stardustRgb) * horizonFade * styleScale * nightVis;
}

/* =============================================================================
 * UNIFIED 3D VOLUMETRIC CLOUDS ON A CURVED SPHERICAL ATMOSPHERE SHELL
 * (Adapted from Guerrilla Games' Horizon Zero Dawn / Nubis principles for Minecraft):
 * 1. Spherical Atmosphere Shell (R_SHELL = 14,000m):
 *    Brings true 3D volumetric cloud formations naturally down toward the horizon
 *    without 2D painted backdrops, decorative walls, or ray-skimming distortion.
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
const float CLOUD_SPHERE_RADIUS = 16000.0;

void getCloudShellBounds(int mode, out float base, out float top) {
    cloudBounds(mode, base, top);
}

float computeSphericalShellAltitude(vec3 tracePos, vec3 camPos, out float distXZ) {
    vec2 dXZ = tracePos.xz - camPos.xz;
    distXZ = length(dXZ);
    // Curved spherical atmosphere layer brings distant 3D formations naturally down toward the horizon
    float curveDrop = (distXZ * distXZ) / (2.0 * CLOUD_SPHERE_RADIUS);
    return tracePos.y + curveDrop;
}

bool intersectSphericalCloudShell(vec3 camPos, vec3 rayDir, float baseAlt, float topAlt, out float tStart, out float tEnd) {
    float a = dot(rayDir.xz, rayDir.xz) / (2.0 * CLOUD_SPHERE_RADIUS);
    float b = rayDir.y;

    if (a < 1e-7) {
        if (abs(b) < 1e-5) return false;
        float t1 = (baseAlt - camPos.y) / b;
        float t2 = (topAlt  - camPos.y) / b;
        tStart = max(min(t1, t2), 0.0);
        tEnd   = max(t1, t2);
        return (tEnd > tStart);
    }

    float discTop = b * b - 4.0 * a * (camPos.y - topAlt);
    if (discTop <= 0.0) return false;
    float sqrtTop = sqrt(discTop);
    float tTopPos = (-b + sqrtTop) / (2.0 * a);
    float tTopNeg = (-b - sqrtTop) / (2.0 * a);

    float discBase = b * b - 4.0 * a * (camPos.y - baseAlt);
    if (camPos.y < baseAlt) {
        if (discBase <= 0.0) return false;
        float sqrtBase = sqrt(discBase);
        tStart = max((-b + sqrtBase) / (2.0 * a), 0.0);
        tEnd   = tTopPos;
    } else if (camPos.y <= topAlt) {
        tStart = 0.0;
        if (discBase > 0.0 && b < 0.0) {
            float sqrtBase = sqrt(discBase);
            float tHitBase = (-b - sqrtBase) / (2.0 * a);
            tEnd = (tHitBase > 0.0) ? tHitBase : tTopPos;
        } else {
            tEnd = tTopPos;
        }
    } else {
        if (tTopNeg <= 0.0 && tTopPos <= 0.0) return false;
        tStart = max(tTopNeg, 0.0);
        if (discBase > 0.0) {
            float sqrtBase = sqrt(discBase);
            float tBaseNeg = (-b - sqrtBase) / (2.0 * a);
            tEnd = (tBaseNeg > tStart) ? tBaseNeg : tTopPos;
        } else {
            tEnd = tTopPos;
        }
    }
    return (tEnd > tStart);
}

// World-anchored, trilinearly sampled volume; shell curvature only affects altitude.
float sampleWuxiaCloudVolume3D(vec3 tracePos, vec3 camPos, float time, int mode,
    float baseAlt, float maxTopAlt, float rain, float storm, float stepSize,
    out float height, out float detail) {
    float distXZ;
    float altitude = computeSphericalShellAltitude(tracePos, camPos, distXZ);
    return cloudDensity(tracePos, altitude, time, mode, rain, storm, stepSize, height, detail);
}

vec4 renderWuxiaVolumetricClouds(vec3 rayDirWorld, vec3 viewRayDir, vec3 camPos, float time, vec3 bgSkyColor, float celestialDiscMask, float maxSceneDist, int activeCloudMode, bool reflectionTrace) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);

    float baseAlt, maxTopAlt;
    getCloudShellBounds(activeCloudMode, baseAlt, maxTopAlt);
    float maxTraceDist = 2800.0;

    float tStart, tEnd;
    if (!intersectSphericalCloudShell(camPos, rayDirWorld, baseAlt, maxTopAlt, tStart, tEnd)) {
        return vec4(0.0);
    }

    tStart = max(tStart, 0.0);
    if (tStart >= maxSceneDist || tEnd <= tStart || tStart >= maxTraceDist) return vec4(0.0);
    tEnd = min(tEnd, min(maxSceneDist, min(tStart + 720.0, maxTraceDist)));

    float localOverheadTop = maxTopAlt - 20.0;
    float grazingFade = 1.0;
    // Shell intersection and distance extinction handle the horizon continuously;
    // a fixed view-angle cutoff would expose a horizontal edge during flight.

    #if CLOUD_QUALITY == 0
    const int STEPS = 32;
    #elif CLOUD_QUALITY == 1
    const int STEPS = 64;
    #elif CLOUD_QUALITY == 2
    const int STEPS = 96;
    #else
    const int STEPS = 128;
    #endif
    // Water reuses the density and lighting model with a smaller ray budget.
    const int REFLECTION_STEPS = (WATER_REFLECTIONS >= 2) ? STEPS / 2 : STEPS / 4;
    int traceSteps = reflectionTrace ? REFLECTION_STEPS : STEPS;
    float totalSpan = tEnd - tStart;
    // Use stable low-amplitude spatial offset so non-TAA modes (Subtle/Smooth AA) never show 1-pixel checkerboard stipple
    float dither = 0.15 + 0.70 * hash12(gl_FragCoord.xy);

    float cosLight = dot(viewRayDir, vLightViewDir);
    float directSourceVis = smoothstep(0.0, 0.10, vLightWorldDir.y);
    float nightAmbientVis = vNightFactor * 0.86;
    float effectiveLightVis = max(directSourceVis, nightAmbientVis);

    float hgForward = henyeyGreensteinPhase(cosLight, 0.65) * 1.40;
    float hgBack    = henyeyGreensteinPhase(cosLight, -0.25) * 0.45;
    float phaseFunction = (hgForward + hgBack) * directSourceVis * (1.0 - wetnessFactor * 0.60);

    vec3 cDeepFold, cMidFold, cWarmMid, cSunCrest, silverRimColor;
    getLuminousCloudPalette(cDeepFold, cMidFold, cWarmMid, cSunCrest, silverRimColor);

    float absRayY = abs(rayDirWorld.y);
    float verticalOpticalProjection = mix(max(absRayY, 0.14), 1.0, 0.35);
    float baseOpticalScale = ((activeCloudMode == 1) ? 0.040 : 0.050) * verticalOpticalProjection;

    float topDownView = smoothstep(localOverheadTop - 20.0, localOverheadTop + 15.0, camPos.y)
                      * (1.0 - smoothstep(-0.18, 0.0, rayDirWorld.y));

    vec3 accumColor = vec3(0.0);
    float accumTransmittance = 1.0;

    float cachedShadowOD = 0.0;
    bool hasShadowSample = false;
    vec3 shadowDir = normalize(mix(vec3(0.0, 1.0, 0.0), vLightWorldDir, directSourceVis * 0.72));

    for (int i = 0; i < STEPS; i++) {
        if (i >= traceSteps) break;
        float f0 = float(i) / float(traceSteps);
        float f1 = float(i + 1) / float(traceSteps);
        float w0 = mix(f0, f0 * f0, 0.34);
        float w1 = mix(f1, f1 * f1, 0.34);
        float stepSize = (w1 - w0) * totalSpan;
        float tSample  = tStart + mix(w0, w1, dither) * totalSpan;
        vec3 tracePos  = camPos + rayDirWorld * tSample;

        float distXZ = length(tracePos.xz - camPos.xz);
        if (distXZ > maxTraceDist) break;

        float localHeightNorm, detailBillow;
        float cloudDensity = sampleWuxiaCloudVolume3D(tracePos, camPos, time, activeCloudMode, baseAlt, maxTopAlt, wetnessFactor, stormFactor, stepSize, localHeightNorm, detailBillow);

        if (cloudDensity > 0.001) {
            #if CLOUD_QUALITY == 0
            float shadowOD = cloudDensity * (1.0 - localHeightNorm * 0.55) * 0.85;
            #else
            if (cloudDensity > 0.025 && (CLOUD_QUALITY >= 3 || !hasShadowSample || (i & 1) == 0)) {
                float dummyH, dummyD;
                cachedShadowOD = sampleWuxiaCloudVolume3D(tracePos + shadowDir * (activeCloudMode == 1 ? 28.0 : 36.0), camPos, time, activeCloudMode, baseAlt, maxTopAlt, wetnessFactor, stormFactor, stepSize * 1.5, dummyH, dummyD);
                hasShadowSample = true;
            } else if (!hasShadowSample) {
                cachedShadowOD = cloudDensity * (1.0 - localHeightNorm * 0.55) * 0.75;
            }
            float shadowOD = cachedShadowOD;
            #endif

            float tau = shadowOD * ((activeCloudMode == 1) ? 1.30 : (1.65 + stormFactor * 0.70)) * effectiveLightVis;
            float multiScatter = exp(-tau) * 0.58 + exp(-tau * 0.28) * 0.42;
            float powderEffect = 1.0 - 0.34 * exp(-cloudDensity * 2.2);
            float lightTrans   = clamp(0.26 + 0.74 * multiScatter * powderEffect, 0.0, 1.0);

            float billowGrad     = clamp((cloudDensity - shadowOD) * 0.38 + 0.50, 0.0, 1.0);
            float canopyTopLight = topDownView * accumTransmittance * 0.46;
            float reliefMod      = (detailBillow - 0.48) * 0.46 + (billowGrad - 0.50) * 0.26;
            float verticalLight  = clamp(smoothstep(0.04, 0.86, localHeightNorm + reliefMod) + canopyTopLight, 0.0, 1.0);
            float directionalRelief = clamp((cloudDensity-shadowOD)*1.1 + 0.48, 0.0, 1.0);
            float cloudShading = clamp((0.12 + 0.52 * verticalLight + 0.30 * directionalRelief) * lightTrans
                + canopyTopLight * 0.30, 0.0, 1.0);
            cloudShading *= mix(1.0, 0.72, wetnessFactor) * mix(1.0, 0.78, stormFactor);

            float t1 = clamp(cloudShading * 1.95, 0.0, 1.0);
            float t2 = clamp((cloudShading - 0.24) * 1.85, 0.0, 1.0);
            float t3 = clamp((cloudShading - 0.50) * 2.15, 0.0, 1.0);
            t1 = t1 * t1 * (3.0 - 2.0 * t1);
            t2 = t2 * t2 * (3.0 - 2.0 * t2);
            t3 = t3 * t3 * (3.0 - 2.0 * t3);

            vec3 colorSample = mix(cDeepFold, cMidFold, t1);
            colorSample = mix(colorSample, cWarmMid,  t2);
            colorSample = mix(colorSample, cSunCrest, t3);

            float baseBounce = (1.0 - smoothstep(0.0, 0.28, localHeightNorm)) * 0.32 * (1.0 - topDownView * 0.8);
            colorSample = mix(colorSample, bgSkyColor * 1.03, baseBounce);

            float thinTrans = exp(-shadowOD * 1.45);
            float rimMask = celestialDiscMask * (1.0 - celestialDiscMask) * 3.5;
            float silverBoost = (phaseFunction + rimMask * (1.0 - wetnessFactor)) * thinTrans;
            float rimScale = (activeCloudMode == 1) ? 0.28 : 0.42;
            colorSample += silverRimColor * clamp(silverBoost * rimScale, 0.0, 0.65);

            applyCelestialCloudGlow(rayDirWorld, thinTrans, colorSample);

            float aerialHaze = 1.0 - exp(-max(distXZ - 350.0, 0.0) * 0.00120);
            colorSample = mix(colorSample, bgSkyColor, clamp(aerialHaze * 0.92, 0.0, 0.94));

            float distanceEnvelope = 1.0 - smoothstep(1900.0, maxTraceDist * 0.98, distXZ);
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

    float startDistFade   = 1.0 - smoothstep(1950.0, maxTraceDist * 0.96, tStart);
    float maxCloudOpacity = mix(0.98, 1.0, wetnessFactor);
    float shapeGamma      = 1.0;
    float finalCloudAlpha = clamp(pow(totalAlpha, shapeGamma) * maxCloudOpacity * grazingFade * startDistFade, 0.0, 1.0);

    return vec4(finalCloudColor, finalCloudAlpha);
}

float terrainSkyBlend(vec3 playerPos) {
    float distance = max(length(playerPos.xz), length(playerPos) * 0.86);
    float clearEnd = min(max(far * 0.97, 64.0), far);
    float clearStart = min(max(far * 0.62, 40.0), clearEnd * 0.90);
    float rain, storm, flash;
    evaluateWeatherState(rain, storm, flash);
    // Rain haze must finish before terrain disappears. Iris can expose a
    // shorter weather/biome visibility distance than the chunk render range.
    // Use the same fade in the cloud prepass and final terrain/sky composite.
    float weatherEnd = clearEnd * mix(0.84, 0.72, storm);
    float end = mix(clearEnd, weatherEnd, rain);
    if (fogEnd > 1.0) end = min(end, fogEnd * 0.97);
    float start = min(mix(clearStart, end * 0.58, rain), end * 0.90);
    return smoothstep(start, end, distance);
}

vec4 computeValleyMistAndBorderFog(vec3 worldPos, vec3 playerPos, float viewDist, vec3 skyAtRay) {
    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);
    float borderFog = terrainSkyBlend(playerPos);
    float densityMult = FOG_DENSITY * (1.0 + wetnessFactor * 0.55 + stormFactor * 0.40);
    float fogStartDist = mix(30.0, 10.0, wetnessFactor);
    float delayedDist = max(viewDist - fogStartDist, 0.0);
    float distFog = 1.0 - exp(-delayedDist * mix(0.00065, 0.0028, wetnessFactor) * densityMult);

    float valleyDelta = (worldPos.y - SEA_OF_CLOUDS_ALTITUDE) / max(SEA_OF_CLOUDS_THICKNESS * (1.0 + wetnessFactor * 0.25), 1.0);
    float valleyBand = exp(-valleyDelta * valleyDelta * 1.85);
    vec2 mistDriftUV = worldPos.xz * 0.00018 + vec2(frameTimeCounter * 0.0005, -frameTimeCounter * 0.0003);
    float billowingNoise = sampleNoiseTexTiled(mistDriftUV).g;
    float valleyMist = valleyBand * smoothstep(0.38, 0.82, billowingNoise)
                     * smoothstep(32.0, 128.0, viewDist);
    float seaStrength = (STYLE_SELECTION == 1 || CLOUD_TYPE == 2) ? 0.30 : 0.22;
    float mistFog = clamp(valleyMist * seaStrength * densityMult, 0.0, 0.65);
    float combinedFog = 1.0 - (1.0 - borderFog) * (1.0 - distFog) * (1.0 - mistFog);
    return vec4(skyAtRay, clamp(combinedFog, 0.0, 1.0));
}

vec3 applyAtmosphericPrecipitation(vec3 sceneRadiance, vec3 unifiedSky, vec3 worldRayDir) {
    vec4 weatherSample = texture(colortex3, vTexCoord);
    if (weatherSample.a <= 0.002) return sceneRadiance;

    vec3 unpacked     = weatherSample.rgb / max(weatherSample.a, 1e-4);
    float streakLuma  = clamp(unpacked.r, 0.40, 1.0);
    float blockLight  = clamp(unpacked.g, 0.0, 1.0);
    float snowWeight  = clamp(unpacked.b, 0.0, 1.0);

    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);

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

vec3 computeUnderwaterLightShafts(vec3 viewPos, vec3 lightDirWorld, float cosTheta) {
    #if LIGHT_SHAFTS == 0
    return vec3(0.0);
    #else
    const int UW_STEPS = (LIGHT_SHAFTS >= 2) ? 14 : 8;
    float sourceVisibility = smoothstep(0.0, 0.10, lightDirWorld.y);
    if (sourceVisibility <= 0.0) return vec3(0.0);
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

        vec2 wavePlaneUV = sampleWorldPos.xz - refractSunWorld.xz * (sampleWorldPos.y / refractSunWorld.y);
        float t = frameTimeCounter;

        float wA = sin(wavePlaneUV.x * 1.15 + wavePlaneUV.y * 0.75 - t * 1.6);
        float wB = cos(wavePlaneUV.x * 0.85 - wavePlaneUV.y * 1.35 + t * 1.3);
        float wC = sin((wavePlaneUV.x + wavePlaneUV.y) * 1.95 - t * 2.1);
        float causticLens = pow(clamp(1.0 - abs(wA * 0.5 + wB * 0.5 + wC * 0.25), 0.0, 1.0), 2.6);

        float distAtten = exp(-length(currentViewPos) * 0.045);
        // Follow the incident sun/moon illumination, including real storm
        // openings. Diffuse overcast remains in underwater fog/ambient light;
        // it must not generate directional shafts under an opaque ceiling.
        float cloudTransmission = cloudLightTransmission(sampleWorldPos, lightDirWorld,
            frameTimeCounter, cloudMode, wetnessFactor, stormFactor);
        accumBeams += shadowVis * cloudTransmission * causticLens * distAtten;
        currentViewPos += stepVecView;
    }

    accumBeams /= float(UW_STEPS);

    vec3 worldRayDir = normalize(mat3(gbufferModelViewInverse) * rayDirView);
    float upLookBoost = smoothstep(-0.45, 0.85, worldRayDir.y) * 0.65 + 0.35;
    float sunAlign    = henyeyGreensteinPhase(dot(worldRayDir, refractSunWorld), 0.55);

    float beamStrength = accumBeams * (0.75 + sunAlign * 0.55) * upLookBoost * mix(0.25, 1.0, vDaylightFactor) * float(LIGHT_SHAFTS);
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
        : ((LIGHT_SHAFTS >= 2) ? 512.0 : 384.0);
    float fullViewDist = length(viewPos);
    float maxRayDist   = depth0 >= 0.999999 && cloudMode != 3 ? MAX_SHAFT_RANGE : min(fullViewDist, MAX_SHAFT_RANGE);
    float sourceVisibility = smoothstep(0.0, 0.10, vLightWorldDir.y);
    if (maxRayDist <= 0.001 || sourceVisibility <= 0.0 || ATMOSPHERIC_SHAFT_STRENGTH <= 0.0) return vec3(0.0);
    // Held items are foreground geometry, outside the atmospheric volume.
    if (abs(texture(colortex1, vTexCoord).a - 0.12) < 0.007) return vec3(0.0);

    // Streamlined step counts (24 Soft / 40 Full) paired with composite2's 3x3 bilateral filter
    const int RAY_STEPS = (LIGHT_SHAFTS >= 2) ? 40 : 24;
    float dither = hash12(gl_FragCoord.xy);

    float minRayDist = min(1.25, maxRayDist * 0.28);
    vec3 rayDirView = viewPos / max(fullViewDist, 1e-5);
    vec3 rayDirPlayer = mat3(gbufferModelViewInverse) * rayDirView;
    vec3 rayOriginPlayer = gbufferModelViewInverse[3].xyz;
    vec3 shadowOrigin = (shadowProjection * (shadowModelView * vec4(rayOriginPlayer, 1.0))).xyz;
    vec3 shadowDirection = (shadowProjection * (shadowModelView * vec4(rayDirPlayer, 0.0))).xyz;
    vec3 lightStepShadowClip = (shadowProjection * (shadowModelView * vec4(vLightWorldDir, 0.0))).xyz;
    float oneMeterShadowZ = max(abs(lightStepShadowClip.z) * 0.1, 1e-5);

    float wetnessFactor, stormFactor, lightningFlash;
    evaluateWeatherState(wetnessFactor, stormFactor, lightningFlash);
    float cloudScatter = 0.0;
    float litScatter = 0.0;
    for (int i = 0; i < RAY_STEPS; i++) {
        float u0 = float(i) / float(RAY_STEPS);
        float u1 = float(i + 1) / float(RAY_STEPS);
        float f0 = cloudMode == 3 ? u0 * (0.36 + 0.64 * u0) : u0 * u0;
        float f1 = cloudMode == 3 ? u1 * (0.36 + 0.64 * u1) : u1 * u1;
        float cellStart = mix(minRayDist, maxRayDist, f0);
        float cellEnd   = mix(minRayDist, maxRayDist, f1);
        float stepLen   = cellEnd - cellStart;
        float sampleDistance = mix(cellStart, cellEnd, dither);

        vec3 sampleWorld=cameraPosition+rayOriginPlayer+rayDirPlayer*sampleDistance;
        float cloudTransmission=cloudLightTransmission(sampleWorld,vLightWorldDir,
            frameTimeCounter,cloudMode,wetnessFactor,stormFactor);
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
        // Beyond the terrain shadow map, cloud transmission still defines air lighting.
        // Omitting those samples would draw the shadow-map boundary across the sky.
        float worldY = rayOriginPlayer.y + rayDirPlayer.y * sampleDistance + cameraPosition.y;
        float mistDensity = exp(-max(worldY - SEA_OF_CLOUDS_ALTITUDE, 0.0) * 0.012);
        float radialWeight = exp(-sampleDistance / 14.0) * (stepLen / 4.5);
        if (cloudMode == 3) radialWeight += exp(-sampleDistance / 70.0) * (stepLen / 360.0);
        float densityWeight = (0.78 + 0.22 * mistDensity) * radialWeight;
        float visibility = isUnoccluded * cloudTransmission;
        litScatter += visibility * densityWeight;
        // Cloud columns accumulate through world-space lit air, including when
        // the viewer is inside the column. Do not subtract the camera's light.
        float cloudBase, cloudTop;
        cloudBounds(cloudMode, cloudBase, cloudTop);
        float airLayer = 1.0 - smoothstep(cloudBase - 16.0, cloudBase + 8.0, worldY);
        float airDensity = exp(-max(worldY - 64.0, 0.0) / 180.0) * airLayer;
        cloudScatter += visibility * airDensity * exp(-sampleDistance / 600.0) * (stepLen / 160.0);
    }

    // Leave headroom between partly lit air and an open canopy gap. Early
    // saturation turns their different optical paths into the same soft veil.
    float beamResponse = 1.0 - exp(-0.65 * litScatter * min(FOG_DENSITY, 1.35));

    // Concentrate the extra visibility toward the light instead of increasing
    // fog or exposure in every direction. Retain a softer response for Ink.
    const float forwardLimit = (STYLE_SELECTION == 0) ? 2.9 : 3.4;
    float forwardMie = min(henyeyGreensteinPhase(clamp(cosTheta, -1.0, 1.0), 0.55) * 12.5663706, forwardLimit);
    float phase = 0.40 + 0.60 * forwardMie;

    float enclosureGain = mix(1.24, 0.82, smoothstep(0.50, 0.95, eyeSkyFactor));

    // Continuous fog/sky damping: near geometry (windows, caves, tree canopies where horizonFogWeight ~ 0)
    // receives full 1.0 shaft weight, while fogged chunk-border terrain and sky pixels share the exact same
    // damped weight (0.55) so there is zero brightness jump across the chunk border or horizon!
    float skyDamp = mix(1.0, 0.55, clamp(horizonFogWeight, 0.0, 1.0));
    float surfaceContrast = (1.0 - smoothstep(0.26, 0.72, sceneLuma) * 0.55) * skyDamp;

    float modeScale = (LIGHT_SHAFTS >= 2) ? 1.00 : 0.75;
    float timeScale = mix(0.88, 1.00, vDaylightFactor);
    // Continuous optical onset: a fixed empty radius draws a clear disk
    // over water when the camera approaches the surface.
    float nearSurfaceFade = 1.0-exp(-maxRayDist/0.45);
    // Exposed air is much clearer than an enclosed or humid volume. Keep this
    // gain independent of occlusion: adding a shadow must never brighten a ray.
    float exposedGain = mix(0.72, 0.90, wetnessFactor);
    float structureGain = mix(1.0, exposedGain, smoothstep(0.35, 0.95, eyeSkyFactor));
    // Keep nearby window/foliage shafts; distant views use the extended cloud
    // volume rather than a saturated patch of scattering around the camera.
    float distantOpenAir = smoothstep(12.0, 64.0, fullViewDist)
                         * smoothstep(0.35, 0.95, eyeSkyFactor);
    float localGain = cloudMode == 3 ? 1.0 : mix(1.0, 0.22, distantOpenAir);

    float shaftIntensity = beamResponse * phase * enclosureGain * surfaceContrast *
                           ((STYLE_SELECTION == 0) ? 0.34 : 0.37) * modeScale * ATMOSPHERIC_SHAFT_STRENGTH * structureGain *
                           timeScale * nearSurfaceFade * sourceVisibility * localGain;

    vec3 dayShaftColor = (STYLE_SELECTION == 0)
        ? mix(vec3(1.02, 0.84, 0.56), vec3(1.08, 0.64, 0.38), vSunsetFactor) * 0.88
        : mix(mix(vec3(1.05, 0.88, 0.60), vec3(0.60, 0.94, 0.80), inBambooJungle * 0.45),
              vec3(1.12, 0.68, 0.40), vSunsetFactor) * 0.95;
    vec3 nightShaftColor = (STYLE_SELECTION == 0)
        ? vec3(0.52, 0.72, 0.76) * 0.86
        : vec3(0.48, 0.76, 1.02) * 0.92;

    float cloudBeam = cloudMode == 3 ? 0.0 : (1.0 - exp(-cloudScatter * 0.9)) * phase
                    * ((STYLE_SELECTION == 0) ? mix(0.14, 0.23, wetnessFactor) : mix(0.18, 0.26, wetnessFactor)) * modeScale * surfaceContrast
                    * timeScale * sourceVisibility * ATMOSPHERIC_SHAFT_STRENGTH;
    vec3 shaftColor = mix(nightShaftColor, dayShaftColor, vDaylightFactor);
    return shaftColor * clamp(shaftIntensity + cloudBeam, 0.0, 0.36);
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

#ifdef YUNMENG_CLOUD_PREPASS
void main() {
    outColor0 = vec4(0.0);
    outWaterEnvironment = vec4(0.0);
    outCloudLight = vec4(0.0);
    int mode = (CLOUD_TYPE == 0) ? (STYLE_SELECTION == 0 ? 1 : 2) : CLOUD_TYPE;
    // Only the active world-map rectangle needs an extinction integration.
    ivec2 mapSize=min(ivec2(vec2(viewWidth,viewHeight)*0.5),ivec2(cloudLightCacheResolution()));
    if (mode!=3 && vLightWorldDir.y>0.01 && all(lessThan(ivec2(gl_FragCoord.xy),mapSize))) {
        vec2 mapOrigin=cloudLightCacheOrigin(vec2(mapSize),cameraPosition,vLightWorldDir);
        vec2 xz=mapOrigin+gl_FragCoord.xy/vec2(mapSize)*2048.0;
        float rain,storm,flash;
        evaluateWeatherState(rain,storm,flash);
        outCloudLight=vec4(cloudColumnOpticalDepth(vec3(xz.x,64.0,xz.y),vLightWorldDir,
            frameTimeCounter,mode,rain,storm),1.0);
    }
    float depth = texture(depthtex0, vTexCoord).r;
    vec3 viewPos = reconstructViewPos(vTexCoord, depth);
    vec3 ray = normalize(viewPos);
    vec3 worldRay = normalize(mat3(gbufferModelViewInverse) * ray);
    vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
    if (isEyeInWater==1) {
        bool surface=depth<0.999999 && abs(texture(colortex1,vTexCoord).a-0.90)<0.05;
        // Opaque exterior geometry already exists in the scene. Only replace
        // sky behind the surface; do not draw an environment over trees/roofs.
        if ((surface || depth>=0.999999) && texture(depthtex1,vTexCoord).r>=0.999999) {
            vec3 n=surface ? normalize(mat3(gbufferModelViewInverse)
                * (texture(colortex1,vTexCoord).rgb*2.0-1.0)) : vec3(0.0,-1.0,0.0);
            n=waterFacingNormal(worldRay,n);
            vec3 exitRay=refract(worldRay,n,WATER_REFRACTIVE_INDEX);
            if (dot(exitRay,exitRay)>1e-5 && exitRay.y>0.0) {
                vec3 exitView=normalize(transpose(mat3(gbufferModelViewInverse))*exitRay);
                vec3 environment=evaluateUnifiedSky(exitRay,exitView);
                environment+=renderNightWuxiaAurora(exitRay,frameTimeCounter,NIGHT_AURORA);
                applyTexturedCelestialBodies(environment,exitRay);
                if (mode!=3) {
                    vec4 cloud=renderWuxiaVolumetricClouds(exitRay,exitView,
                        surface ? worldPos : cameraPosition,frameTimeCounter,environment,0.0,4200.0,mode,false);
                    environment=mix(environment,cloud.rgb,cloud.a);
                }
                outWaterEnvironment=vec4(environment,max(length(viewPos),0.001));
            }
        }
        return;
    }
    if (depth < 0.999999 && abs(texture(colortex1, vTexCoord).a - 0.90) < 0.05) {
        vec3 normal = normalize(texture(colortex1, vTexCoord).rgb * 2.0 - 1.0);
        vec3 reflectedView = normalize(reflect(ray, normal));
        vec3 reflectedWorld = normalize(mat3(gbufferModelViewInverse) * reflectedView);
        vec3 environment = evaluateUnifiedSky(reflectedWorld, reflectedView);
        // Preserve the broad celestial glow used on water, without a sharp disc.
        environment += renderNightWuxiaAurora(reflectedWorld, frameTimeCounter, NIGHT_AURORA);
        #if WATER_REFLECTIONS > 0
        if (mode != 3) {
            vec4 reflectedCloud = renderWuxiaVolumetricClouds(reflectedWorld, reflectedView,
                worldPos, frameTimeCounter, environment, 0.0, 4200.0, mode, true);
            environment = mix(environment, reflectedCloud.rgb, reflectedCloud.a);
        }
        #endif
        // Alpha carries the water distance for depth-aware reconstruction.
        outWaterEnvironment = vec4(environment, length(viewPos));
    }
    if (mode == 3) return;
    bool belowLayer = cameraPosition.y < 164.0 && worldPos.y < 164.0;
    float backgroundBlend = depth >= 0.999999 ? 1.0 : terrainSkyBlend(worldPos - cameraPosition);
    if (depth < 0.999999 && belowLayer && backgroundBlend <= 0.001) return;
    // Fogged terrain dissolves into the same cloudy sky as the unloaded horizon.
    float maxDistance = (depth >= 0.999999 || belowLayer) ? 4200.0 : length(viewPos);
    vec3 sky = evaluateUnifiedSky(worldRay, ray);
    vec4 cloud = renderWuxiaVolumetricClouds(worldRay, ray, cameraPosition, frameTimeCounter, sky, 0.0, maxDistance, mode, false);
    // Premultiply before interpolation to avoid dark fringes at cloud/sky edges.
    float fogVisibility = (depth < 0.999999 && belowLayer) ? backgroundBlend : 1.0;
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
    // A subpixel sky hole can have no valid half-size neighbor. Avoid a second
    // full-resolution march: nearest premultiplied cloud is a bounded fallback.
    return texelFetch(colortex8, clamp(center, ivec2(0), size-1), 0);

}
void main() {
#if LIGHT_SHAFTS > 0
    outAtmosphericShafts = vec4(0.0);
#endif
    vec4 sceneColor = texture(colortex0, vTexCoord);
    float depth0 = texture(depthtex0, vTexCoord).r;

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

        if (STYLE_SELECTION == 0) {
            vec3 deepSumiTeal = vec3(0.10, 0.22, 0.24);
            vec3 upperCeladon = vec3(0.32, 0.52, 0.50);
            uwFogColor   = mix(deepSumiTeal, upperCeladon, pow(upGradient, 0.85)) * mix(0.22, 1.0, vDaylightFactor);
            uwFogDensity = 0.052;
        } else {
            vec3 abyssalSapphire  = vec3(0.015, 0.11, 0.20);
            vec3 surfaceTurquoise = vec3(0.06, 0.36, 0.46);
            uwFogColor   = mix(abyssalSapphire, surfaceTurquoise, pow(upGradient, 0.75)) * mix(0.20, 1.0, vDaylightFactor);
            uwFogDensity = 0.046;
        }

        // Retain diffuse underwater visibility in overcast, while its direct
        // shafts below use the spatially varying incident cloud transmission.
        float uwRain, uwStorm, uwFlash;
        evaluateWeatherState(uwRain, uwStorm, uwFlash);
        uwFogColor *= mix(1.0, 0.82, uwRain) * mix(1.0, 0.82, uwStorm);
        bool waterSurface=depth0<0.999999 && abs(texture(colortex1,vTexCoord).a-0.90)<0.05;
        if ((waterSurface || depth0>=0.999999) && texture(depthtex1,vTexCoord).r>=0.999999) {
            vec4 environment=reconstructWaterEnvironment(vTexCoord,viewDist);
            vec3 n=waterSurface ? normalize(mat3(gbufferModelViewInverse)
                * (texture(colortex1,vTexCoord).rgb*2.0-1.0)) : vec3(0.0,-1.0,0.0);
            float transmission=waterExitTransmission(worldRayDir,n);
            finalRadiance=mix(finalRadiance,environment.rgb,environment.a*transmission);
        }
        float uwFogFactor = (depth0 >= 0.999999) ? 0.96 : clamp(1.0 - exp(-viewDist * uwFogDensity), 0.0, 0.96);
        finalRadiance = mix(finalRadiance * 0.88, uwFogColor, uwFogFactor);
        finalRadiance += computeUnderwaterLightShafts(viewPos, vLightWorldDir, cosTheta);

        outColor0 = vec4(finalRadiance, 1.0);
        return;
    }

    int activeCloudMode = (CLOUD_TYPE == 0) ? (STYLE_SELECTION == 0 ? 1 : 2) : CLOUD_TYPE;

    vec3 unifiedSky = evaluateUnifiedSky(worldRayDir, viewRayDir);
    float celestialDiscMask = 0.0;
    float horizonFogWeight  = 1.0;

    if (depth0 >= 0.999999) {
        float moonStarOcc = smoothstep(0.9965, 0.9982, dot(worldRayDir, vMoonWorldDir));
        float wetnessNow, stormNow, flashNow;
        evaluateWeatherState(wetnessNow, stormNow, flashNow);
        vec3 starAdd = sceneColor.rgb * vNightFactor * (1.0 - wetnessNow * 0.96) * (1.0 - moonStarOcc) * smoothstep(0.02, 0.12, worldRayDir.y);
        vec3 auroraCol = renderNightWuxiaAurora(worldRayDir, frameTimeCounter, NIGHT_AURORA);
        vec3 skyWithCelestials = unifiedSky + starAdd + auroraCol;

        celestialDiscMask = applyTexturedCelestialBodies(skyWithCelestials, worldRayDir);
        finalRadiance = skyWithCelestials;
    } else {
        vec4 mistAndBorder = computeValleyMistAndBorderFog(worldPos, playerPos, viewDist, unifiedSky);
        horizonFogWeight = mistAndBorder.a;
        finalRadiance = mix(finalRadiance, mistAndBorder.rgb, mistAndBorder.a);
    }

    // Unified 3D Volumetric Clouds (Skip raymarching on below-cloud terrain pixels for major GPU speedup)
    bool needsCloudTrace = (depth0 >= 0.999999) || (cameraPosition.y > 162.0) || (worldPos.y > 162.0)
                        || terrainSkyBlend(playerPos) > 0.001;
    if (activeCloudMode != 3 && needsCloudTrace) {
        vec4 volClouds = resolveClouds(depth0, viewDist);
        finalRadiance = finalRadiance * (1.0-volClouds.a) + volClouds.rgb;
    }

    vec3 shaftViewPos = viewPos;
    float shaftDepth = depth0;
    float shaftMaterial = texture(colortex1, vTexCoord).a;
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
    if (abs(shaftMaterial - 0.12) >= 0.007) {
        finalRadiance = applyAtmosphericPrecipitation(finalRadiance, unifiedSky, worldRayDir);
    }
    float sceneLuma = dot(finalRadiance, vec3(0.2126, 0.7152, 0.0722));
    vec3 lightShafts = computeVolumetricLightShafts(shaftViewPos, shaftDepth, cosTheta, sceneLuma, horizonFogWeight);
    finalRadiance += lightShafts;
#if LIGHT_SHAFTS > 0
    outAtmosphericShafts = vec4(lightShafts, 0.0);
#endif
#if SUN_LENS_FLARE > 0
    finalRadiance += renderSunLensFlare(vTexCoord);
#endif

    outColor0 = vec4(finalRadiance, 1.0);
}

#endif
