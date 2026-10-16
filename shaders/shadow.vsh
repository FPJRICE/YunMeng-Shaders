#version 330 compatibility
// Build 2 performance update: scalable cloud, shadow and shoreline settings.
const float shadowDistanceRenderMul = 1.0;
const float shadowDistance = 128.0; // [64.0 96.0 128.0 160.0 224.0]
#define WIND_SPEED 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]
#define WAVING_BAMBOO
#define WAVING_SUGARCANE
#define WAVING_LEAVES
#define WAVING_GRASS

in vec4 mc_Entity;
in vec4 mc_midTexCoord;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;

out vec2 vTexCoord;
out vec4 vVertexColor;

vec3 distortShadowClipPos(vec3 shadowClipPos) {
    float dist = length(shadowClipPos.xy);
    float distortFactor = mix(1.0, dist, 0.85);
    shadowClipPos.xy /= max(distortFactor, 1e-4);
    shadowClipPos.z  *= 0.2;
    return shadowClipPos;
}

vec3 evaluateShadowWind(vec3 worldPos, float time, float skyExposure) {
    float gustTime = time * WIND_SPEED;
    vec2 windDir = normalize(vec2(0.82, 0.57));
    float phase = dot(worldPos.xz, windDir) * 0.35 - gustTime * 2.4;
    float wave = sin(phase) * 0.65 + sin(phase * 0.45 + worldPos.y * 0.18) * 0.35;
    return vec3(windDir.x * wave, 0.0, windDir.y * wave) * skyExposure;
}

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec2 lmCoord = clamp((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy, 0.0, 1.0);
    vVertexColor = gl_Color;

    int matId = int(floor(mc_Entity.x + 0.5));
    vec4 clipPos = ftransform();
    vec4 playerPos = shadowModelViewInverse * (shadowProjectionInverse * clipPos);
    vec3 worldPos = playerPos.xyz + cameraPosition;

    float skyExposure = smoothstep(0.15, 0.65, lmCoord.y);
    vec2 midCoord = (gl_TextureMatrix[0] * mc_midTexCoord).st;
    bool isTopVertex = (vTexCoord.y < midCoord.y);

    #ifdef WAVING_BAMBOO
    if (matId == 8106) {
        vec3 w = evaluateShadowWind(worldPos, frameTimeCounter, skyExposure);
        playerPos.xz += w.xz * 0.095;
    }
    #endif
    #ifdef WAVING_LEAVES
    if (matId == 8102 || matId == 8103) {
        vec3 w = evaluateShadowWind(worldPos * 0.85, frameTimeCounter, skyExposure);
        playerPos.xyz += w * 0.065;
    }
    #endif
    #ifdef WAVING_GRASS
    if (matId == 8101 && isTopVertex) {
        vec3 w = evaluateShadowWind(worldPos, frameTimeCounter * 1.25, skyExposure);
        playerPos.xz += w.xz * 0.12;
    } else if (matId == 8105) {
        vec3 w = evaluateShadowWind(worldPos, frameTimeCounter * 1.25, skyExposure);
        playerPos.xz += w.xz * (isTopVertex ? 0.22 : 0.12);
    }
    #endif

    #ifdef WAVING_SUGARCANE
    if (matId == 8104 && isTopVertex) {
        vec3 w = evaluateShadowWind(worldPos, frameTimeCounter * 1.25, skyExposure);
        playerPos.xz += w.xz * 0.12;
    }
    #endif

    gl_Position = shadowProjection * (shadowModelView * playerPos);
    gl_Position.xyz = distortShadowClipPos(gl_Position.xyz);
}
