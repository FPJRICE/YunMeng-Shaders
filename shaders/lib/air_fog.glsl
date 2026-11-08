#ifndef YUNMENG_AIR_FOG
#define YUNMENG_AIR_FOG
#include "/lib/fog_options.glsl"

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
    float density = FOG_DENSITY * (1.0 + rain * 0.55 + storm * 0.40);
    // Nocturnal ground mist settles over valleys, rivers, and mid-ground trees at night
    float onsetDist = mix(mix(36.0, 14.0, nightFactor * 0.88), 10.0, rain);
    float delayed   = max(distance - onsetDist, 0.0);
    float avgY      = 0.5 * (start.y + end.y);
    float lowAirWeight = 1.0 - smoothstep(56.0, 175.0, avgY);
    float baseRate  = mix(0.00055, 0.0028 * (0.45 + 0.55 * lowAirWeight), nightFactor);
    float fogRate   = mix(baseRate, 0.0032, rain);
    float distFog   = clamp((1.0 - exp(-delayed * fogRate * density)) * mix(1.0, 0.88, nightFactor), 0.0, 0.88);
    // Integrate smoothly through the valley height layer without stamping high-contrast
    // 2D noise blotches onto mid-distance hillsides.
    float column = valleyFogLength(start.y, end.y, distance, max(rain, nightFactor * 0.65));
    vec2 uv = (start.xz * 0.35 + end.xz * 0.65) * 0.00014 + vec2(frameTimeCounter * 0.0004, -frameTimeCounter * 0.00025);
    float noise = textureLod(cloudTex, fract(uv), 0.0).g;
    float strength = mix((STYLE_SELECTION == 1 || CLOUD_TYPE == 2) ? 0.22 : 0.18, 0.38, nightFactor);
    float mistMod = 0.86 + 0.14 * smoothstep(0.25, 0.75, noise);
    float mistFog = clamp((1.0 - exp(-column / 92.0)) * mistMod * strength * density, 0.0, 0.62);
    return 1.0 - (1.0 - distFog) * (1.0 - mistFog);
}

float airFogAmount(vec3 worldPos, vec3 playerPos, float viewDist, float rain, float storm) {
    return 1.0 - (1.0-airBorderFog(playerPos,rain,storm))
        * (1.0-airPathFog(cameraPosition,worldPos,viewDist,rain,storm));
}
#endif
