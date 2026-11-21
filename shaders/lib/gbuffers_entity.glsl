#include "/lib/camera_options.glsl"
in vec2 vTexCoord;
in vec2 vLmCoord;
in vec3 vViewNormal;
in vec4 vVertexColor;

uniform sampler2D gtexture;
uniform vec4 entityColor;
uniform float rainStrength;
#ifdef YUNMENG_PORTAL_ENTITIES
uniform int blockEntityId;
#endif
#ifdef YUNMENG_ONLY_TRUE_ENTITIES
uniform sampler2D specular;
#endif

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

void main() {
    outOpaqueBank = vec4(0.0);
#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
    outMotion = vec4(0.0);
#endif
    // Explicit block-entity identity; never classify a portal from its color.
#ifdef YUNMENG_PORTAL_ENTITIES
    if (blockEntityId == 8600) {
        outColor0 = vec4(0.0, 0.0, 0.0, 1.0);
        outColor1 = vec4(0.5, 1.0, 0.5, 0.98);
        outColor2 = vec4(0.0, 1.0, 1.0, 0.0);
        return;
    }
#endif
    vec4 texSample = texture(gtexture, vTexCoord) * vVertexColor;
    if (texSample.a < 0.12) {
        discard;
    }

    vec3 albedo = mix(texSample.rgb, entityColor.rgb, entityColor.a);
    // Neutralize vanilla's bright royal-blue rain splash particles into soft silver-mist droplets
    if (abs(YUNMENG_ENTITY_TAG - 0.06) < 0.01 && rainStrength > 0.02) {
        float blueExcess = albedo.b - max(albedo.r, albedo.g);
        if (blueExcess > 0.14 && vLmCoord.y > 0.65) {
            float splashLuma = clamp(dot(albedo, vec3(0.25, 0.35, 0.40)) * 1.45, 0.45, 0.88);
            albedo = mix(albedo, vec3(0.74, 0.81, 0.84) * splashLuma, clamp(rainStrength * 1.25, 0.0, 0.92));
        }
    }
    vec3 viewNormal = normalize(gl_FrontFacing ? vViewNormal : -vViewNormal);
    float outMatTag = YUNMENG_ENTITY_TAG;
    float outBlockLight = min(vLmCoord.x, 0.94);

#ifdef YUNMENG_ONLY_TRUE_ENTITIES
#if EMISSIVE_EYES_MODE > 0
    ivec2 gTexSize   = textureSize(gtexture, 0);
    ivec2 texelCoord = clamp(ivec2(vTexCoord * vec2(gTexSize)), ivec2(0), max(gTexSize - 1, ivec2(0)));

    // 1. Exact integer texelFetch on LabPBR specular.a (8..252 = emissive; 0 and 255 = non-emissive):
    //    - Never reads specular.b (porosity/subsurface scattering) and never interpolates 0 with 255 on cutout edges.
    ivec2 specSize = textureSize(specular, 0);
    float labPbrEmissive = 0.0;
    if (specSize.x >= 16 && specSize.y >= 16 && texSample.a > 0.85) {
        ivec2 specCoord = clamp(ivec2(vTexCoord * vec2(specSize)), ivec2(0), specSize - 1);
        float rawSpecA  = texelFetch(specular, specCoord, 0).a;
        int specByte    = int(floor(rawSpecA * 255.0 + 0.5));
        if (specByte >= 8 && specByte <= 252) {
            labPbrEmissive = rawSpecA;
        }
    }

    // 2. Sample unshaded, unfiltered raw texel so directional vertex shading (0.6 on sides vs 0.8 on fronts)
    //    and bilinear texture filtering never distort emissive classification thresholds.
    vec4 rawTex     = texelFetch(gtexture, texelCoord, 0);
    float rawPeak   = max(rawTex.r, max(rawTex.g, rawTex.b));
    float rawMin    = min(rawTex.r, min(rawTex.g, rawTex.b));
    float rawChroma = rawPeak - rawMin;
    float rawSat    = rawChroma / max(rawPeak, 1e-4);

    // 3. Detect standard 2:1 EndermanModel UV geometry via 4 structural UV coordinates:
    //    - Opaque dark forehead (12/64, 10/32) and torso front (40/64, 22/32)
    //    - Opaque long lower limb (58/64, 24/32)
    //    - Transparent unused upper-torso header (36/64, 2/32) (rejects minecarts, books, boats, and animals)
    vec4 sForehead = texelFetch(gtexture, clamp(ivec2((gTexSize.x * 12) / 64, (gTexSize.y * 10) / 32), ivec2(0), max(gTexSize - 1, ivec2(0))), 0);
    vec4 sTorso    = texelFetch(gtexture, clamp(ivec2((gTexSize.x * 40) / 64, (gTexSize.y * 22) / 32), ivec2(0), max(gTexSize - 1, ivec2(0))), 0);
    vec4 sLimb     = texelFetch(gtexture, clamp(ivec2((gTexSize.x * 58) / 64, (gTexSize.y * 24) / 32), ivec2(0), max(gTexSize - 1, ivec2(0))), 0);
    vec4 sUnused   = texelFetch(gtexture, clamp(ivec2((gTexSize.x * 36) / 64, (gTexSize.y *  2) / 32), ivec2(0), max(gTexSize - 1, ivec2(0))), 0);
    float foreheadPeak = max(sForehead.r, max(sForehead.g, sForehead.b));
    float torsoPeak    = max(sTorso.r,    max(sTorso.g,    sTorso.b));
    bool isDarkHumanoidMob = (gTexSize.x == gTexSize.y * 2)
                          && (sForehead.a > 0.95 && sTorso.a > 0.95 && sLimb.a > 0.95 && sUnused.a < 0.05)
                          && (foreheadPeak < 0.22 && torsoPeak < 0.22);

    // 4. Support both single-layer outer head eyes (row 12/32) and 2-layer cutout eye windows (where row 12/32 on the
    //    outer head has transparent eye cutouts a < 0.15, revealing row 28/32 on the recessed inner head cube):
    vec4 sOuterEyeL = texelFetch(gtexture, clamp(ivec2((gTexSize.x * 9)  / 64, (gTexSize.y * 12) / 32), ivec2(0), max(gTexSize - 1, ivec2(0))), 0);
    vec4 sOuterEyeR = texelFetch(gtexture, clamp(ivec2((gTexSize.x * 14) / 64, (gTexSize.y * 12) / 32), ivec2(0), max(gTexSize - 1, ivec2(0))), 0);
    bool hasCutoutEyeWindow = (sOuterEyeL.a < 0.15 && sOuterEyeR.a < 0.15);

    int col64 = (texelCoord.x * 64) / max(gTexSize.x, 1);
    int row32 = (texelCoord.y * 32) / max(gTexSize.y, 1);

    bool inHeadHalf   = (col64 < 32);
    bool inLeftEyeX   = (col64 >= 8  && col64 <= 10); // Left 3-texel eye (strictly excludes nose bridge cols 11..12)
    bool inRightEyeX  = (col64 >= 13 && col64 <= 15); // Right 3-texel eye (strictly excludes nose bridge cols 11..12)
    int  activeEyeRow = hasCutoutEyeWindow ? 28 : 12; // Row 28/32 behind cutout window, or Row 12/32 on outer head
    bool inHeadEyeRow = (inLeftEyeX || inRightEyeX) && (row32 == activeEyeRow);
    bool inBodyOrLimb = (col64 >= 32);

    bool isCoolBioluminescent = (rawTex.g > rawTex.r * 1.35 || rawTex.b > rawTex.r * 1.35);
    // On limbs/body, require high bioluminescent chroma and peak so dark base shading stays unlit
    // and only the brighter pattern texels glow with clear pixel-to-pixel contrast:
    bool isBiolumLimbPixel = ((rawTex.g > rawTex.r * 1.45 && (rawTex.g - rawTex.b) > (rawTex.g - rawTex.r) * 0.30)
                           || (rawTex.b > rawTex.g * 1.50 && rawTex.r > rawTex.g * 1.25))
                           && (rawPeak > 0.58) && (rawSat > 0.43);

    bool isIntegratedPackEye  = false;
    bool isIntegratedPackLimb = false;
#if EMISSIVE_EYES_MODE >= 2
    if (isDarkHumanoidMob && entityColor.a < 0.01) {
        if (inHeadEyeRow && rawPeak > 0.45 && rawSat > 0.30) {
            isIntegratedPackEye = true;
        }
        if (inBodyOrLimb && isBiolumLimbPixel) {
            isIntegratedPackLimb = true;
        }
    }
#endif

    // Prevent non-eye rows of a 2-layer head/jaw or dark limb base tones from false-triggering glow:
    if (isDarkHumanoidMob && inHeadHalf && !inHeadEyeRow) {
        labPbrEmissive = 0.0;
    }
    if (isDarkHumanoidMob && inBodyOrLimb && !isBiolumLimbPixel) {
        labPbrEmissive = 0.0;
    }
    if (!isCoolBioluminescent && rawPeak < 0.65 && rawSat < 0.65) {
        labPbrEmissive = 0.0;
    }

    if ((labPbrEmissive > 0.01 || isIntegratedPackEye || isIntegratedPackLimb) && rawPeak > 0.35) {
        float targetPeak;
        if (isDarkHumanoidMob && inHeadEyeRow) {
            // Preserve sclera (0.48) vs. center pupil (0.92) contrast inside the 3-texel eye
            targetPeak = clamp(mix(0.48, 0.92, smoothstep(0.55, 0.63, rawPeak)), 0.48, 0.92);
        } else if (isDarkHumanoidMob && inBodyOrLimb) {
            // Preserve distinct pixel contrast between medium (0.40) and bright (0.72) limb markings
            targetPeak = clamp(mix(0.40, 0.72, smoothstep(0.62, 0.78, rawPeak)), 0.40, 0.72);
        } else {
            targetPeak = clamp(mix(0.65, 0.95, smoothstep(0.35, 0.85, rawPeak)), 0.65, 0.95);
        }
        vec3 dewhitened = (rawChroma > 0.02) ? max(rawTex.rgb - rawMin * 0.38, vec3(0.0)) : rawTex.rgb;
        float newPeak   = max(dewhitened.r, max(dewhitened.g, dewhitened.b));
        albedo          = (dewhitened / max(newPeak, 1e-4)) * targetPeak;
        outMatTag       = 0.36;
        outBlockLight   = 1.0;
    }
#endif
#endif

    outColor0 = vec4(albedo, 1.0);
    outColor1 = vec4(viewNormal * 0.5 + 0.5, outMatTag);
    outColor2 = vec4(outBlockLight, max(vLmCoord.y, 0.15), 1.0, 0.0);
}
