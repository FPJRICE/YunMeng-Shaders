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
const ivec2 entityOffsets[5] = ivec2[5](ivec2(0), ivec2(2,0), ivec2(-2,0), ivec2(0,2), ivec2(0,-2));
float entityMatchCost(vec3 currentColors[5], bool currentValid[5], vec2 candidate, float previousDepth) {
    if (!validHistoryUV(candidate)) return 1e4;
    ivec2 size = textureSize(colortex0, 0);
    ivec2 previousCenter = ivec2(candidate * vec2(size));
    float previousTagDepth = texelFetch(colortex6, previousCenter, 0).a;
    if (previousTagDepth >= 0.0 || previousTagDepth < -32000.0) return 1e4;
    if (abs(-previousTagDepth - previousDepth) > max(0.25, previousDepth * 0.12)) return 1e4;
    float cost = 0.0;
    float count = 0.0;
    for (int i = 0; i < 5; i++) {
        ivec2 b = clamp(previousCenter + entityOffsets[i], ivec2(0), size - 1);
        if (!currentValid[i]) continue;
        float oldDepth = texelFetch(colortex6, b, 0).a;
        if (oldDepth >= 0.0 || oldDepth < -32000.0) { cost += 0.10; count += 1.0; continue; }
        vec3 difference = currentColors[i] - trackingColor(texelFetch(colortex6, b, 0).rgb);
        cost += dot(difference, difference);
        count += 1.0;
    }
    return count >= 3.0 ? cost / count : 1e4;
}

