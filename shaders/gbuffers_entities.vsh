#version 330 compatibility
#include "/lib/camera_vertex.glsl"
out vec2 vTexCoord;
out vec2 vLmCoord;
out vec3 vViewNormal;
out vec4 vVertexColor;

void main() {
    gl_Position = ftransform();
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLmCoord  = clamp((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy, 0.0, 1.0);
    vViewNormal = normalize(gl_NormalMatrix * gl_Normal);
    vVertexColor = gl_Color;
    applyCameraJitter(gl_Position);
}
