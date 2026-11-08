#version 330 compatibility
#include "/lib/camera_options.glsl"
/* =============================================================================
 * gbuffers_terrain.fsh — YunMeng material classification pass
 * ============================================================================= */

in vec2 vTexCoord;
in vec2 vLmCoord;
in vec3 vViewNormal;
in vec3 vWorldPos;
in vec4 vVertexColor;
flat in int vMaterialId;
in float vWindFlex;
#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
in vec3 vMotionDelta;
/*
const int colortex5Format = RGBA16F;
*/
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
#endif

// Cleared each frame; water preserves this attachment via additive zero blend.
/*
const int colortex13Format = RGBA8;
*/
const vec4 colortex13ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
uniform sampler2D gtexture;
uniform float alphaTestRef;

#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
/* RENDERTARGETS: 0,1,2,5,13 */
layout(location = 4) out vec4 outOpaqueBank;
layout(location = 3) out vec4 outMotion;
#else
/* RENDERTARGETS: 0,1,2,13 */
layout(location = 3) out vec4 outOpaqueBank;
#endif
layout(location = 0) out vec4 outColor0;
layout(location = 1) out vec4 outColor1;
layout(location = 2) out vec4 outColor2;

float classifyMaterialTag(int id, vec3 tintedAlbedo) {
    if (id == 8200) {
        return 0.90; // Water
    }
    if (id == 8300) {
        return 0.16; // Clear glass
    }
    if (id == 8500) {
        return 0.82; // Smooth reflective ice (blue_ice)
    }
    if (id == 8501) {
        return 0.83; // Frosted packed ice
    }
    if (id == 8106) {
        return 0.50; // Bamboo
    }
    if (id == 8102 || id == 8103) {
        bool isBlossom = (tintedAlbedo.r > tintedAlbedo.g * 1.10 && tintedAlbedo.b > tintedAlbedo.g * 0.82);
        return isBlossom ? 0.75 : 0.25; // Cherry blossom vs leaves
    }
    if (id == 8101 || id == 8104 || id == 8105) {
        return 0.25; // Foliage & reeds
    }
    return 0.00;
}

void main() {
    outOpaqueBank = vec4(0.0);
#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
    outMotion = vec4(vMotionDelta, 1.0);
#endif
    vec4 texSample = texture(gtexture, vTexCoord);

    if (texSample.a < max(alphaTestRef, 0.1)) {
        discard;
    }

    vec3 albedo = texSample.rgb * vVertexColor.rgb;
    float vertexAo = clamp(vVertexColor.a, 0.0, 1.0);
    vec3 viewNormal = normalize(vViewNormal);
    float matTag = classifyMaterialTag(vMaterialId, albedo);

    outColor0 = vec4(albedo, 1.0);
    outColor1 = vec4(viewNormal * 0.5 + 0.5, matTag);
    // Record solid terrain surface normals in colortex13 for underwater riverbed shading.
    bool isSolidTerrain = (vMaterialId == 8400 || vMaterialId == 8500 || vMaterialId == 8501) || (matTag < 0.05 && alphaTestRef < 0.05);
    if (vMaterialId != 8200 && vMaterialId != 8300) outOpaqueBank = vec4(viewNormal * 0.5 + 0.5, 1.0);
    float terrainMetadata = isSolidTerrain ? 1.0 : clamp(vWindFlex, 0.0, 1.0);
    outColor2 = vec4(vLmCoord.x, vLmCoord.y, vertexAo, terrainMetadata);
}
