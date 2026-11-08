#ifndef YUNMENG_WATER_ENVIRONMENT
#define YUNMENG_WATER_ENVIRONMENT
uniform sampler2D colortex9;

vec4 reconstructWaterEnvironment(vec2 uv, float viewDist) {
    ivec2 size = textureSize(colortex9, 0);
    vec2 pixel = uv * vec2(size) - 0.5;
    ivec2 base = ivec2(floor(pixel));
    vec2 fraction = fract(pixel);
    vec3 sum = vec3(0.0);
    float weightSum = 0.0;
    for (int y=0; y<2; ++y) for (int x=0; x<2; ++x) {
        ivec2 q = clamp(base + ivec2(x,y), ivec2(0), size-1);
        vec4 environment = texelFetch(colortex9, q, 0);
        if (environment.a <= 0.0) continue;
        vec2 bilinear = mix(vec2(1.0)-fraction, fraction, vec2(x,y));
        float weight = bilinear.x * bilinear.y;
        sum += environment.rgb * weight;
        weightSum += weight;
    }
    return vec4(sum / max(weightSum,1e-8), smoothstep(0.0,0.02,weightSum));
}

vec4 sampleSurfaceWaterEnvironmentAt(vec2 sampleUV, vec3 player, float viewLen, float horizontal, ivec2 size) {
    vec2 pixel = clamp(sampleUV, vec2(0.001), vec2(0.999)) * vec2(size) - 0.5;
    vec2 fraction = fract(pixel);
    ivec2 base = ivec2(floor(pixel));
    vec3 sum = vec3(0.0);
    float weightSum = 0.0;
    for (int y = 0; y < 2; ++y) for (int x = 0; x < 2; ++x) {
        vec4 e = texelFetch(colortex9, clamp(base + ivec2(x, y), ivec2(0), size - 1), 0);
        float support = 0.0;
        if (e.a < 0.0 && player.y < 0.0)
            support = (1.0 - smoothstep(0.14, 0.42, abs(e.a - player.y))) * max(horizontal, 0.35);
        else if (e.a > 0.0)
            support = exp(-abs(e.a - viewLen) / max(0.75, viewLen * 0.06));
        vec2 bilinear = mix(vec2(1.0) - fraction, fraction, vec2(x, y));
        float weight = bilinear.x * bilinear.y * support;
        sum += e.rgb * weight;
        weightSum += weight;
    }
    return vec4(sum / max(weightSum, 1e-8), weightSum);
}

// Horizontal reflection samples encode negative camera-relative water height.
// Perturb the half-resolution environment lookup coherently with the full-resolution
// wave normal deflection while falling back to the unperturbed UV at shore boundaries.
vec4 reconstructSurfaceWaterEnvironment(vec2 uv, vec3 viewPos, vec3 viewNormal,bool slopedTop) {
    vec3 player = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    float horizontal = slopedTop ? 0.0 : smoothstep(0.50, 0.85, dot(viewNormal, vUpViewDir));
    float viewLen = length(viewPos);
    ivec2 size = textureSize(colortex9, 0);

    vec3 tangentTilt = viewNormal - vUpViewDir * dot(viewNormal, vUpViewDir);
    vec2 rippleOffset = clamp(tangentTilt.xy * 0.14 * horizontal, vec2(-0.018), vec2(0.018));

    vec4 perturbed = sampleSurfaceWaterEnvironmentAt(uv + rippleOffset, player, viewLen, horizontal, size);
    // Full perturbed support already makes the fallback's blend weight zero.
    // Skip its four reads without changing the result or quality setting.
    if (perturbed.a>=0.18) return vec4(perturbed.rgb,1.0);
    vec4 center    = sampleSurfaceWaterEnvironmentAt(uv, player, viewLen, horizontal, size);

    float perturbedValid = smoothstep(0.02, 0.18, perturbed.a);
    vec3 rgb = mix(center.rgb, perturbed.rgb, perturbedValid);
    float totalConf = max(perturbed.a, center.a);
    return vec4(rgb, smoothstep(0.0, 0.02, totalConf));
}
#endif
