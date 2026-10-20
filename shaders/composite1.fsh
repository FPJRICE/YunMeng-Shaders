#version 330 compatibility
#include "/lib/temporal_jitter.glsl"
// Build 2 performance update: scalable cloud, shadow and shoreline settings.
/* =============================================================================
 * composite1.fsh — Unified 3D Volumetric Cloud Engine, Atmosphere & Night Sky
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
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex1;
uniform sampler2D noisetex;
uniform sampler2D celestialTex;
uniform sampler2D guofengMoonTex;
uniform sampler2D xianxiaMoonTex;
uniform sampler2D cloudTex;

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
uniform float rainStrength;
uniform float eyeAltitude;
uniform int frameCounter;
uniform int isEyeInWater;
uniform int moonPhase;

uniform float inBambooJungle;
uniform float inMountainBiome;
uniform float inCherryGrove;
uniform float eyeSkyFactor;

#if LIGHT_SHAFTS > 0
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
    vec3 u = f * f * (3.0 - 2.0 * f);

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

// True 3D volumetric value-noise field blended with planar cloud texture modulation
// (completely independent of 2D z-slice offset indexing).
float evaluateWuxiaCloudField3D(vec3 p) {
    float lattice3D = smoothNoise3D(p * 128.0);
    vec2 texSample  = sampleNoiseTexTiled(p.xz + vec2(p.y * 0.37, -p.y * 0.29)).rb;
    float texDetail = mix(texSample.x, texSample.y, 0.5);
    return mix(lattice3D, texDetail, 0.22);
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

void getLuminousCloudPalette(out vec3 cDeepFold, out vec3 cMidFold, out vec3 cWarmMid, out vec3 cSunCrest, out vec3 silverRimColor) {
    if (STYLE_SELECTION == 0) {
        vec3 dayDeep    = vec3(0.36, 0.45, 0.48);
        vec3 sunsetDeep = vec3(0.44, 0.32, 0.36);
        vec3 nightDeep  = vec3(0.025, 0.048, 0.085);

        vec3 dayMid     = vec3(0.54, 0.63, 0.64);
        vec3 sunsetMid  = vec3(0.70, 0.48, 0.38);
        vec3 nightMid   = vec3(0.050, 0.090, 0.145);

        vec3 dayWarm    = vec3(0.72, 0.78, 0.76);
        vec3 sunsetWarm = vec3(0.88, 0.64, 0.44);
        vec3 nightWarm  = vec3(0.085, 0.140, 0.210);

        vec3 dayCrest    = vec3(0.88, 0.88, 0.84);
        vec3 sunsetCrest = vec3(0.96, 0.76, 0.54);
        vec3 nightCrest  = vec3(0.140, 0.220, 0.300);

        cDeepFold = mix(nightDeep,  mix(dayDeep,  sunsetDeep,  vSunsetFactor), vDaylightFactor);
        cMidFold  = mix(nightMid,   mix(dayMid,   sunsetMid,   vSunsetFactor), vDaylightFactor);
        cWarmMid  = mix(nightWarm,  mix(dayWarm,  sunsetWarm,  vSunsetFactor), vDaylightFactor);
        cSunCrest = mix(nightCrest, mix(dayCrest, sunsetCrest, vSunsetFactor), vDaylightFactor);
        silverRimColor = mix(vec3(0.32, 0.46, 0.50), vec3(1.06, 0.92, 0.74), vDaylightFactor);
    } else {
        vec3 dayDeep    = vec3(0.42, 0.58, 0.74);
        vec3 sunsetDeep = vec3(0.46, 0.34, 0.48);
        vec3 nightDeep  = vec3(0.025, 0.050, 0.110);

        vec3 dayMid     = vec3(0.64, 0.76, 0.86);
        vec3 sunsetMid  = vec3(0.76, 0.50, 0.46);
        vec3 nightMid   = vec3(0.048, 0.092, 0.180);

        vec3 dayWarm    = vec3(0.82, 0.88, 0.93);
        vec3 sunsetWarm = vec3(0.92, 0.66, 0.48);
        vec3 nightWarm  = vec3(0.080, 0.150, 0.265);

        vec3 dayCrest    = vec3(0.95, 0.97, 0.99);
        vec3 sunsetCrest = vec3(1.04, 0.84, 0.60);
        vec3 nightCrest  = vec3(0.135, 0.235, 0.400);

        cDeepFold = mix(nightDeep,  mix(dayDeep,  sunsetDeep,  vSunsetFactor), vDaylightFactor);
        cMidFold  = mix(nightMid,   mix(dayMid,   sunsetMid,   vSunsetFactor), vDaylightFactor);
        cWarmMid  = mix(nightWarm,  mix(dayWarm,  sunsetWarm,  vSunsetFactor), vDaylightFactor);
        cSunCrest = mix(nightCrest, mix(dayCrest, sunsetCrest, vSunsetFactor), vDaylightFactor);
        silverRimColor = mix(vec3(0.34, 0.50, 0.74), vec3(1.10, 1.00, 0.86), vDaylightFactor);
    }

    float rainDim = 1.0 - rainStrength * 0.25;
    cDeepFold *= rainDim;
    cMidFold  *= rainDim;
    cWarmMid  *= rainDim;
    cSunCrest *= rainDim;
}

void applyCelestialCloudGlow(vec3 worldRayDir, float thinnessFactor, inout vec3 cloudColor) {
    float cosSun  = max(dot(worldRayDir, vSunWorldDir), 0.0);
    float cosMoon = max(dot(worldRayDir, vMoonWorldDir), 0.0);

    if (vDaylightFactor > 0.01) {
        float sunZoneWide = pow(cosSun, (STYLE_SELECTION == 0 ? 5.5 : 4.5)) * vDaylightFactor;
        float sunZoneMid  = pow(cosSun, (STYLE_SELECTION == 0 ? 16.0 : 12.0)) * vDaylightFactor;
        float sunZoneCore = pow(cosSun, (STYLE_SELECTION == 0 ? 48.0 : 36.0)) * vDaylightFactor;

        vec3 dayGlowWide = (STYLE_SELECTION == 0)
            ? mix(vec3(0.98, 0.74, 0.44), vec3(1.04, 0.58, 0.28), vSunsetFactor)
            : mix(vec3(1.04, 0.84, 0.55), vec3(1.10, 0.64, 0.35), vSunsetFactor);
        vec3 dayGlowCore = (STYLE_SELECTION == 0) ? vec3(1.08, 0.88, 0.58) : vec3(1.15, 0.95, 0.68);

        float clearFactor = 1.0 - rainStrength * 0.75;
        // Warm atmospheric sunlight wash over clouds facing the sun
        cloudColor = mix(cloudColor, max(cloudColor, dayGlowWide * clearFactor), sunZoneWide * 0.52);
        // Forward Mie scattering: thin cloud edges & crests catch a rich golden rim
        cloudColor += dayGlowWide * (sunZoneMid * 0.45) * thinnessFactor * clearFactor;
        cloudColor += dayGlowCore * (sunZoneCore * 0.65) * thinnessFactor * clearFactor;
    }

    if (vNightFactor > 0.01) {
        float moonRimZone = pow(cosMoon, 36.0) * vNightFactor * (1.0 - rainStrength * 0.80);
        vec3 moonRimTint  = (STYLE_SELECTION == 0) ? vec3(0.28, 0.42, 0.46) : vec3(0.26, 0.44, 0.68);
        cloudColor += moonRimTint * moonRimZone * thinnessFactor * 0.28;
    }
}

vec3 evaluateUnifiedSky(vec3 worldRayDir, vec3 viewRayDir) {
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
        vec3 nightMid      = vec3(0.035, 0.065, 0.11);
        vec3 nightHorizon  = vec3(0.06, 0.10, 0.15);

        zenithCol  = mix(nightZenith,  mix(noonZenith,  sunsetZenith,  vSunsetFactor), vDaylightFactor);
        midCol     = mix(nightMid,     mix(noonMid,     sunsetMid,     vSunsetFactor), vDaylightFactor);
        horizonCol = mix(nightHorizon, mix(noonHorizon, sunsetHorizon, vSunsetFactor), vDaylightFactor);
    } else {
        vec3 noonZenith    = vec3(0.14, 0.44, 0.76);
        vec3 noonMid       = vec3(0.32, 0.64, 0.86);
        vec3 noonHorizon   = vec3(0.68, 0.84, 0.92);

        vec3 sunsetZenith  = vec3(0.14, 0.22, 0.52);
        vec3 sunsetMid     = vec3(0.78, 0.44, 0.48);
        vec3 sunsetHorizon = vec3(0.98, 0.64, 0.42);

        vec3 nightZenith   = vec3(0.015, 0.03, 0.075);
        vec3 nightMid      = vec3(0.035, 0.07, 0.14);
        vec3 nightHorizon  = vec3(0.06,  0.11, 0.20);

        zenithCol  = mix(nightZenith,  mix(noonZenith,  sunsetZenith,  vSunsetFactor), vDaylightFactor);
        midCol     = mix(nightMid,     mix(noonMid,     sunsetMid,     vSunsetFactor), vDaylightFactor);
        horizonCol = mix(nightHorizon, mix(noonHorizon, sunsetHorizon, vSunsetFactor), vDaylightFactor);
    }

    float nightBiomeScale = mix(0.18, 1.0, vDaylightFactor);
    vec3 bambooJade   = ((STYLE_SELECTION == 0) ? vec3(0.54, 0.72, 0.66) : vec3(0.38, 0.72, 0.64)) * nightBiomeScale;
    vec3 mountainGray = ((STYLE_SELECTION == 0) ? vec3(0.72, 0.77, 0.78) : vec3(0.64, 0.74, 0.84)) * nightBiomeScale;
    vec3 cherryRose   = vec3(0.88, 0.72, 0.80) * nightBiomeScale;

    horizonCol = mix(horizonCol, bambooJade,   bambooWeight * 0.45);
    horizonCol = mix(horizonCol, mountainGray, mountainWeight * 0.40);
    horizonCol = mix(horizonCol, cherryRose,   cherryWeight * 0.35);

    float upFactor = clamp(VdotU, 0.0, 1.0);
    float midCurve = pow(1.0 - upFactor, 2.2);
    float horCurve = pow(1.0 - abs(VdotU), 5.5);

    vec3 sky = mix(zenithCol, midCol, midCurve);
    sky = mix(sky, horizonCol, horCurve);

    if (VdotU < 0.0) {
        float downT = clamp(-VdotU * 2.8, 0.0, 1.0);
        vec3 nadirAbyss = mix(zenithCol * 0.55, midCol * 0.75, vDaylightFactor);
        sky = mix(horizonCol, nadirAbyss, downT);
    }

    float rayHorizonGate = smoothstep(-0.02, 0.12, VdotU);
    float sunElevGate    = smoothstep(-0.02, 0.12, vSunWorldDir.y) * rayHorizonGate;
    float moonElevGate   = smoothstep(-0.02, 0.12, vMoonWorldDir.y) * rayHorizonGate;

    float sunGlare  = pow(clamp(VdotS, 0.0, 1.0), (STYLE_SELECTION == 0 ? 18.0 : 14.0)) * (STYLE_SELECTION == 0 ? 0.15 : 0.18) * sunElevGate;
    float moonGlare = pow(clamp(VdotM, 0.0, 1.0), 16.0) * 0.10 * moonElevGate;
    vec3 sunGlareCol = (STYLE_SELECTION == 0)
        ? mix(vec3(0.98, 0.76, 0.42), vec3(1.04, 0.50, 0.24), vSunsetFactor)
        : mix(vec3(1.00, 0.85, 0.58), vec3(1.10, 0.58, 0.30), vSunsetFactor);
    vec3 moonGlareCol = (STYLE_SELECTION == 0) ? vec3(0.45, 0.58, 0.56) : vec3(0.36, 0.56, 0.78);

    sky += (sunGlareCol * sunGlare + moonGlareCol * moonGlare) * (1.0 - rainStrength * 0.8);
    return sky;
}


float applyTexturedCelestialBodies(inout vec3 skyRadiance, vec3 worldRayDir) {
    float sunAngularScale  = 0.082 * SUN_SIZE;
    float moonAngularScale = 0.080 * SUN_SIZE;
    float celestialDiscMask = 0.0;

    // Clip softly at the actual horizon, not several degrees above it.
    // Body visibility starts below the horizon so the upper limb rises first.
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
    if (cosSun > 0.85 && sunHorizonVis > 0.001) {
        vec3 poleAxis = (abs(dot(vSunWorldDir, ORBIT_POLE)) > 0.92) ? vec3(1.0, 0.0, 0.0) : ORBIT_POLE;
        vec3 sunRight = normalize(cross(vSunWorldDir, poleAxis));
        vec3 sunUp    = normalize(cross(sunRight, vSunWorldDir));
        vec2 sunUV    = vec2(dot(worldRayDir, sunRight), dot(worldRayDir, sunUp)) / (0.096 * SUN_SIZE);
        float rSun    = length(sunUV);

        float outerCorona = exp(-max(rSun - 0.62, 0.0) * 3.2) * smoothstep(2.4, 0.62, rSun) * (STYLE_SELECTION == 0 ? 0.14 : 0.18) * sunHorizonVis;
        vec3 coronaColor  = (STYLE_SELECTION == 0)
            ? mix(vec3(0.98, 0.72, 0.38), vec3(1.02, 0.48, 0.22), vSunsetFactor)
            : mix(vec3(1.02, 0.82, 0.46), vec3(1.08, 0.56, 0.26), vSunsetFactor);
        skyRadiance += coronaColor * outerCorona * (1.0 - rainStrength);

        if (rSun < 1.18) {
            vec2 atlasUV;
            vec2 localSunUV = clamp(sunUV * 0.45 + 0.5, 0.005, 0.995);
            if (STYLE_SELECTION == 0) {
                // Guofeng Ink Sun in Left Half [x=0..512, y=0..512] of 1024x512 wuxia_celestial.png
                atlasUV = vec2(localSunUV.x * 0.5, localSunUV.y);
            } else {
                // Xianxia Mist Sun in Right Half [x=512..1024, y=0..512] of 1024x512 wuxia_celestial.png
                atlasUV = vec2(0.5 + localSunUV.x * 0.5, localSunUV.y);
            }

            vec4 texSun = texture(celestialTex, atlasUV);
            float edgeFade = smoothstep(1.15, 0.88, rSun);
            float sunAlpha = texSun.a * edgeFade * (1.0 - rainStrength * 0.85) * sunHorizonVis;

            if (sunAlpha > 0.001) {
                vec3 sunArtwork = texSun.rgb;
                if (STYLE_SELECTION == 0) {
                    vec3 sunsetTint = mix(vec3(0.98, 0.94, 0.88), vec3(1.12, 0.58, 0.36), vSunsetFactor);
                    sunArtwork *= sunsetTint;

                    float discBleed = exp(-max(rSun - 0.50, 0.0) * 3.8) * 0.20;
                    vec3 bleedColor = mix(vec3(0.98, 0.74, 0.40), vec3(1.04, 0.50, 0.24), vSunsetFactor);
                    skyRadiance += bleedColor * discBleed * (1.0 - rainStrength * 0.85) * sunHorizonVis;

                    skyRadiance = mix(skyRadiance, sunArtwork, sunAlpha);
                } else {
                    vec3 solarBrilliance = mix(vec3(0.98, 0.94, 0.86), vec3(1.14, 0.64, 0.38), vSunsetFactor);
                    sunArtwork *= solarBrilliance;

                    float solarBloom = exp(-max(rSun - 0.50, 0.0) * 3.6) * 0.22;
                    vec3 bloomColor  = mix(vec3(1.00, 0.80, 0.44), vec3(1.10, 0.58, 0.26), vSunsetFactor);
                    skyRadiance += bloomColor * solarBloom * (1.0 - rainStrength * 0.85) * sunHorizonVis;

                    skyRadiance = mix(skyRadiance, sunArtwork, sunAlpha);
                }

                // Track full solar emblem + cloud-scroll halo so volumetric clouds punch through cleanly!
                celestialDiscMask = max(celestialDiscMask, clamp(sunAlpha * 1.15, 0.0, 1.0));
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
        // Illuminated fraction & horizontal phase bias so the lunar corona & mist glow
        // radiate strongest from the lit side of the crescent/gibbous moon!
        float phaseIllumFrac = (mPhase == 0) ? 1.00 : ((mPhase == 4) ? 0.18 : ((mPhase == 1 || mPhase == 7) ? 0.78 : ((mPhase == 2 || mPhase == 6) ? 0.54 : 0.34)));
        float phaseDirX      = (mPhase >= 1 && mPhase <= 3) ? -1.0 : ((mPhase >= 5 && mPhase <= 7) ? 1.0 : 0.0);
        float dirBias        = 1.0 + 0.28 * phaseDirX * clamp(moonUV.x / max(rMoon, 0.25), -1.0, 1.0);

        // Multi-layered atmospheric lunar bloom:
        // 1) Wide soft Mie scattering aura into the night sky & aurora
        // 2) Inner limb-diffusion cushion straddling rMoon = 0.55..1.35 to soften the disc border
        float wideLunarAura = exp(-rMoon * 1.15) * smoothstep(4.2, 0.45, rMoon) * 0.16;
        float limbDiffusion = exp(-max(rMoon - 0.54, 0.0) * 3.2) * smoothstep(2.0, 0.54, rMoon) * 0.20;
        float totalHalo     = (wideLunarAura + limbDiffusion) * phaseIllumFrac * dirBias * moonHorizonVis * (1.0 - rainStrength);

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
            float rawAlpha = texMoon.a * edgeFade * (1.0 - rainStrength * 0.85) * moonHorizonVis;

            if (rawAlpha > 0.001) {
                // Atmospheric Screen + Surface Blend:
                // - Both guofengMoonTex and xianxiaMoonTex now encode a wide, velvety penumbral terminator
                //   and translucent earthshine alpha (0.22 on shadowed disc, 0.06 on shadowed wisps/ring).
                // - By blending toward `max(skyRadiance + texMoon.rgb * 0.22, texMoon.rgb * litTint)`,
                //   the moon NEVER darkens the night sky or aurora on the shadowed side (zero dark cutout!),
                //   while preserving every ink brushstroke and Moon Palace detail on the sunlit side!
                vec3 litTint = (STYLE_SELECTION == 0) ? vec3(0.96, 0.95, 0.90) : vec3(0.92, 0.97, 1.00);
                vec3 targetMoon = max(skyRadiance + texMoon.rgb * 0.24, texMoon.rgb * litTint);

                // Soft atmospheric rim diffusion where the lunar disc meets the sky halo
                float rimFeather = 1.0 - smoothstep(0.58, 0.96, rMoon) * 0.25;
                float effectiveAlpha = rawAlpha * rimFeather;

                skyRadiance = mix(skyRadiance, targetMoon, effectiveAlpha);
                celestialDiscMask = max(celestialDiscMask, clamp(effectiveAlpha * 1.05, 0.0, 1.0));
            }
        }
    }

    return celestialDiscMask;
}

/* -----------------------------------------------------------------------------
 * V16 PAINTERLY 3D CELESTIAL AURORA CURTAINS & ASTRAL NEBULA ARCH
 * ----------------------------------------------------------------------------- */
