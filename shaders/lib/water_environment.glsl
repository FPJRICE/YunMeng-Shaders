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
        float weight = bilinear.x * bilinear.y
            * exp(-abs(environment.a-viewDist) / max(0.5,viewDist*0.04));
        sum += environment.rgb * weight;
        weightSum += weight;
    }
    // Confidence fades before tiny depth support disappears. Do not switch
    // abruptly between clouds and an unrelated analytic sky at a contour.
    return vec4(sum / max(weightSum,1e-8), smoothstep(0.0,0.02,weightSum));
}
#endif
