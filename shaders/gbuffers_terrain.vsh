#version 330 compatibility
/* =============================================================================
 * gbuffers_terrain.vsh — Wuxia Foliage & Bamboo Wind Pass (Iris 1.26.3)
 * ============================================================================= */

#define STYLE_SELECTION 1  // [0 1] 0: Guofeng Ink, 1: Xianxia Mist
#define WIND_SPEED 1.00    // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]
#define WAVING_BAMBOO
#define WAVING_SUGARCANE
#define WAVING_LEAVES
#define WAVING_GRASS

in vec4 mc_Entity;
in vec4 mc_midTexCoord;
in vec4 at_tangent;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float wetness;

out vec2 vTexCoord;
out vec2 vLmCoord;
out vec3 vViewNormal;
out vec3 vWorldPos;
out vec4 vVertexColor;
flat out int vMaterialId;
out float vWindFlex;

bool isBambooBlock(int id) {
    return (id == 8106);
}

bool isSugarCaneBlock(int id) {
    return (id == 8104);
}

bool isLeavesBlock(int id) {
    return (id == 8102 || id == 8103);
}

bool isLowerGrassOrFoliage(int id) {
    return (id == 8101);
}

bool isUpperTallGrass(int id) {
    return (id == 8105);
}

vec3 evaluateMountainWind(vec3 worldPos, float time, float skyExposure, float stormBoost) {
    float gustTime = time * WIND_SPEED;
    vec2 windDir = normalize(vec2(0.82, 0.57));
    float projectedPhase = dot(worldPos.xz, windDir) * 0.35 - gustTime * 2.4;

    float ridgeWave = sin(projectedPhase) * 0.65 + sin(projectedPhase * 0.45 + worldPos.y * 0.18) * 0.35;
    float crossGust = cos(dot(worldPos.xz, vec2(-windDir.y, windDir.x)) * 0.55 - gustTime * 1.7);

    float swellEnvelope = 0.55 + 0.45 * sin(gustTime * 0.65 + worldPos.x * 0.08 + worldPos.z * 0.08);
    float amplitude = swellEnvelope * mix(1.0, 1.65, stormBoost) * skyExposure;

    return vec3(
        (windDir.x * ridgeWave + 0.25 * crossGust) * amplitude,
        -abs(ridgeWave) * 0.08 * amplitude,
        (windDir.y * ridgeWave - 0.25 * crossGust) * amplitude
    );
}

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLmCoord  = clamp((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy, 0.0, 1.0);

    vVertexColor = gl_Color;
    if (vVertexColor.a < 0.05) {
        vVertexColor.a = 1.0;
    }

    vViewNormal = normalize(gl_NormalMatrix * gl_Normal);
    vMaterialId = int(floor(mc_Entity.x + 0.5));

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vec4 playerPos = gbufferModelViewInverse * viewPos;
    vec3 worldPos = playerPos.xyz + cameraPosition;

    float skyExposure = smoothstep(0.15, 0.65, vLmCoord.y);
    float stormBoost  = clamp(rainStrength + wetness * 0.5, 0.0, 1.0);
    float profileWindScale = (STYLE_SELECTION == 1) ? 1.15 : 0.90;

    vec2 midCoord = (gl_TextureMatrix[0] * mc_midTexCoord).st;
    bool isTopVertex = (vTexCoord.y < midCoord.y);
    float blockFractY = fract(worldPos.y + 0.001);

    vec3 windOffset = vec3(0.0);
    vWindFlex = 0.0;

    #ifdef WAVING_BAMBOO
    if (isBambooBlock(vMaterialId)) {
        float culmHeightPhase = worldPos.y * 0.28;
        vec3 mountainWind = evaluateMountainWind(worldPos + vec3(0.0, culmHeightPhase, 0.0), frameTimeCounter, skyExposure, stormBoost);
        float nodeVib = sin(frameTimeCounter * 6.5 * WIND_SPEED + worldPos.x * 3.1 + worldPos.z * 2.7 + worldPos.y * 1.4) * 0.025;
        float stalkFlex = 0.095 * profileWindScale;

        windOffset.xz = mountainWind.xz * stalkFlex + vec2(nodeVib, -nodeVib * 0.7) * skyExposure;
        windOffset.y  = -length(windOffset.xz) * 0.18;
        vWindFlex = clamp(length(windOffset.xz) * 6.0, 0.0, 1.0);
    }
    #endif

    #ifdef WAVING_SUGARCANE
    if (isSugarCaneBlock(vMaterialId)) {
        float segmentFactor = isTopVertex ? 1.0 : 0.45;
        vec3 mountainWind = evaluateMountainWind(worldPos, frameTimeCounter * 1.15, skyExposure, stormBoost);
        float reedFlutter = sin(frameTimeCounter * 4.8 * WIND_SPEED + dot(worldPos.xz, vec2(2.3, 1.9)) + worldPos.y * 1.8) * 0.03;

        windOffset.xz = (mountainWind.xz * 0.085 + vec2(reedFlutter)) * segmentFactor * profileWindScale;
        vWindFlex = clamp(length(windOffset.xz) * 7.0, 0.0, 1.0);
    }
    #endif

    #ifdef WAVING_LEAVES
    if (isLeavesBlock(vMaterialId)) {
        vec3 mountainWind = evaluateMountainWind(worldPos * 0.85, frameTimeCounter, skyExposure, stormBoost);
        float rustleTime = frameTimeCounter * 5.2 * WIND_SPEED;
        vec3 leafFlutter = vec3(
            sin(rustleTime + worldPos.x * 2.9 + worldPos.y * 1.7),
            cos(rustleTime * 0.85 + worldPos.y * 2.5 + worldPos.z * 2.1) * 0.6,
            sin(rustleTime * 1.15 + worldPos.z * 3.1 - worldPos.x * 1.9)
        ) * 0.028 * skyExposure;

        windOffset = (mountainWind * 0.065 + leafFlutter) * profileWindScale;
        vWindFlex = clamp(length(windOffset) * 8.0, 0.0, 1.0);
    }
    #endif

    #ifdef WAVING_GRASS
    if (isLowerGrassOrFoliage(vMaterialId)) {
        float anchorWeight = (isTopVertex || blockFractY > 0.25) ? 1.0 : 0.0;
        vec3 mountainWind = evaluateMountainWind(worldPos, frameTimeCounter * 1.25, skyExposure, stormBoost);

        windOffset.xz = mountainWind.xz * 0.135 * anchorWeight * profileWindScale;
        windOffset.y  = mountainWind.y * 0.06 * anchorWeight;
        vWindFlex = anchorWeight * clamp(length(windOffset.xz) * 5.0, 0.0, 1.0);
    } else if (isUpperTallGrass(vMaterialId)) {
        float heightWeight = isTopVertex ? 1.85 : 1.0;
        vec3 mountainWind = evaluateMountainWind(worldPos - vec3(0.0, 0.5, 0.0), frameTimeCounter * 1.25, skyExposure, stormBoost);

        windOffset.xz = mountainWind.xz * 0.135 * heightWeight * profileWindScale;
        windOffset.y  = -length(windOffset.xz) * 0.15;
        vWindFlex = clamp(length(windOffset.xz) * 4.5, 0.0, 1.0);
    }
    #endif

    playerPos.xyz += windOffset;
    vWorldPos = playerPos.xyz + cameraPosition;

    gl_Position = gbufferProjection * (gbufferModelView * playerPos);
}
