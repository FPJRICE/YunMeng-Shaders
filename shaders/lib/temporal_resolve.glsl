uniform sampler2D colortex6;
uniform sampler2D depthtex1;
bool temporalHistoryValid() {
    if (!cameraHistoryUsable()) return false;
    ivec2 size = textureSize(colortex0, 0);
    if (any(notEqual(textureSize(colortex6, 0), size))) return false;
    vec4 header = texelFetch(colortex6, ivec2(0), 0);
    float marker = float(isEyeInWater + 1 + STYLE_SELECTION * 4 + ANTI_ALIASING * 16 + MOTION_BLUR * 64);
    return all(equal(header.xy, vec2(size % 1024))) && header.z == float((frameCounter + 1023) % 1024) && header.w == marker;
}
bool validHistoryUV(vec2 uv) {
    vec2 margin = vec2(2.0) / vec2(textureSize(colortex0, 0));
    return all(greaterThanEqual(uv, margin)) && all(lessThanEqual(uv, vec2(1.0) - margin));
}
vec3 trackingColor(vec3 color) { return color / (1.0 + max(max(color.r, color.g), color.b)); }
#if MOTION_BLUR == 2
float entityMatchCost(ivec2 center, vec2 candidate, float previousDepth) {
    if (!validHistoryUV(candidate)) return 1e4;
    ivec2 size = textureSize(colortex0, 0);
    ivec2 previousCenter = ivec2(candidate * vec2(size));
    float previousTagDepth = texelFetch(colortex6, previousCenter, 0).a;
    if (previousTagDepth >= 0.0 || previousTagDepth < -32000.0) return 1e4;
    if (abs(-previousTagDepth - previousDepth) > max(0.25, previousDepth * 0.12)) return 1e4;
    const ivec2 offsets[5] = ivec2[5](ivec2(0), ivec2(2,0), ivec2(-2,0), ivec2(0,2), ivec2(0,-2));
    float cost = 0.0;
    float count = 0.0;
    for (int i = 0; i < 5; i++) {
        ivec2 a = clamp(center + offsets[i], ivec2(0), size - 1);
        ivec2 b = clamp(previousCenter + offsets[i], ivec2(0), size - 1);
        if (!entityPixel(a)) continue;
        float oldDepth = texelFetch(colortex6, b, 0).a;
        if (oldDepth >= 0.0 || oldDepth < -32000.0) { cost += 0.10; count += 1.0; continue; }
        vec3 difference = trackingColor(texelFetch(colortex0, a, 0).rgb) - trackingColor(texelFetch(colortex6, b, 0).rgb);
        cost += dot(difference, difference);
        count += 1.0;
    }
    return count >= 3.0 ? cost / count : 1e4;
}
vec2 trackEntityMotion(ivec2 p, vec2 cameraUV, float previousDepth, out float confidence) {
    confidence = 0.0;
    vec2 texel = 1.0 / vec2(textureSize(colortex0, 0));
    float initialCost = entityMatchCost(p, cameraUV, previousDepth);
    float bestCost = initialCost;
    vec2 bestOffset = vec2(0.0);
    for (int y = -2; y <= 2; y++) for (int x = -2; x <= 2; x++) {
        vec2 offset = vec2(x,y) * 4.0;
        float cost = entityMatchCost(p, cameraUV + offset * texel, previousDepth) + dot(offset, offset) * 0.000002;
        if (cost < bestCost) { bestCost = cost; bestOffset = offset; }
    }
    vec2 coarseOffset = bestOffset;
    for (int y = -2; y <= 2; y++) for (int x = -2; x <= 2; x++) {
        vec2 offset = coarseOffset + vec2(x,y);
        float cost = entityMatchCost(p, cameraUV + offset * texel, previousDepth) + dot(offset, offset) * 0.000002;
        if (cost < bestCost) { bestCost = cost; bestOffset = offset; }
    }
    if (bestCost < 0.015 && bestCost < initialCost * 0.65 && initialCost > 0.0005) {
        confidence = 1.0;
        return cameraUV + bestOffset * texel;
    }
    return cameraUV;
}
#endif
vec3 toTemporalColor(vec3 c) { return vec3(dot(c, vec3(0.25,0.5,0.25)), c.r-c.b, c.g-(c.r+c.b)*0.5); }
vec3 fromTemporalColor(vec3 c) { return vec3(c.x+c.y*0.5-c.z*0.5, c.x+c.z*0.5, c.x-c.y*0.5-c.z*0.5); }
bool sampleTemporalHistory(vec2 uv, float previousDepth, bool sky, out vec3 history) {
    history = vec3(0.0);
    if (!validHistoryUV(uv)) return false;
    vec2 q = uv * vec2(textureSize(colortex6, 0)) - 0.5;
    ivec2 base = ivec2(floor(q));
    vec2 fraction = fract(q);
    float total = 0.0;
    for (int y = 0; y < 2; y++) for (int x = 0; x < 2; x++) {
        vec4 sampleValue = texelFetch(colortex6, base + ivec2(x,y), 0);
        bool depthMatches = sky ? sampleValue.a == 0.0
            : sampleValue.a > 0.0 && abs(sampleValue.a - previousDepth) <= max(0.10, previousDepth * 0.02);
        if (!depthMatches) continue;
        vec2 weights = mix(vec2(1.0) - fraction, fraction, vec2(x,y));
        float weight = weights.x * weights.y;
        history += sampleValue.rgb * weight;
        total += weight;
    }
    if (total < 0.5) return false;
    history /= total;
    return !any(isnan(history)) && !any(isinf(history));
}
vec3 resolveTemporal(ivec2 p, vec3 current, vec2 previousUV, float previousDepth, bool sky) {
    vec3 history;
    if (!sampleTemporalHistory(previousUV, previousDepth, sky, history)) return current;
    ivec2 size = textureSize(colortex0, 0);
    vec3 lo = vec3(1e20), hi = vec3(-1e20), mean = vec3(0.0), squareMean = vec3(0.0);
    for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
        vec3 sampleValue = toTemporalColor(texelFetch(colortex0, clamp(p + ivec2(x,y), ivec2(0), size - 1), 0).rgb);
        lo = min(lo, sampleValue); hi = max(hi, sampleValue);
        mean += sampleValue; squareMean += sampleValue * sampleValue;
    }
    mean /= 9.0; squareMean /= 9.0;
    vec3 deviation = sqrt(max(squareMean - mean * mean, vec3(0.0)));
    float extent = STYLE_SELECTION == 0 ? 1.25 : 1.50;
    vec3 clipped = clamp(toTemporalColor(history), max(lo, mean - deviation * extent), min(hi, mean + deviation * extent));
    history = max(fromTemporalColor(clipped), vec3(0.0));
    float material = texelFetch(colortex1, p, 0).a;
    float weight = STYLE_SELECTION == 0 ? 0.82 : 0.90;
    if (material > 0.20 && material < 0.80) weight = min(weight, 0.70);
    if (abs(material - 0.90) < 0.05) weight = min(weight, 0.40);
    // A glass surface cannot describe the motion of everything behind it.
    if (abs(material - 0.90) >= 0.05 && texelFetch(depthtex1, p, 0).r > texelFetch(depthtex0, p, 0).r + 0.000001)
        weight = min(weight, 0.20);
    if (sky) weight = min(weight, 0.55);
    float brightnessChange = abs(dot(history-current, vec3(0.2126,0.7152,0.0722)));
    weight /= 1.0 + brightnessChange;
    return mix(current, history, weight);
}
