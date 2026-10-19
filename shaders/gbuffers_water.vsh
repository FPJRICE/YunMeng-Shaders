#version 330 compatibility
#include "/lib/camera_vertex.glsl"
/* =============================================================================
 * gbuffers_water.vsh — Watertight Distance-Attenuated Water Vertex Displacement
 * ============================================================================= */

#define STYLE_SELECTION 1      // [0 1] 0: Guofeng Ink, 1: Xianxia Mist
#define WIND_SPEED 1.00        // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]
#define WATER_WAVE_HEIGHT 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]

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

float sampleOvalWaveHeight(vec2 uv) {
    float sx = sin(uv.x * 6.28318 + cos(uv.y * 4.1));
    float cy = cos(uv.y * 6.28318 - sin(uv.x * 3.7));
    return sx * cy;
}

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

    // Strictly 0.0 on all horizontal and sloped water surfaces (abs(y) >= 0.70);
    // 1.0 only on vertical waterfall side faces (abs(y) < 0.25).
    vVerticalCurtain = 1.0 - smoothstep(0.25, 0.70, abs(worldGeoNormal.y));

    bool isWater = (vMaterialId == 8200);

    if (isWater) {
        float t = frameTimeCounter * WIND_SPEED;
        vec2 wp = undisplacedWorldPos.xz + vec2(undisplacedWorldPos.y * 0.35, -undisplacedWorldPos.y * 0.35);
        float distFade = exp(-length(playerPos.xyz) * 0.045);

        if (STYLE_SELECTION == 1) {
            mat2 rot1 = mat2( 0.92, -0.39,  0.39,  0.92);
            mat2 rot2 = mat2( 0.64,  0.77, -0.77,  0.64);
            mat2 rot3 = mat2(-0.45,  0.89, -0.89, -0.45);

            vec2 uvLarge  = rot1 * (wp * 0.05) + vec2( 0.041,  0.019) * t;
            vec2 uvMedium = rot2 * (wp * 0.13) + vec2(-0.053,  0.037) * t;
            vec2 uvSmall  = rot3 * (wp * 0.27) + vec2( 0.067, -0.049) * t;

            float hLarge  = sampleOvalWaveHeight(uvLarge)  * 0.032;
            float hMedium = sampleOvalWaveHeight(uvMedium) * 0.018;
            float hSmall  = sampleOvalWaveHeight(uvSmall)  * 0.008;

            float waveDisp = (hLarge + hMedium + hSmall) * WATER_WAVE_HEIGHT * distFade;
            playerPos.y += waveDisp;
        } else {
            float h1 = sin(wp.x * 0.13 * 6.28318 - t * 1.35) * 0.014;
            float h2 = sin((wp.x * 0.05 + wp.y * 0.03) * 6.28318 - t * 0.85) * 0.008;
            playerPos.y += (h1 + h2) * WATER_WAVE_HEIGHT * distFade;
        }
    }

    vPlayerPos = playerPos.xyz;
    vWorldPos  = undisplacedWorldPos;
    gl_Position = gbufferProjection * (gbufferModelView * playerPos);
    applyCameraJitter(gl_Position);
}
