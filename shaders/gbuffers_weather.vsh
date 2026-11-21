#version 330 compatibility
#include "/lib/camera_vertex.glsl"

#define SKY_STYLE 0       // [0 1] 0: Wuxia Smooth, 1: Minecraft Voxel
#define WIND_SPEED 1.00   // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform vec3 cameraPosition;
uniform float thunderStrength;

out vec2 vTexCoord;
out vec2 vLmCoord;
out vec4 vVertexColor;
out vec3 vPlayerPos;
out vec3 vWorldPos;

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLmCoord  = clamp((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy, 0.0, 1.0);
    vVertexColor = gl_Color;

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vec4 playerPos = gbufferModelViewInverse * viewPos;

    // Gentle wind-driven diagonal shear for Wuxia Smooth silk-needle rain; minimal tilt in Voxel style
    float slantScale = (SKY_STYLE == 1)
        ? (0.018 + 0.022 * thunderStrength)
        : (0.085 + 0.075 * thunderStrength);
    float windTilt = slantScale * clamp(WIND_SPEED, 0.0, 2.0);
    playerPos.xz += vec2(0.82, 0.57) * (playerPos.y * windTilt);

    vPlayerPos = playerPos.xyz;
    vWorldPos  = playerPos.xyz + cameraPosition;

    gl_Position = gbufferProjection * (gbufferModelView * playerPos);
    applyCameraJitter(gl_Position);
}
