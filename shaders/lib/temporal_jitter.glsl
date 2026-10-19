#ifndef YUNMENG_TEMPORAL_JITTER
#define YUNMENG_TEMPORAL_JITTER
#include "/lib/camera_options.glsl"
vec2 cameraJitter(int frame, vec2 size) {
#if ANTI_ALIASING == 3
    const vec2 offsets[8] = vec2[8](
        vec2(0.0, -0.16666667), vec2(-0.25, 0.16666667),
        vec2(0.25, -0.38888889), vec2(-0.375, -0.05555556),
        vec2(0.125, 0.27777778), vec2(-0.125, -0.27777778),
        vec2(0.375, 0.05555556), vec2(-0.4375, 0.38888889)
    );
    return offsets[frame % 8] / max(size, vec2(1.0));
#else
    return vec2(0.0);
#endif
}
#endif