vec2 trackEntityMotion(ivec2 p, vec2 cameraUV, float previousDepth, out float confidence) {
    confidence = 0.0;
    ivec2 size = textureSize(colortex0, 0);
    vec2 texel = 1.0 / vec2(size);
    // The current patch is invariant across all history candidates.
    vec3 currentColors[5];
    bool currentValid[5];
    for (int i = 0; i < 5; i++) {
        ivec2 a = clamp(p + entityOffsets[i], ivec2(0), size - 1);
        currentValid[i] = entityPixel(a);
        currentColors[i] = currentValid[i] ? trackingColor(texelFetch(colortex0, a, 0).rgb) : vec3(0.0);
    }
    float initialCost = entityMatchCost(currentColors, currentValid, cameraUV, previousDepth);
    // The acceptance test below cannot select tracked motion at this cost.
    if (initialCost <= 0.0005) return cameraUV;
    float bestCost = initialCost;
    vec2 bestOffset = vec2(0.0);
    for (int y = -2; y <= 2; y++) for (int x = -2; x <= 2; x++) {
        vec2 offset = vec2(x,y) * 4.0;
        float cost = entityMatchCost(currentColors, currentValid, cameraUV + offset * texel, previousDepth) + dot(offset, offset) * 0.000002;
        if (cost < bestCost) { bestCost = cost; bestOffset = offset; }
    }
    vec2 coarseOffset = bestOffset;
    for (int y = -2; y <= 2; y++) for (int x = -2; x <= 2; x++) {
        vec2 offset = coarseOffset + vec2(x,y);
        float cost = entityMatchCost(currentColors, currentValid, cameraUV + offset * texel, previousDepth) + dot(offset, offset) * 0.000002;
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
    ivec2 size = textureSize(colortex6, 0);
    vec2 texSize = vec2(size);
    vec2 q = uv * texSize - 0.5;
    ivec2 base = ivec2(floor(q));
    vec2 f = fract(q);

    float total = 0.0;
    int validCount = 0;
    for (int y = 0; y < 2; y++) for (int x = 0; x < 2; x++) {
        vec4 sampleValue = texelFetch(colortex6, clamp(base + ivec2(x, y), ivec2(0), size - 1), 0);
        bool depthMatches = sky ? (sampleValue.a == 0.0)
            : (sampleValue.a > 0.0 && abs(sampleValue.a - previousDepth) <= max(0.12, previousDepth * 0.025));
        if (!depthMatches) continue;
        vec2 weights = mix(vec2(1.0) - f, f, vec2(x, y));
        float weight = weights.x * weights.y;
        history += sampleValue.rgb * weight;
        total += weight;
        validCount++;
    }
    if (total < 0.45) return false;
    history /= total;

    // When all 4 footprint texels lie on the same continuous surface, upgrade to a 5-tap
    // Catmull-Rom bicubic sharpening kernel so TAA preserves crisp block & foliage detail.
    if (validCount == 4) {
        vec2 f2 = f * f;
        vec2 f3 = f2 * f;
        vec2 w0 = f2 - 0.5 * (f3 + f);
        vec2 w1 = 1.5 * f3 - 2.5 * f2 + vec2(1.0);
        vec2 w2 = -1.5 * f3 + 2.0 * f2 + 0.5 * f;
        vec2 w3 = 0.5 * (f3 - f2);

        vec2 w12 = w1 + w2;
        vec2 tc0 = (vec2(base) - 0.5) / texSize;
        vec2 tc12 = (vec2(base) + 0.5 + w2 / max(w12, vec2(1e-5))) / texSize;
        vec2 tc3 = (vec2(base) + 2.5) / texSize;

        vec3 bicubic =
            textureLod(colortex6, vec2(tc12.x, tc0.y),  0.0).rgb * (w12.x * w0.y) +
            textureLod(colortex6, vec2(tc0.x,  tc12.y), 0.0).rgb * (w0.x  * w12.y) +
            textureLod(colortex6, vec2(tc12.x, tc12.y), 0.0).rgb * (w12.x * w12.y) +
            textureLod(colortex6, vec2(tc3.x,  tc12.y), 0.0).rgb * (w3.x  * w12.y) +
            textureLod(colortex6, vec2(tc12.x, tc3.y),  0.0).rgb * (w12.x * w3.y);
        float weightSum = (w12.x * w0.y) + (w0.x * w12.y) + (w12.x * w12.y) + (w3.x * w12.y) + (w12.x * w3.y);
        bicubic = max(bicubic / max(weightSum, 1e-5), vec3(0.0));
        if (!any(isnan(bicubic)) && !any(isinf(bicubic))) {
            history = mix(history, bicubic, 0.75);
        }
    }

    return !any(isnan(history)) && !any(isinf(history));
}

vec3 resolveTemporal(ivec2 p, vec3 current, vec2 previousUV, float previousDepth, bool sky) {
    vec3 history;
    if (!sampleTemporalHistory(previousUV, previousDepth, sky, history)) return current;
    ivec2 size = textureSize(colortex0, 0);

    // Evaluate both 3x3 box and 5-tap cross neighborhoods in YCoCg space, then blend them
    // into a rounded AABB to eliminate diagonal corner ghosting while preventing shimmer.
    vec3 boxLo = vec3(1e20), boxHi = vec3(-1e20);
    vec3 crossLo = vec3(1e20), crossHi = vec3(-1e20);
    vec3 mean = vec3(0.0), squareMean = vec3(0.0);

    for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
        vec3 neighbor = (x == 0 && y == 0) ? current
            : temporalScene(clamp(p + ivec2(x, y), ivec2(0), size - 1));
        vec3 sampleValue = toTemporalColor(neighbor);
        boxLo = min(boxLo, sampleValue);
        boxHi = max(boxHi, sampleValue);
        if (abs(x) + abs(y) <= 1) {
            crossLo = min(crossLo, sampleValue);
            crossHi = max(crossHi, sampleValue);
        }
        mean += sampleValue;
        squareMean += sampleValue * sampleValue;
    }
    mean /= 9.0;
    squareMean /= 9.0;
    vec3 deviation = sqrt(max(squareMean - mean * mean, vec3(0.0)));

    vec3 roundedLo = mix(boxLo, crossLo, 0.5);
    vec3 roundedHi = mix(boxHi, crossHi, 0.5);

    float extent = STYLE_SELECTION == 0 ? 1.15 : 1.35;
    vec3 clipMin = max(roundedLo, mean - deviation * extent);
    vec3 clipMax = min(roundedHi, mean + deviation * extent);
    vec3 clipped = clamp(toTemporalColor(history), clipMin, clipMax);
    history = max(fromTemporalColor(clipped), vec3(0.0));

    float material = texelFetch(colortex1, p, 0).a;
    float weight = STYLE_SELECTION == 0 ? 0.85 : 0.91;
    // Portal content moves at virtual depths, unlike its physical surface.
    if (abs(material - 0.98) < 0.006) weight = min(weight, 0.16);
    if (material > 0.20 && material < 0.80) weight = min(weight, 0.76);
    if (abs(material - 0.90) < 0.05) weight = min(weight, 0.52);
    if (abs(material - 0.90) >= 0.05 && texelFetch(depthtex1, p, 0).r > texelFetch(depthtex0, p, 0).r + 0.000001)
        weight = min(weight, 0.25);
    if (sky) weight = min(weight, 0.65);

    // Reduce history weight slightly when camera motion velocity is large to prevent motion smearing
    vec2 pixelVelocity = (previousUV - (vec2(p) + 0.5) / vec2(size)) * vec2(size);
    float motionFactor = clamp(length(pixelVelocity) * 0.08, 0.0, 0.35);
    weight *= (1.0 - motionFactor);

    float brightnessChange = abs(dot(history - current, vec3(0.2126, 0.7152, 0.0722)));
    weight /= 1.0 + brightnessChange * (1.0 + smoothstep(0.06, 0.24, brightnessChange) * 14.0);
    return mix(current, history, weight);
}
