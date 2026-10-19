#version 330 compatibility
#include "/lib/camera_vertex.glsl"
out vec2 vTexCoord;
out vec4 vColor;
void main() {
    gl_Position = ftransform();
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
    applyCameraJitter(gl_Position);
}
