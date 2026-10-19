#include "/lib/temporal_jitter.glsl"
#if ANTI_ALIASING == 3
uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
#endif
void applyCameraJitter(inout vec4 clipPosition) {
#if ANTI_ALIASING == 3
    clipPosition.xy += cameraJitter(frameCounter, vec2(viewWidth, viewHeight)) * (2.0 * clipPosition.w);
#endif
}
