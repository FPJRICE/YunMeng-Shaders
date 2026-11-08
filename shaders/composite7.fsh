#version 330 compatibility
#include "/lib/camera_options.glsl"
#include "/lib/presentation.glsl"
noperspective in vec2 vTexCoord;
/* RENDERTARGETS: 3 */
#if ANTI_ALIASING > 0
/*
const int colortex3Format = RGBA16F;
*/
#endif
layout(location = 0) out vec4 outColor;
void main() {
    // AA sees the tone-mapped image and outlines, without paper noise.
    outColor = vec4(preparePresentation(vTexCoord, false), 1.0);
}
