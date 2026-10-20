#version 330 compatibility
#define STYLE_SELECTION 1 // [0 1] 0: Guofeng Ink, 1: Xianxia Mist
#include "/lib/camera_motion.glsl"
#include "/lib/atmospheric_filter.glsl"
#include "/lib/temporal_resolve.glsl"
noperspective in vec2 vTexCoord;
#if MOTION_BLUR == 2
/* RENDERTARGETS: 0,6,7 */
layout(location = 2) out vec4 outMotion;
/*
const int colortex7Format = RGBA16F;
*/
#elif ANTI_ALIASING == 3
/* RENDERTARGETS: 0,6 */
#else
/* RENDERTARGETS: 0 */
#endif
#if ANTI_ALIASING == 3 || MOTION_BLUR == 2
/*
const int colortex6Format = RGBA16F;
*/
const bool colortex6Clear = false;
#endif
layout(location = 0) out vec4 outScene;
#if ANTI_ALIASING == 3 || MOTION_BLUR == 2
layout(location = 1) out vec4 outHistory;
#endif
void main() {
    ivec2 size = textureSize(colortex0, 0);
    ivec2 p = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - 1);
    vec3 current = filteredAtmosphericScene(p);
    float depth = texelFetch(depthtex0, p, 0).r;
    bool sky = depth >= 0.999999;
    bool hand = handPixel(p);
    bool entity = entityPixel(p);
#if ANTI_ALIASING == 3 || MOTION_BLUR == 2
    float previousDepth;
    vec2 previousUV = previousSampleUV(vTexCoord, depth, previousDepth);
    bool usable = temporalHistoryValid();
#endif
    float confidence = 0.0;
#if MOTION_BLUR == 2
    if (usable && entity && !hand) previousUV = trackEntityMotion(p, previousUV, previousDepth, confidence);
    bool validMotion = cameraHistoryUsable() && validHistoryUV(previousUV);
    outMotion = vec4(validMotion ? previousUV - vTexCoord : vec2(0.0), confidence, float(validMotion));
#endif
    vec3 resolved = current;
#if ANTI_ALIASING == 3
    if (usable && !hand && !entity) resolved = resolveTemporal(p, current, previousUV, previousDepth, sky);
#endif
    outScene = vec4(resolved, 1.0);
#if ANTI_ALIASING == 3 || MOTION_BLUR == 2
    float metadata = sky ? 0.0 : min(linearDepth(depth), 30000.0);
    if (entity) metadata = -metadata;
    if (hand) metadata = -65504.0;
    outHistory = vec4(resolved, metadata);
    if (all(equal(p, ivec2(0)))) {
        // Integer residues keep the history header exact in half precision.
        float marker = float(isEyeInWater + 1 + STYLE_SELECTION * 4 + ANTI_ALIASING * 16 + MOTION_BLUR * 64);
        outHistory = vec4(vec2(size % 1024), float(frameCounter % 1024), marker);
    }
#endif
}
