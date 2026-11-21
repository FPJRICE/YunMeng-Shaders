#ifndef YUNMENG_AIR_FOG
#define YUNMENG_AIR_FOG
#include "/lib/fog_options.glsl"

// Universal Pale Garden detector:
// In vanilla Minecraft 1.21.4+, every standard Overworld biome computes a saturated blue skyColor (#7BA4FF),
// whereas the Pale Garden overrides skyColor to achromatic pale gray (#B9B9B9, sat ~ 0.0) and fogColor to
// smoky gray-taupe (#817770, sat ~ 0.13) with pulled-in fogEnd.
float evaluatePaleGardenWeight() {
    if (inTheEnd > 0.01 || isEyeInWater != 0) return 0.0;
    float skyPeak = max(skyColor.r, max(skyColor.g, skyColor.b));
    float skyMin  = min(skyColor.r, min(skyColor.g, skyColor.b));
    float skySat  = (skyPeak - skyMin) / max(skyPeak, 1e-4);
    float skyBlueRatio = skyColor.b / max(skyColor.r, 1e-4);

    float fogPeak = max(fogColor.r, max(fogColor.g, fogColor.b));
    float fogMin  = min(fogColor.r, min(fogColor.g, fogColor.b));
    float fogSat  = (fogPeak - fogMin) / max(fogPeak, 1e-4);
    float fogBlueRatio = fogColor.b / max(fogColor.r, 1e-4);

    // During day, sunrise, and sunset (skyPeak > 0.012), vanilla Pale Garden keeps skyColor at achromatic #B9B9B9
    // (skySat ~ 0.0, skyBlueRatio ~ 1.0) even when vanilla tints fogColor orange at sunrise/sunset!
    // Every normal Overworld biome has blue skyColor (#7BA4FF, skySat > 0.45, skyBlueRatio > 1.35).
    float achromaticSky = (1.0 - smoothstep(0.08, 0.25, skySat))
                        * (1.0 - smoothstep(1.06, 1.24, skyBlueRatio));
    // At deep midnight (skyPeak <= 0.012), skyColor approaches black, so we check that night fogColor
    // is achromatic dark gray rather than normal Overworld night blue (where fogBlueRatio > 1.35).
    float achromaticNightFog = (1.0 - smoothstep(0.18, 0.34, fogSat))
                             * (1.0 - smoothstep(1.08, 1.28, fogBlueRatio));
    float daySkyVis = smoothstep(0.004, 0.022, skyPeak);
    float rawPale = mix(achromaticNightFog, achromaticSky, daySkyVis);
    return clamp(rawPale * min(BIOME_TINT_STRENGTH, 1.25), 0.0, 1.0);
}

float airBorderFog(vec3 playerPos, float rain, float storm) {
    // Chunk visibility follows horizontal distance. Keep mid-ground terrain solid
    // out to 82% of render distance, then smoothly dissolve the outer chunk border.
    float distance = length(playerPos.xz);
    float clearEnd = min(max(far * 0.98, 64.0), far);
    float clearStart = min(max(far * 0.82, 52.0), clearEnd * 0.92);
    float weatherEnd = clearEnd * mix(0.88, 0.78, storm);
    float end = mix(clearEnd, weatherEnd, rain);
    if (fogEnd > 1.0) end = min(end, fogEnd * 0.98);
    float start = min(mix(clearStart, end * 0.70, rain), end * 0.92);
    float paleGardenW = evaluatePaleGardenWeight();
    if (paleGardenW > 0.001) {
        distance = mix(distance, length(playerPos), paleGardenW * 0.85);
        float paleEnd   = min(end, clamp(far * 0.45, 44.0, 84.0));
        float paleStart = max(paleEnd * 0.20, 8.0);
        start = mix(start, min(start, paleStart), paleGardenW);
        end   = mix(end,   paleEnd,               paleGardenW);
    }
    if (fogStart >= 0.0 && fogEnd > 1.0 && fogEnd < far * 0.78) {
        start = min(start, max(fogStart * 0.85, 4.0));
    }
    if (inTheEnd > 0.001) {
        float endDimW = clamp(inTheEnd, 0.0, 1.0);
        float endFogStart = min(max(far * 0.55, 64.0), 140.0);
        float endFogEnd   = clearEnd;
        start = mix(start, endFogStart, endDimW);
        end   = mix(end,   endFogEnd,   endDimW);
    }
    float border = smoothstep(start, end, distance);
    return border * sqrt(border);
}

// Gaussian antiderivative approximation (Abramowitz and Stegun 7.1.26).
float fogErf(float x) {
    float t = 1.0 / (1.0 + 0.3275911 * abs(x));
    float p = (((((1.061405429*t - 1.453152027)*t) + 1.421413741)*t
                - 0.284496736)*t + 0.254829592)*t;
    return sign(x) * (1.0 - p * exp(-x*x));
}