vec3 renderNightWuxiaAurora(vec3 worldRayDir, float time, int auroraMode) {
    if (auroraMode == 3 || vNightFactor <= 0.01 || worldRayDir.y <= 0.01) {
        return vec3(0.0);
    }

    int activeAuroraStyle = (auroraMode == 0) ? (STYLE_SELECTION == 1 ? 1 : 2) : auroraMode;
    float nightVis = vNightFactor * (1.0 - rainStrength * 0.88);
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

/* -----------------------------------------------------------------------------
 * V16 UNIFIED 3D VOLUMETRIC CLOUD ENGINE (BEER-LAMBERT TRANSMITTANCE INTEGRATION)
 * - Uses independent asymmetric condensation envelope & Beer-Lambert absorption
 *   model extending 4200m to the horizon!
 * ----------------------------------------------------------------------------- */
const float WUXIA_CLOUD_BASE_Y   = 174.0;
const float WUXIA_CLOUD_TOP_Y    = 210.0;
const float WUXIA_CLOUD_HEIGHT   = 36.0;

float sampleWuxiaCloudVolume3D(vec3 tracePos, float time, int activeCloudMode) {
    if (tracePos.y < WUXIA_CLOUD_BASE_Y || tracePos.y > WUXIA_CLOUD_TOP_Y) return 0.0;

    float relH = (tracePos.y - WUXIA_CLOUD_BASE_Y) / WUXIA_CLOUD_HEIGHT;
    // Flat condensation cloud-base below (0.0..0.18) and rounded billowing upper domes (0.40..1.0)
    float baseCondense = smoothstep(0.00, 0.18, relH);
    float domeCeiling  = smoothstep(1.00, 0.42, relH);
    float heightEnvelope = baseCondense * domeCeiling;

    vec3 baseCoord = tracePos * 0.000125;
    if (activeCloudMode == 1) {
        baseCoord.x *= 0.82; // Elongated Shanshui scroll bands in Guofeng mode
    }

    float drift = time * 0.00055;
    vec3 windOffset = vec3(drift * 0.18, 0.0, drift);

    // 1. Macro sky-cluster envelope (~600m formations across the sky)
    vec3 macroPos = tracePos * 0.000038 - vec3(drift * 0.12, 0.0, drift * 0.35);
    float macroShape = evaluateWuxiaCloudField3D(macroPos);

    // 2. Rotated 3D multi-scale billow & erosion synthesis (no 2D slice-stepping)
    const mat2 ROT_XZ = mat2(0.80, -0.60, 0.60, 0.80);
    vec3 q0 = baseCoord - windOffset;

    vec3 q1 = baseCoord * 2.85 - windOffset * 1.40;
    q1.xz = ROT_XZ * q1.xz + vec2(1.73, 3.19);

    vec3 q2 = baseCoord * 8.12 - windOffset * 1.95;
    q2.xz = ROT_XZ * q2.xz + vec2(4.27, 1.83);

    vec3 q3 = baseCoord * 23.15 - windOffset * 2.70;
    q3.xz = ROT_XZ * q3.xz + vec2(2.61, 5.41);

    float billow0 = evaluateWuxiaCloudField3D(q0);
    float billow1 = evaluateWuxiaCloudField3D(q1);
    float cloudSignal = macroShape * 0.266
                      + billow0    * 0.391
                      + billow1    * 0.196;
    #if CLOUD_QUALITY >= 1
    cloudSignal += evaluateWuxiaCloudField3D(q2) * 0.098;
    #endif
    #if CLOUD_QUALITY >= 2
    cloudSignal += evaluateWuxiaCloudField3D(q3) * 0.049;
    #elif CLOUD_QUALITY == 1
    cloudSignal /= 0.951;
    #else
    cloudSignal /= 0.853;
    #endif

    float rainExpand = 1.18 + 0.28 * rainStrength;
    float shapedDensity = (cloudSignal * cloudSignal * rainExpand - 0.228) * heightEnvelope;
    return max(shapedDensity * 1.88, 0.0);
}

vec4 renderWuxiaVolumetricClouds(vec3 rayDirWorld, vec3 viewRayDir, vec3 camPos, float time, vec3 bgSkyColor, float celestialDiscMask, float maxSceneDist, int activeCloudMode) {
    float lowerAlt     = WUXIA_CLOUD_BASE_Y;
    float higherAlt    = WUXIA_CLOUD_TOP_Y;
    float maxTraceDist = 4200.0;

    vec3 cloudRayDir = rayDirWorld;
    float tStart = 0.0;
    float tEnd   = 0.0;

    if (camPos.y < lowerAlt) {
        float nearSlab = smoothstep(lowerAlt - 55.0, lowerAlt, camPos.y);
        float minRayY  = mix(0.008, 0.001, nearSlab);
        if (rayDirWorld.y <= minRayY) return vec4(0.0);

        cloudRayDir = normalize(vec3(rayDirWorld.x, max(rayDirWorld.y + mix(0.032, 0.0, nearSlab), 0.002), rayDirWorld.z));
        tStart = (lowerAlt  - camPos.y) / cloudRayDir.y;
        tEnd   = (higherAlt - camPos.y) / cloudRayDir.y;
    } else if (camPos.y <= higherAlt) {
        tStart = 0.0;
        if (rayDirWorld.y > 0.003) {
            tEnd = (higherAlt - camPos.y) / rayDirWorld.y;
        } else if (rayDirWorld.y < -0.003) {
            tEnd = (lowerAlt  - camPos.y) / rayDirWorld.y;
        } else {
            tEnd = 1200.0;
        }
        tEnd = min(tEnd, 1200.0);
    } else {
        float nearTop = smoothstep(higherAlt + 55.0, higherAlt, camPos.y);
        float maxRayY = mix(-0.010, -0.001, nearTop);
        if (rayDirWorld.y >= maxRayY) return vec4(0.0);

        tStart = (higherAlt - camPos.y) / rayDirWorld.y;
        tEnd   = (lowerAlt  - camPos.y) / rayDirWorld.y;
    }

    tStart = max(tStart, 0.0);
    if (tStart >= maxSceneDist || tEnd <= tStart || tStart >= maxTraceDist) return vec4(0.0);
    tEnd = min(tEnd, min(maxSceneDist, min(tStart + 2400.0, maxTraceDist)));

    #if CLOUD_QUALITY == 0
    const int STEPS = 8;
    #elif CLOUD_QUALITY == 1
    const int STEPS = 12;
    #elif CLOUD_QUALITY == 2
    const int STEPS = 18;
    #else
    const int STEPS = 26;
    #endif
    float stepSize  = (tEnd - tStart) / float(STEPS);
    float dither    = interleavedGradientNoise(gl_FragCoord.xy);

    vec3 stepVec  = cloudRayDir * stepSize;
    vec3 tracePos = camPos + cloudRayDir * (tStart + stepSize * (0.25 + 0.45 * dither));

    float cosLight = dot(viewRayDir, vLightViewDir);
    float sourceVisibility = smoothstep(0.0, 0.10, vLightWorldDir.y);
    float silverLiningPhase = henyeyGreensteinPhase(cosLight, 0.72) * 1.4
                            + henyeyGreensteinPhase(cosLight, 0.28) * 0.45;
    silverLiningPhase *= sourceVisibility;

    vec3 cDeepFold, cMidFold, cWarmMid, cSunCrest, silverRimColor;
    getLuminousCloudPalette(cDeepFold, cMidFold, cWarmMid, cSunCrest, silverRimColor);

    vec3 accumColor = vec3(0.0);
    float accumTransmittance = 1.0;

    float cachedShadowDensity = 0.0;
    bool hasShadowSample = false;
    for (int i = 0; i < STEPS; i++) {
        float distXZ = length(tracePos.xz - camPos.xz);
        if (distXZ > maxTraceDist) break;

        float cloudDensity = sampleWuxiaCloudVolume3D(tracePos, time, activeCloudMode);

        if (cloudDensity > 0.00001) {
            float heightShading = clamp((tracePos.y - lowerAlt) / WUXIA_CLOUD_HEIGHT, 0.0, 1.0);

            #if CLOUD_QUALITY == 0
            // Density-based shading avoids a second volume query on Low.
            float shadowDensity = cloudDensity;
            #else
            // Medium/High reuse the nearby sample for alternate ray steps.
            // Ultra retains the full per-step self-shadow evaluation.
            if (CLOUD_QUALITY >= 3 || !hasShadowSample || (i % 2) == 0) {
                vec3 lightSamplePos = tracePos + vLightWorldDir * 10.5;
                cachedShadowDensity = sampleWuxiaCloudVolume3D(lightSamplePos, time, activeCloudMode);
                hasShadowSample = true;
            }
            float shadowDensity = cachedShadowDensity;
            #endif
            shadowDensity *= sourceVisibility;
            float lightTrans    = 0.38 + 0.62 * exp(-shadowDensity * 3.6);

            float cloudShading = clamp((0.32 + 0.68 * heightShading) * lightTrans, 0.0, 1.0);

            float s1 = smoothstep(0.20, 0.46, cloudShading);
            float s2 = smoothstep(0.46, 0.72, cloudShading);
            float s3 = smoothstep(0.70, 0.88, cloudShading);

            vec3 colorSample = mix(cDeepFold, cMidFold, s1);
            colorSample = mix(colorSample, cWarmMid,  s2);
            colorSample = mix(colorSample, cSunCrest, s3);

            float thinTrans = exp(-shadowDensity * 2.0);
            // Rim-light cloud edges around the sun without bleaching the cloud face directly in front of the disc
            float rimMask = celestialDiscMask * (1.0 - celestialDiscMask) * 3.5;
            float silverBoost = (silverLiningPhase + rimMask) * thinTrans;
            colorSample += silverRimColor * clamp(silverBoost * 0.28, 0.0, 0.52);

            applyCelestialCloudGlow(rayDirWorld, thinTrans, colorSample);

            // Distance atmospheric haze at far horizon boundary (> 2400m)
            float horizonHaze = smoothstep(2200.0, 4200.0, distXZ);
            colorSample = mix(colorSample, bgSkyColor, horizonHaze * 0.42);

            // Physically-based Beer-Lambert transmittance integration
            float opticalScale = (activeCloudMode == 1) ? 0.042 : 0.045;
            float stepOpticalDepth = cloudDensity * stepSize * opticalScale;
            float stepAlpha = 1.0 - exp(-stepOpticalDepth);
            float stepWeight = accumTransmittance * stepAlpha;

            accumColor += colorSample * stepWeight;
            accumTransmittance *= (1.0 - stepAlpha);

            if (accumTransmittance < 0.03) {
                accumTransmittance = 0.0;
                break;
            }
        }
        tracePos += stepVec;
    }

    float totalAlpha = 1.0 - accumTransmittance;
    if (totalAlpha <= 0.001) return vec4(0.0);

    vec3 finalCloudColor = accumColor / max(totalAlpha, 1e-4);

    float groundModeWeight = 1.0 - smoothstep(lowerAlt - 45.0, lowerAlt - 5.0, camPos.y);
    // Smooth horizon fade that doesn't disappear when looking slightly upward
    float grazingFade      = mix(1.0, smoothstep(0.002, 0.065, rayDirWorld.y), groundModeWeight);
    // Balanced visibility: soft artistic definition without being harsh or opaque
    float finalCloudAlpha  = clamp(pow(totalAlpha, 0.85) * (activeCloudMode == 1 ? 0.76 : 0.82) * grazingFade, 0.0, 0.86);

    return vec4(finalCloudColor, finalCloudAlpha);
}

vec4 computeValleyMistAndBorderFog(vec3 worldPos, vec3 playerPos, float viewDist, vec3 skyAtRay) {
    float lPosXZ = length(playerPos.xz);
    float borderRatio = lPosXZ / max(far * 0.76, 40.0);
    float borderFog = 1.0 - exp(-4.8 * pow(borderRatio, 3.8));
    borderFog = clamp(borderFog, 0.0, 1.0);

    float densityMult = FOG_DENSITY * mix(1.0, 1.35, rainStrength);
    float delayedDist = max(viewDist - 36.0, 0.0);
    float distFog = (1.0 - exp(-pow(delayedDist / max(far * 0.95, 80.0), 1.45) * 0.55 * densityMult))
                  * smoothstep(28.0, 72.0, viewDist);

    float valleyDelta = (worldPos.y - SEA_OF_CLOUDS_ALTITUDE) / max(SEA_OF_CLOUDS_THICKNESS, 1.0);
    float valleyBand  = exp(-valleyDelta * valleyDelta * 1.85);

    vec2 mistDriftUV = worldPos.xz * 0.012 + vec2(frameTimeCounter * 0.032, -frameTimeCounter * 0.020);
    float billowingNoise = fbm2D(mistDriftUV);
    float seaOfCloudsFactor = valleyBand * smoothstep(0.34, 0.80, billowingNoise) * smoothstep(32.0, 120.0, viewDist);
    float seaStrength = (STYLE_SELECTION == 1 || CLOUD_TYPE == 2) ? 0.60 : 0.38;

    float valleyFog = clamp(distFog + seaOfCloudsFactor * seaStrength * densityMult, 0.0, 0.82);

    float combinedFogFactor = clamp(max(valleyFog, borderFog), 0.0, 1.0);
    return vec4(skyAtRay, combinedFogFactor);
}

vec3 computeUnderwaterLightShafts(vec3 viewPos, vec3 lightDirWorld, float cosTheta) {
    #if LIGHT_SHAFTS == 0
    return vec3(0.0);
    #else
    const int UW_STEPS = (LIGHT_SHAFTS >= 2) ? 14 : 8;
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
        if (shadowUV.x > 0.0 && shadowUV.x < 1.0 && shadowUV.y > 0.0 && shadowUV.y < 1.0) {
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
        accumBeams += shadowVis * causticLens * distAtten;
        currentViewPos += stepVecView;
    }

    accumBeams /= float(UW_STEPS);

    vec3 worldRayDir = normalize(mat3(gbufferModelViewInverse) * rayDirView);
    float upLookBoost = smoothstep(-0.45, 0.85, worldRayDir.y) * 0.65 + 0.35;
    float sunAlign    = henyeyGreensteinPhase(dot(worldRayDir, refractSunWorld), 0.55);

    float beamStrength = accumBeams * (0.75 + sunAlign * 0.55) * upLookBoost * mix(0.25, 1.0, vDaylightFactor) * float(LIGHT_SHAFTS);
    beamStrength *= smoothstep(0.0, 0.10, lightDirWorld.y);

    if (STYLE_SELECTION == 0) {
        return vec3(0.56, 0.78, 0.72) * clamp(beamStrength * 0.75, 0.0, 0.65);
    } else {
        return vec3(0.28, 0.88, 0.86) * clamp(beamStrength * 1.05, 0.0, 0.82);
    }
    #endif
}

vec3 computeVolumetricLightShafts(vec3 viewPos, float depth0, float cosTheta, float sceneLuma) {
    #if LIGHT_SHAFTS == 0
    return vec3(0.0);
    #else
    const float MAX_SHAFT_RANGE = (LIGHT_SHAFTS >= 2) ? 64.0 : 52.0;
    float maxRayDist = min(length(viewPos), MAX_SHAFT_RANGE);
    float sourceVisibility = smoothstep(0.0, 0.10, vLightWorldDir.y);
    if (maxRayDist <= 0.45 || sourceVisibility <= 0.0 || ATMOSPHERIC_SHAFT_STRENGTH <= 0.0) return vec3(0.0);
    // Held items are foreground geometry, outside the atmospheric volume.
    if (abs(texture(colortex1, vTexCoord).a - 0.12) < 0.007) return vec3(0.0);

    const int RAY_STEPS = (LIGHT_SHAFTS >= 2) ? 64 : 32;
    // Stable sampling avoids frame-to-frame noise without temporal accumulation.
    float dither = hash12(gl_FragCoord.xy);

    // Start the ray outside the first-person player torso/head and held-item zone.
    float minRayDist = min(1.25, maxRayDist * 0.28);
    vec3 rayDirView = normalize(viewPos);
    vec3 rayDirPlayer = mat3(gbufferModelViewInverse) * rayDirView;
    vec3 rayOriginPlayer = gbufferModelViewInverse[3].xyz;
    // The shadow projection is orthographic: transform the ray once per pixel.
    vec3 shadowOrigin = (shadowProjection * (shadowModelView * vec4(rayOriginPlayer, 1.0))).xyz;
    vec3 shadowDirection = (shadowProjection * (shadowModelView * vec4(rayDirPlayer, 0.0))).xyz;
    // Shadow-map Z scale per meter along the light vector (accounts for distortShadowClipPos z *= 0.2 and * 0.5 + 0.5).
    vec3 lightStepShadowClip = (shadowProjection * (shadowModelView * vec4(vLightWorldDir, 0.0))).xyz;
    float oneMeterShadowZ = max(abs(lightStepShadowClip.z) * 0.1, 1e-5);

    float litScatter = 0.0;
    for (int i = 0; i < RAY_STEPS; i++) {
        // Front-weighted sample distribution concentrates resolution across nearby windows,
        // cave mouths, and foliage canopies while covering the full mid-range air volume.
        float u0 = float(i) / float(RAY_STEPS);
        float u1 = float(i + 1) / float(RAY_STEPS);
        float f0 = u0 * (0.36 + 0.64 * u0);
        float f1 = u1 * (0.36 + 0.64 * u1);
        float cellStart = mix(minRayDist, maxRayDist, f0);
        float cellEnd   = mix(minRayDist, maxRayDist, f1);
        float stepLen   = cellEnd - cellStart;
        float sampleDistance = mix(cellStart, cellEnd, dither);

        vec3 shadowClipPos = distortShadowClipPos(shadowOrigin + shadowDirection * sampleDistance);
        vec3 shadowUV = shadowClipPos * 0.5 + 0.5;

        if (all(greaterThan(shadowUV, vec3(0.001))) && all(lessThan(shadowUV, vec3(0.999)))) {
            float shadowMapDepth = texture(shadowtex1, shadowUV.xy).r;
            float isUnoccluded = step(shadowUV.z - 0.0005, shadowMapDepth);

            if (isUnoccluded < 0.5) {
                // Reconstruct the 3D player-space position of the shadow caster along vLightWorldDir.
                // If the caster sits inside the player's own first-person body volume, ignore the
                // self-shadow so player movement/turning cannot cast streaks through the air.
                float casterDist = max((shadowUV.z - shadowMapDepth) / oneMeterShadowZ, 0.0);
                vec3 casterPlayerPos = (rayOriginPlayer + rayDirPlayer * sampleDistance) + vLightWorldDir * casterDist;
                if (length(casterPlayerPos.xz) < 0.65 && casterPlayerPos.y > -1.80 && casterPlayerPos.y < 0.35) {
                    isUnoccluded = 1.0;
                }
            }

            float worldY = rayOriginPlayer.y + rayDirPlayer.y * sampleDistance + cameraPosition.y;
            float mistDensity = exp(-max(worldY - SEA_OF_CLOUDS_ALTITUDE, 0.0) * 0.012);
            // Near/mid-field Tyndall kernel: a 3m..6m sunbeam through a window, cave opening,
            // or foliage gap accumulates strong scattering without requiring a 100m path.
            float radialWeight = exp(-sampleDistance / 14.0) * (stepLen / 4.5);
            float densityWeight = (0.78 + 0.22 * mistDensity) * radialWeight;
            litScatter += isUnoccluded * densityWeight;
        }
    }

    // Strictly monotonic saturation: occlusion only reduces scattering and can never amplify a ray.
    float beamResponse = 1.0 - exp(-1.35 * litScatter * min(FOG_DENSITY, 1.35));

    // Side-view friendly phase function: strong Rayleigh/isotropic side-scatter baseline so beams
    // remain clearly visible from 60..120 deg side views when the sun/moon is off-screen.
    float forwardMie = min(henyeyGreensteinPhase(clamp(cosTheta, -1.0, 1.0), 0.40) * 12.5663706, 2.3);
    float phase = 0.62 + 0.36 * forwardMie;

    // Smooth camera-enclosure adaptation from the global eyeSkyFactor uniform (spatially constant).
    float enclosureGain = mix(1.24, 0.82, smoothstep(0.50, 0.95, eyeSkyFactor));

    // Soft-shoulder destination luminance protection: beams pop vividly across shaded interiors,
    // cave walls, and tree trunks while avoiding washout over bright sunlit ground or sky.
    float skyDamp = (depth0 >= 0.999999) ? 0.55 : 1.0;
    float surfaceContrast = (1.0 - smoothstep(0.26, 0.72, sceneLuma) * 0.76) * skyDamp;

    float modeScale = (LIGHT_SHAFTS >= 2) ? 1.00 : 0.75;
    float timeScale = mix(0.88, 1.00, vDaylightFactor);
    float nearSurfaceFade = smoothstep(0.45, 1.80, maxRayDist);
    float weatherVisibility = 1.0 - rainStrength * 0.85;

    float shaftIntensity = beamResponse * phase * enclosureGain * surfaceContrast *
                           0.32 * modeScale * ATMOSPHERIC_SHAFT_STRENGTH *
                           timeScale * nearSurfaceFade * sourceVisibility * weatherVisibility;

    vec3 dayShaftColor = (STYLE_SELECTION == 0)
        ? mix(vec3(1.02, 0.84, 0.56), vec3(1.08, 0.64, 0.38), vSunsetFactor) * 0.88
        : mix(mix(vec3(1.05, 0.88, 0.60), vec3(0.60, 0.94, 0.80), inBambooJungle * 0.45),
              vec3(1.12, 0.68, 0.40), vSunsetFactor) * 0.95;
    vec3 nightShaftColor = (STYLE_SELECTION == 0)
        ? vec3(0.52, 0.72, 0.76) * 0.86
        : vec3(0.48, 0.76, 1.02) * 0.92;

    vec3 shaftColor = mix(nightShaftColor, dayShaftColor, vDaylightFactor);
    return shaftColor * clamp(shaftIntensity, 0.0, 0.36);
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
    // Project a direction (w=0), so camera translation cannot move the flare.
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
    // The bright arc faces away from the screen center and turns as the sun moves.
    vec2 outwardVector = (sunUV - vec2(0.5)) * aspect + vec2(0.0001, 0.0);
    vec2 outward = outwardVector / max(length(outwardVector), 0.0001);
    float arc = smoothstep(-0.30, 0.48, dot(relative / max(r, 0.0001), outward));
    float ringRadius = (STYLE_SELECTION == 0) ? 0.14 : 0.17;
    float width = (STYLE_SELECTION == 0) ? 0.0045 : 0.0055;
    vec2 towardCenter = vec2(0.5) - sunUV;
    vec2 ghostCenterA = sunUV + towardCenter * 0.78;
    vec2 ghostCenterB = sunUV + towardCenter * 1.42;
    // Place the second arc beyond the view center along the sun-to-camera line.
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
        smoothstep(-0.03, 0.10, vSunWorldDir.y) * (1.0 - rainStrength * 0.9);
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

        float uwFogFactor = (depth0 >= 0.999999) ? 0.96 : clamp(1.0 - exp(-viewDist * uwFogDensity), 0.0, 0.96);
        finalRadiance = mix(finalRadiance * 0.88, uwFogColor, uwFogFactor);
        finalRadiance += computeUnderwaterLightShafts(viewPos, vLightWorldDir, cosTheta);

        outColor0 = vec4(finalRadiance, 1.0);
        return;
    }

    int activeCloudMode = (CLOUD_TYPE == 0) ? (STYLE_SELECTION == 0 ? 1 : 2) : CLOUD_TYPE;

    vec3 unifiedSky = evaluateUnifiedSky(worldRayDir, viewRayDir);
    float celestialDiscMask = 0.0;

    if (depth0 >= 0.999999) {
        float moonStarOcc = smoothstep(0.9965, 0.9982, dot(worldRayDir, vMoonWorldDir));
        vec3 starAdd = sceneColor.rgb * vNightFactor * (1.0 - rainStrength) * (1.0 - moonStarOcc) * smoothstep(0.02, 0.12, worldRayDir.y);
        vec3 auroraCol = renderNightWuxiaAurora(worldRayDir, frameTimeCounter, NIGHT_AURORA);
        vec3 skyWithCelestials = unifiedSky + starAdd + auroraCol;

        celestialDiscMask = applyTexturedCelestialBodies(skyWithCelestials, worldRayDir);
        finalRadiance = skyWithCelestials;
    } else {
        vec4 mistAndBorder = computeValleyMistAndBorderFog(worldPos, playerPos, viewDist, unifiedSky);
        finalRadiance = mix(finalRadiance, mistAndBorder.rgb, mistAndBorder.a);
    }

    // Unified 3D Volumetric Clouds (Overhead to Horizon, with Solar/Lunar Disc Punch-Through!)
    if (activeCloudMode != 3) {
        float maxSceneDist = (depth0 >= 0.999999) ? 4200.0 : viewDist;
        vec4 volClouds = renderWuxiaVolumetricClouds(worldRayDir, viewRayDir, cameraPosition, frameTimeCounter, unifiedSky, celestialDiscMask, maxSceneDist, activeCloudMode);

        // When clouds overlap the sun/moon (celestialDiscMask > 0):
        // 1. Reduce cloud opacity over the celestial emblem to ~26%..32% of its normal value so the sun's
        //    Golden Crow / Gongbi calligraphy stands out vividly!
        // 2. Warm the translucent cloud wisps crossing the sun so sculpted cloud billows remain clearly visible
        //    drifting across the solar disc without washing it out into grey!
        float cloudPunchAlpha = volClouds.a * (1.0 - celestialDiscMask * 0.72);
        vec3 dayBacklitTint   = (STYLE_SELECTION == 0) ? vec3(1.02, 0.84, 0.58) : vec3(1.04, 0.88, 0.62);
        vec3 nightBacklitTint = (STYLE_SELECTION == 0) ? vec3(0.66, 0.82, 0.80) : vec3(0.62, 0.86, 1.00);
        vec3 backlitCloudTint = mix(nightBacklitTint, dayBacklitTint, vDaylightFactor);
        vec3 cloudColorOverCelestial = mix(volClouds.rgb, finalRadiance * 0.68 + volClouds.rgb * backlitCloudTint * 0.42, celestialDiscMask * 0.78);
        finalRadiance = mix(finalRadiance, cloudColorOverCelestial, cloudPunchAlpha);
    }

    vec3 shaftViewPos = viewPos;
    float shaftDepth = depth0;
    float shaftMaterial = texture(colortex1, vTexCoord).a;
    // Glass transmits light; integrate air up to the opaque surface behind it.
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
    } else if (abs(shaftMaterial - 0.90) >= 0.05 && abs(shaftMaterial - 0.12) >= 0.007) {
        float opaqueDepth = texture(depthtex1, vTexCoord).r;
        if (opaqueDepth > depth0) {
            shaftDepth = opaqueDepth;
            shaftViewPos = reconstructViewPos(vTexCoord, shaftDepth);
        }
    }
    float sceneLuma = dot(finalRadiance, vec3(0.2126, 0.7152, 0.0722));
    vec3 lightShafts = computeVolumetricLightShafts(shaftViewPos, shaftDepth, cosTheta, sceneLuma);
    finalRadiance += lightShafts;
#if LIGHT_SHAFTS > 0
    outAtmosphericShafts = vec4(lightShafts, 0.0);
#endif
#if SUN_LENS_FLARE > 0
    finalRadiance += renderSunLensFlare(vTexCoord);
#endif

    outColor0 = vec4(finalRadiance, 1.0);
}
