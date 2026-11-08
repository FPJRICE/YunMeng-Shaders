#version 330 compatibility
#include "/lib/camera_vertex.glsl"
/* =============================================================================
 * gbuffers_water.vsh — Watertight Distance-Attenuated Water Vertex Displacement
 * ============================================================================= */

#define STYLE_SELECTION 1      // [0 1] 0: Guofeng Ink, 1: Xianxia Mist
#define WIND_SPEED 1.00        // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]
#define WATER_WAVE_HEIGHT 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#ifndef SKY_STYLE
#define SKY_STYLE 0 // [0 1] 0:Wuxia Smooth 1:Minecraft Voxel
#endif
#ifndef WATER_STYLE
#define WATER_STYLE 0 // [0 1 2] 0:Auto (By Shader Style) 1:Wuxia Smooth 2:Minecraft Voxel
#endif

in vec4 mc_Entity;
in vec4 at_tangent;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;

out vec2 vTexCoord;
out vec2 vLmCoord;
out vec3 vViewNormal;
out vec3 vWorldNormal;
out vec3 vWorldPos;
out vec3 vPlayerPos;
out vec4 vVertexColor;
flat out int vMaterialId;
out float vVerticalCurtain;

#include "/lib/water_waves.glsl"

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLmCoord  = clamp((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy, 0.0, 1.0);
    vVertexColor = gl_Color;
    vViewNormal = normalize(gl_NormalMatrix * gl_Normal);
    vMaterialId = int(floor(mc_Entity.x + 0.5));

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vec4 playerPos = gbufferModelViewInverse * viewPos;
    vec3 undisplacedWorldPos = playerPos.xyz + cameraPosition;

    vec3 worldGeoNormal = normalize(mat3(gbufferModelViewInverse) * vViewNormal);
    vWorldNormal = worldGeoNormal;

    // 0.0 on horizontal and sloped water surfaces (abs(y) >= 0.70);
    // 1.0 on vertical waterfall side faces (abs(y) < 0.25).
    vVerticalCurtain = 1.0 - smoothstep(0.25, 0.70, abs(worldGeoNormal.y));

    bool isWater = (vMaterialId == 8200);

    if (isWater) {
        float t = frameTimeCounter * WIND_SPEED;
        vec3 wave = waterLongWaves(undisplacedWorldPos.xz, t, 0.0);
        // Calmer vertex wave displacement in Minecraft Voxel style (0.38x) vs full Wuxia Smooth (1.0x)
        float styleWaveScale = (ACTIVE_WATER_STYLE == 2) ? 0.38 : 1.0;
        playerPos.y += wave.z * WATER_WAVE_HEIGHT * styleWaveScale;
    }

    vPlayerPos = playerPos.xyz;
    vWorldPos  = undisplacedWorldPos;
    gl_Position = gbufferProjection * (gbufferModelView * playerPos);
    applyCameraJitter(gl_Position);
}