float valleyFogLength(float startY, float endY, float distance, float rain) {
    float thickness = max(SEA_OF_CLOUDS_THICKNESS * (1.0 + rain * 0.25), 1.0);
    float a = (startY - SEA_OF_CLOUDS_ALTITUDE) * 1.36014705 / thickness;
    float b = (endY - SEA_OF_CLOUDS_ALTITUDE) * 1.36014705 / thickness;
    float delta = b - a;
    float average = abs(delta) < 0.02
        ? exp(-0.25*(a+b)*(a+b))
        : 0.886226925 * (fogErf(b)-fogErf(a)) / delta;
    return distance * clamp(average, 0.0, 1.0);
}

float airPathFog(vec3 start, vec3 end, float distance, float rain, float storm) {
    float nightFactor = clamp(1.0 - vDaylightFactor, 0.0, 1.0);
    float paleGardenW = evaluatePaleGardenWeight();
    float swampW      = clamp(inSwampBiome * BIOME_TINT_STRENGTH, 0.0, 1.0);
    float vanillaPull = (inTheEnd < 0.01 && isEyeInWater == 0 && fogEnd > 1.0 && fogEnd < far * 0.78)
        ? clamp((far * 0.78 - fogEnd) / max(far * 0.55, 16.0), 0.0, 1.0) : 0.0;
    float biomeHazeW  = max(paleGardenW, vanillaPull * 0.85);

    float density = FOG_DENSITY * (1.0 + rain * 0.55 + storm * 0.40 + swampW * 0.35 + biomeHazeW * 1.45);
    // Nocturnal ground mist settles over valleys, rivers, and mid-ground trees at night;
    // Pale Garden and Swamps bring closer, thicker atmospheric haze even during the day!
    float onsetDist = mix(mix(36.0, 14.0, max(nightFactor * 0.88, swampW * 0.65)), 10.0, rain);
    onsetDist       = mix(onsetDist, 5.5, biomeHazeW);
    float delayed   = max(distance - onsetDist, 0.0);
    float avgY      = 0.5 * (start.y + end.y);
    float lowAirWeight = 1.0 - smoothstep(56.0, 175.0, avgY);
    float baseRate  = mix(0.00055, 0.0028 * (0.45 + 0.55 * lowAirWeight), nightFactor);
    baseRate        = max(baseRate + swampW * 0.0014 * lowAirWeight, biomeHazeW * 0.024);
    float fogRate   = mix(baseRate, max(baseRate, 0.0032), rain);
    float maxFogCap = mix(mix(1.0, 0.88, nightFactor), 1.00, biomeHazeW);
    float distFog   = clamp((1.0 - exp(-delayed * fogRate * density)) * maxFogCap, 0.0, maxFogCap);
    if (inTheEnd > 0.001) {
        float endDimW = clamp(inTheEnd, 0.0, 1.0);
        // Smooth atmospheric End depth fog starting gently at 12m so Obsidian Pillars and distant
        // End Stone ledges recede cohesively into the luminous End horizon mist.
        float delayedEnd = max(distance - 12.0, 0.0);
        float endPathFog = clamp((1.0 - exp(-delayedEnd * 0.0145 * FOG_DENSITY)), 0.0, 0.84);
        distFog = mix(distFog, endPathFog, endDimW);
    }
    // Integrate smoothly through the valley height layer without stamping high-contrast
    // 2D noise blotches onto mid-distance hillsides (strictly Overworld only; 0 in The End).
    float column = valleyFogLength(start.y, end.y, distance, max(rain, max(nightFactor * 0.65, max(swampW * 0.55, biomeHazeW * 0.85))));
    vec2 uv = (start.xz * 0.35 + end.xz * 0.65) * 0.00014 + vec2(frameTimeCounter * 0.0004, -frameTimeCounter * 0.00025);
    float noise = textureLod(cloudTex, fract(uv), 0.0).g;
    float strength = mix((STYLE_SELECTION == 1 || CLOUD_TYPE == 2) ? 0.22 : 0.18, 0.38, max(nightFactor, biomeHazeW * 0.85));
    float mistMod = 0.86 + 0.14 * smoothstep(0.25, 0.75, noise);
    float mistFog = clamp((1.0 - exp(-column / 92.0)) * mistMod * strength * density, 0.0, 0.68);
    mistFog *= (1.0 - clamp(inTheEnd, 0.0, 1.0));
    return 1.0 - (1.0 - distFog) * (1.0 - mistFog);
}

float airFogAmount(vec3 worldPos, vec3 playerPos, float viewDist, float rain, float storm) {
    return 1.0 - (1.0-airBorderFog(playerPos,rain,storm))
        * (1.0-airPathFog(cameraPosition,worldPos,viewDist,rain,storm));
}
#endif
