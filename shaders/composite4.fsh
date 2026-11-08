#version 330 compatibility
#include "/lib/camera_motion.glsl"
#include "/lib/atmospheric_filter.glsl"
/* RENDERTARGETS: 4 */
/*
const int colortex4Format = RGBA16F;
*/
layout(location = 0) out vec4 outColor;
void main() {
    ivec2 p = clamp(ivec2(gl_FragCoord.xy), ivec2(0), textureSize(colortex0, 0) - 1);
    outColor = vec4(filteredAtmosphericScene(p), 1.0);
}
