#include "/lib/atmospheric_options.glsl"
#if LIGHT_SHAFTS > 0
uniform sampler2D colortex7;
#endif
vec3 filteredAtmosphericScene(ivec2 p) {
    vec3 scene = texelFetch(colortex0, p, 0).rgb;
#if LIGHT_SHAFTS > 0
    if (ATMOSPHERIC_SHAFT_STRENGTH <= 0.0 || isEyeInWater == 1 || handPixel(p)) return scene;
    ivec2 size = textureSize(colortex0, 0);
    float centerTag = texelFetch(colortex1, p, 0).a;
    bool centerClearGlass = abs(centerTag - 0.16) < 0.02;
    float centerDepth = texelFetch(depthtex0, p, 0).r;
    bool sky = !centerClearGlass && (centerDepth >= 0.999999);
    bool water = abs(centerTag - 0.90) < 0.05;
    float centerDistance = linearDepth(centerDepth);
    vec3 total = vec3(0.0);
    float weightSum = 0.0;
    for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
        ivec2 q = clamp(p + ivec2(x, y), ivec2(0), size - 1);
        float qTag = texelFetch(colortex1, q, 0).a;
        bool qClearGlass = abs(qTag - 0.16) < 0.02;
        float depth = texelFetch(depthtex0, q, 0).r;
        if (handPixel(q)) continue;
        if ((abs(qTag - 0.90) < 0.05) != water) continue;
        float weight = float((x == 0 ? 2 : 1) * (y == 0 ? 2 : 1));
        if (!centerClearGlass && !qClearGlass) {
            if ((depth >= 0.999999) != sky) continue;
            if (!sky) weight *= exp(-abs(linearDepth(depth) - centerDistance) / max(0.25, centerDistance * 0.06));
        }
        total += texelFetch(colortex7, q, 0).rgb * weight;
        weightSum += weight;
    }
    return max(scene - texelFetch(colortex7, p, 0).rgb + total / max(weightSum, 1e-5), vec3(0.0));
#else
    return scene;
#endif
}
