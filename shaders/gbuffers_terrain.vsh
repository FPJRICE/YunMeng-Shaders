#version 330 compatibility
#include "/lib/camera_vertex.glsl"
/* =============================================================================
 * gbuffers_terrain.vsh — YunMeng foliage and bamboo wind pass
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
uniform float frameTime;
uniform float rainStrength;
uniform float wetness;

out vec2 vTexCoord;
out vec2 vLmCoord;
out vec3 vViewNormal;
out vec3 vWorldPos;
out vec4 vVertexColor;
flat out int vMaterialId;
out float vWindFlex;
#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
out vec3 vMotionDelta;
#endif

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

bool isHangingStrand(int id) {
    return (id == 8107);
}

bool isWallVine(int id) {
    return (id == 8108);
}

bool isUnderwaterFlora(int id) {
    return (id == 8109);
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

vec3 foliageDisplacement(vec3 worldPos, vec3 worldNormal, float animationTime, float skyExposure, float stormBoost, float profileWindScale, bool isTopVertex, float blockFractY, out float flex) {
    vec3 windOffset = vec3(0.0);
    flex = 0.0;

    #ifdef WAVING_BAMBOO
    if (isBambooBlock(vMaterialId)) {
        float culmHeightPhase = worldPos.y * 0.28;
        vec3 mountainWind = evaluateMountainWind(worldPos + vec3(0.0, culmHeightPhase, 0.0), animationTime, skyExposure, stormBoost);
        float nodeVib = sin(animationTime * 6.5 * WIND_SPEED + worldPos.x * 3.1 + worldPos.z * 2.7 + worldPos.y * 1.4) * 0.025;
        float stalkFlex = 0.095 * profileWindScale;

        windOffset.xz = mountainWind.xz * stalkFlex + vec2(nodeVib, -nodeVib * 0.7) * skyExposure;
        windOffset.y  = -length(windOffset.xz) * 0.18;
        flex = clamp(length(windOffset.xz) * 6.0, 0.0, 1.0);
    }
    #endif

    #ifdef WAVING_SUGARCANE
    if (isSugarCaneBlock(vMaterialId)) {
        float segmentFactor = isTopVertex ? 1.0 : 0.45;
        vec3 mountainWind = evaluateMountainWind(worldPos, animationTime * 1.15, skyExposure, stormBoost);
        float reedFlutter = sin(animationTime * 4.8 * WIND_SPEED + dot(worldPos.xz, vec2(2.3, 1.9)) + worldPos.y * 1.8) * 0.03;

        windOffset.xz = (mountainWind.xz * 0.085 + vec2(reedFlutter)) * segmentFactor * profileWindScale;
        flex = clamp(length(windOffset.xz) * 7.0, 0.0, 1.0);
    }
    #endif

    #ifdef WAVING_LEAVES
    if (isLeavesBlock(vMaterialId)) {
        vec3 mountainWind = evaluateMountainWind(worldPos * 0.85, animationTime, skyExposure, stormBoost);
        float rustleTime = animationTime * 5.2 * WIND_SPEED;
        vec3 leafFlutter = vec3(
            sin(rustleTime + worldPos.x * 2.9 + worldPos.y * 1.7),
            cos(rustleTime * 0.85 + worldPos.y * 2.5 + worldPos.z * 2.1) * 0.6,
            sin(rustleTime * 1.15 + worldPos.z * 3.1 - worldPos.x * 1.9)
        ) * 0.028 * skyExposure;

        windOffset = (mountainWind * 0.065 + leafFlutter) * profileWindScale;
        flex = clamp(length(windOffset) * 8.0, 0.0, 1.0);
    }
    #endif

    #ifdef WAVING_GRASS
    if (isLowerGrassOrFoliage(vMaterialId)) {
        float anchorWeight = (isTopVertex || blockFractY > 0.25) ? 1.0 : 0.0;
        vec3 mountainWind = evaluateMountainWind(worldPos, animationTime * 1.25, skyExposure, stormBoost);

        windOffset.xz = mountainWind.xz * 0.120 * anchorWeight * profileWindScale;
        windOffset.y  = mountainWind.y * 0.05 * anchorWeight;
        flex = anchorWeight * clamp(length(windOffset.xz) * 5.0, 0.0, 1.0);
    } else if (isUpperTallGrass(vMaterialId)) {
        float heightWeight = isTopVertex ? 1.75 : 1.0;
        vec3 mountainWind = evaluateMountainWind(worldPos - vec3(0.0, 0.5, 0.0), animationTime * 1.25, skyExposure, stormBoost);

        windOffset.xz = mountainWind.xz * 0.120 * heightWeight * profileWindScale;
        windOffset.y  = -length(windOffset.xz) * 0.14;
        flex = clamp(length(windOffset.xz) * 4.5, 0.0, 1.0);
    } else if (isHangingStrand(vMaterialId)) {
        // Top-anchored inverted pendulum: ceiling attachment stays pinned while bottom tip sways gently
        float hangWeight = isTopVertex ? 0.12 : 1.0;
        vec3 mountainWind = evaluateMountainWind(worldPos, animationTime * 1.05, max(skyExposure, 0.25), stormBoost);
        windOffset.xz = mountainWind.xz * 0.075 * hangWeight * profileWindScale;
        windOffset.y  = length(windOffset.xz) * 0.08;
        flex = hangWeight * clamp(length(windOffset.xz) * 6.0, 0.0, 1.0);
    } else if (isWallVine(vMaterialId)) {
        // Wall-attached vine: micro-flutter tangent to or gently away from the block face (NEVER clips behind block!)
        vec3 mountainWind = evaluateMountainWind(worldPos, animationTime * 1.10, skyExposure, stormBoost);
        float microFlutter = sin(animationTime * 3.8 * WIND_SPEED + worldPos.x * 2.5 + worldPos.y * 2.1 + worldPos.z * 2.3) * 0.012;
        vec3 rawOffset = vec3(mountainWind.x * 0.022 + microFlutter, 0.0, mountainWind.z * 0.022 - microFlutter) * profileWindScale;
        vec3 n = (length(worldNormal) > 0.1) ? normalize(worldNormal) : vec3(0.0, 1.0, 0.0);
        float alongN = dot(rawOffset, n);
        // Clamp any inward motion into the supporting block to 0.0, and allow at most +0.024 outward lift
        rawOffset += n * (clamp(alongN, 0.0, 0.024) - alongN);
        windOffset = rawOffset * (isTopVertex ? 0.45 : 1.0);
        flex = clamp(length(windOffset) * 14.0, 0.0, 1.0);
    }
    #endif

    #ifdef WAVING_SUGARCANE
    if (isUnderwaterFlora(vMaterialId)) {
        float anchorWeight = (isTopVertex || blockFractY > 0.25) ? 1.0 : 0.0;
        float tFlow = animationTime * 1.6 * WIND_SPEED;
        float waveX = sin(tFlow + worldPos.x * 0.65 + worldPos.y * 0.85 + worldPos.z * 0.45);
        float waveZ = cos(tFlow * 0.85 + worldPos.z * 0.65 - worldPos.y * 0.75 + worldPos.x * 0.40);
        windOffset.xz = vec2(waveX, waveZ) * 0.070 * anchorWeight * profileWindScale;
        flex = anchorWeight * clamp(length(windOffset.xz) * 6.0, 0.0, 1.0);
    }
    #endif

    return windOffset;
}

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLmCoord  = clamp((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy, 0.0, 1.0);

    vVertexColor = gl_Color;
    if (vVertexColor.a < 0.05) {
        vVertexColor.a = 1.0;
    }

    vMaterialId = int(floor(mc_Entity.x + 0.5));
    // Cross-model plants (grass, saplings, flowers, reeds, vines, or any 45-degree diagonal cross quad)
    // must use an upward normal (0, 1, 0) so they match the exact lighting and shadow of the ground block beneath them!
    // Wall-mounted vines (8108) keep their real face normal; cross-model plants use upward normal
    bool isCrossModelQuad = (vMaterialId == 8101 || vMaterialId == 8104 || vMaterialId == 8105 || vMaterialId == 8107 || vMaterialId == 8109)
                         || (vMaterialId != 8108 && abs(gl_Normal.y) < 0.15 && abs(gl_Normal.x) > 0.20 && abs(gl_Normal.z) > 0.20);
    vec3 effNormal = isCrossModelQuad ? vec3(0.0, 1.0, 0.0) : gl_Normal;
    vViewNormal = normalize(gl_NormalMatrix * effNormal);

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vec4 playerPos = gbufferModelViewInverse * viewPos;
    vec3 worldPos = playerPos.xyz + cameraPosition;

    float skyExposure = smoothstep(0.15, 0.65, vLmCoord.y);
    float stormBoost  = clamp(rainStrength + wetness * 0.5, 0.0, 1.0);
    float profileWindScale = (STYLE_SELECTION == 1) ? 1.15 : 0.90;

    vec2 midCoord = (gl_TextureMatrix[0] * mc_midTexCoord).st;
    bool isTopVertex = (vTexCoord.y < midCoord.y);
    float blockFractY = fract(worldPos.y + 0.001);

    vec3 windOffset = foliageDisplacement(worldPos, gl_Normal, frameTimeCounter, skyExposure, stormBoost, profileWindScale, isTopVertex, blockFractY, vWindFlex);
#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
    float previousFlex;
    vec3 previousWind = foliageDisplacement(worldPos, gl_Normal, max(frameTimeCounter - frameTime, 0.0), skyExposure, stormBoost, profileWindScale, isTopVertex, blockFractY, previousFlex);
    vMotionDelta = windOffset - previousWind;
#endif

    playerPos.xyz += windOffset;
    vWorldPos = playerPos.xyz + cameraPosition;

    gl_Position = gbufferProjection * (gbufferModelView * playerPos);
    applyCameraJitter(gl_Position);
}
