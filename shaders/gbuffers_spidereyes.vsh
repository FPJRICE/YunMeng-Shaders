#version 330 compatibility
#include "/lib/camera_vertex.glsl"
out vec2 vTexCoord;
out vec4 vVertexColor;
out vec3 vViewNormal;

void main() {
    gl_Position = ftransform();
    // Slight negative depth bias prevents coplanar custom resource-pack eye quads from Z-fighting with the head mesh
    gl_Position.z -= 0.00005 * gl_Position.w;
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vVertexColor = gl_Color;
    vViewNormal = normalize(gl_NormalMatrix * gl_Normal);
    applyCameraJitter(gl_Position);
}
