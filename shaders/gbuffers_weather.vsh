#version 330 compatibility
#include "/lib/camera_vertex.glsl"

uniform mat4 gbufferModelViewInverse;

out vec2 vTexCoord;
out vec2 vLmCoord;
out vec4 vVertexColor;
out vec3 vPlayerPos;

void main() {
    gl_Position = ftransform();
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLmCoord  = clamp((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy, 0.0, 1.0);
    vVertexColor = gl_Color;

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vPlayerPos = (gbufferModelViewInverse * viewPos).xyz;

    applyCameraJitter(gl_Position);
}
