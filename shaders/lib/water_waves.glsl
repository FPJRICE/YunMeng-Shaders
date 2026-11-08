#ifndef YUNMENG_WATER_WAVES
#define YUNMENG_WATER_WAVES

#ifndef SKY_STYLE
#define SKY_STYLE 0                   // [0 1] 0: Wuxia Smooth, 1: Minecraft Voxel
#endif
#ifndef WATER_STYLE
#define WATER_STYLE 0                 // [0 1 2] 0: Auto (By Shader Style), 1: Wuxia Smooth, 2: Minecraft Voxel
#endif
#define ACTIVE_WATER_STYLE ((WATER_STYLE == 0) ? ((SKY_STYLE == 1) ? 2 : 1) : WATER_STYLE)

// World-space directional and cross-warped trochoidal waves (NVIDIA GPU Gems Ch. 1).
// XY is the exact analytical height derivative in XZ; Z is height.
// Long waves drive both vertex geometry and macro surface slopes; multi-scale
// medium and capillary waves add scale-balanced facet detail to fragment normals.

vec3 waterWaveComponent(vec2 p, float t, vec2 direction, float wavelength,
                        float amplitude, float phaseOffset, float footprint) {
    float k = 6.28318530718 / wavelength;
    float phase = dot(p, direction) * k - t * sqrt(9.81 * k) * 0.28 + phaseOffset;
    float visibility = 1.0 - smoothstep(0.25, 0.65, footprint / wavelength);
    float h = sin(phase);
    float slope = cos(phase);
    return vec3(direction * (amplitude * k * slope), amplitude * h) * visibility;
}

// Cross-warped trochoidal wave component with exact chain-rule analytical derivatives.
// Dual non-collinear phase modulations break straight wave fronts into interlocking
// organic facets while the second-harmonic crest term sharpens crests and broadens troughs.
vec3 waterFacetComponent(vec2 p, float t, vec2 direction, float wavelength,
                         float amplitude, float phaseOffset, float bendScale,
                         float steepness, float footprint) {
    float visibility = 1.0 - smoothstep(0.22, 0.58, footprint / wavelength);
    if (visibility <= 0.0001) return vec3(0.0);

    float k = 6.28318530718 / wavelength;
    float omega = sqrt(9.81 * k) * 0.18;
    vec2 ortho = vec2(-direction.y, direction.x);

    vec2 m1 = ortho * (k * 0.37) + direction * (k * 0.19);
    vec2 m2 = ortho * (k * 0.23) - direction * (k * 0.29);
    float u1 = dot(p, m1) - t * omega * 0.41 + phaseOffset * 0.7;
    float u2 = dot(p, m2) + t * omega * 0.33 - phaseOffset * 1.1;

    float warp = bendScale * (0.65 * sin(u1) + 0.35 * cos(u2));
    vec2 warpGrad = bendScale * (0.65 * cos(u1) * m1 - 0.35 * sin(u2) * m2);

    float phase = dot(p, direction) * k - t * omega + phaseOffset + warp;
    vec2 phaseGrad = direction * k + warpGrad;

    float s1 = sin(phase);
    float c1 = cos(phase);
    float s2 = sin(2.0 * phase);
    float c2 = cos(2.0 * phase);

    float h = (s1 - steepness * c2) * amplitude * visibility;
    float dHdPhase = (c1 + 2.0 * steepness * s2) * amplitude * visibility;
    return vec3(phaseGrad * dHdPhase, h);
}

vec3 waterLongWaves(vec2 p, float t, float footprint) {
    float scale = STYLE_SELECTION == 0 ? 0.68 : 1.0;
    // Slowly bend the wave coordinates. Transform the analytic derivatives
    // through the same Jacobian so reflections follow the displaced surface.
    vec2 a = vec2(0.13, 0.17), b = vec2(-0.19, 0.09);
    float u = dot(p, a) - t * 0.11, v = dot(p, b) + t * 0.09;
    vec2 q = p + vec2(sin(u), sin(v)) * 1.8;
    vec3 wave = scale * (
        waterWaveComponent(q, t, vec2( 0.939693, 0.342020), 15.7, 0.022, 0.4, footprint) +
        waterWaveComponent(q, t, vec2(-0.422618, 0.906308),  9.6, 0.010, 2.1, footprint) +
        waterWaveComponent(q, t, vec2( 0.173648, 0.984808),  6.7, 0.005, 4.7, footprint));
    vec2 slope = wave.xy;
    wave.xy += 1.8 * (slope.x * cos(u) * a + slope.y * cos(v) * b);
    return wave;
}

vec3 waterShimmerDetailWaves(vec2 p, float t, float footprint) {
    return
        waterFacetComponent(p, t, vec2( 0.829038,  0.559193), 3.70, 0.0050, 1.3, 0.82, 0.16, footprint) +
        waterFacetComponent(p, t, vec2(-0.681998,  0.731354), 2.55, 0.0037, 2.8, 0.88, 0.16, footprint) +
        waterFacetComponent(p, t, vec2( 0.309017, -0.951057), 1.78, 0.0027, 4.1, 0.92, 0.15, footprint) +
        waterFacetComponent(p, t, vec2(-0.951057, -0.309017), 1.24, 0.0019, 0.9, 0.95, 0.14, footprint) +
        waterFacetComponent(p, t, vec2( 0.587785, -0.809017), 0.86, 0.0013, 3.5, 0.96, 0.13, footprint) +
        waterFacetComponent(p, t, vec2(-0.207912, -0.978148), 0.58, 0.00085, 5.2, 0.96, 0.11, footprint);
}

vec3 waterSurfaceWaves(vec2 p, float t, float footprint) {
    // Smooth, continuous 3D wave ripples in both styles, with calmer amplitude (0.45x) and gentler pace (0.75x)
    // in Minecraft Voxel style so the shimmer and real Minecraft water surface texture blend naturally.
    float styleScale  = (ACTIVE_WATER_STYLE == 2) ? 0.45 : 1.0;
    float styleTime   = (ACTIVE_WATER_STYLE == 2) ? (t * 0.75) : t;
    float detailScale = (STYLE_SELECTION == 0 ? 0.78 : 1.0) * styleScale;
    vec3 detail = waterShimmerDetailWaves(p, styleTime, footprint);
    return waterLongWaves(p, styleTime, footprint) * styleScale + detailScale * detail;
}

#endif
