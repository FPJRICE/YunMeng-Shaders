#version 330 compatibility
#include "/lib/temporal_jitter.glsl"
#include "/lib/camera_options.glsl"
#include "/lib/water_optics.glsl"
#include "/lib/flow_direction.glsl"
// Modified 2026-10-15: extended Guofeng and Xianxia above-water depth-color ramps.
/* =============================================================================
 * gbuffers_water.fsh — Surface-aligned water normals and depth absorption.
 * ============================================================================= */

#define STYLE_SELECTION 1          // [0 1] 0: Guofeng Ink, 1: Xianxia Mist
#define WATER_WAVE_HEIGHT 1.00     // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#ifndef SKY_STYLE
#define SKY_STYLE 0                // [0 1] 0: Wuxia Smooth, 1: Minecraft Voxel
#endif
#ifndef WATER_STYLE
#define WATER_STYLE 0              // [0 1 2] 0: Auto (By Shader Style), 1: Wuxia Smooth, 2: Minecraft Voxel
#endif
#define WATER_TEXTURE 0.00         // [0.00 0.25 0.50 0.75 1.00]
#define WIND_SPEED 1.00            // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]
#ifndef BIOME_TINT_STRENGTH
#define BIOME_TINT_STRENGTH 1.00   // [0.00 0.50 0.75 1.00 1.15 1.25 1.50]
#endif

in vec2 vTexCoord;
in vec2 vLmCoord;
in vec3 vViewNormal;
in vec3 vWorldNormal;
in vec3 vWorldPos;
in vec3 vPlayerPos;
in vec4 vVertexColor;
flat in int vMaterialId;
in float vVerticalCurtain;

uniform sampler2D gtexture;
uniform sampler2D depthtex1;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform int isEyeInWater;
uniform float inBambooJungle;
uniform float inCherryGrove;
uniform float inSnowyBiome;
uniform float inAridBiome;
uniform float inSwampBiome;
#include "/lib/water_waves.glsl"
#include "/lib/water_fall.glsl"


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

float linearizeDepth(float d) {
    return (2.0 * near * far) / max(far + near - (d * 2.0 - 1.0) * (far - near), 1e-5);
}

vec3 reconstructViewPos(vec2 uv, float depth) {
    vec4 ndc = vec4((uv - cameraJitter(frameCounter, vec2(viewWidth, viewHeight))) * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * ndc;
    return viewPos.xyz / max(viewPos.w, 1e-6);
}

// Hash without Sine by David Hoskins (MIT License, https://www.shadertoy.com/view/4djSRW)
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Quintic value noise & analytical 2D derivatives (Ken Perlin 2002; Inigo Quilez, MIT License)
vec3 smoothNoiseGrad(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    float a = hash12(i + vec2(0.0, 0.0));
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));

    vec2 u  = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    float val = a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y;
    vec2 grad = du * vec2(
        (b - a) + (a - b - c + d) * u.y,
        (c - a) + (a - b - c + d) * u.x
    );
    return vec3(grad, val);
}

float fbmSmooth(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(0.80, -0.60, 0.60, 0.80);
    for (int i = 0; i < 3; i++) {
        v += a * smoothNoiseGrad(p).z;
        p = rot * p * 2.03 + vec2(13.7, 29.3);
        a *= 0.5;
    }
    return v;
}

vec3 evaluateFilteredWaveField(vec2 wp, float time, float viewDist) {
    const mat2 ROT1 = mat2( 0.921, -0.389,  0.389,  0.921);
    const mat2 ROT2 = mat2( 0.629,  0.777, -0.777,  0.629);
    const mat2 ROT3 = mat2(-0.438,  0.899, -0.899, -0.438);
    const mat2 ROT4 = mat2( 0.259, -0.966,  0.966,  0.259);

    float mip1 = exp(-viewDist * 0.008);
    float mip2 = exp(-viewDist * 0.018);
    float mip3 = exp(-viewDist * 0.038);
    float mip4 = exp(-viewDist * 0.075);

    vec2 uv1 = ROT1 * (wp * 0.11) + vec2( 0.09,  0.04) * time;
    vec2 uv2 = ROT2 * (wp * 0.27) + vec2(-0.13,  0.08) * time;
    vec2 uv3 = ROT3 * (wp * 0.59) + vec2( 0.17, -0.11) * time;
    vec2 uv4 = ROT4 * (wp * 1.23) + vec2(-0.23, -0.19) * time;

    vec3 n1 = smoothNoiseGrad(uv1 * 3.2);
    vec3 n2 = smoothNoiseGrad(uv2 * 3.2 + n1.xy * 0.25);
    vec3 n3 = smoothNoiseGrad(uv3 * 3.2 + n2.xy * 0.20);
    vec3 n4 = smoothNoiseGrad(uv4 * 3.2);

    vec2 grad = n1.xy * (0.42 * mip1)
              + n2.xy * (0.34 * mip2)
              + n3.xy * (0.22 * mip3)
              + n4.xy * (0.14 * mip4);
    float height = n1.z * 0.45 + n2.z * 0.35 + n3.z * 0.20;

    return vec3(grad, height);
}

void main() {
    outOpaqueBank = vec4(0.0);
#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
    outMotion = vec4(0.0);
#endif
    vec4 texSample = texture(gtexture, vTexCoord);
    if (texSample.a < 0.05) {
        discard;
    }

    float waterFootprint = max(length(dFdx(vWorldPos.xz)),length(dFdy(vWorldPos.xz)));
    float flowDirection=encodeWaterFlow(dFdx(vWorldPos),dFdy(vWorldPos),
                                        dFdx(vTexCoord),dFdy(vTexCoord));
    bool isWater = (vMaterialId == 8200);
    if (!isWater) {
        vec3 normEnc = normalize(vViewNormal) * 0.5 + 0.5;
        float nonWaterTag = (vMaterialId == 8500) ? 0.82 : ((vMaterialId == 8501) ? 0.83 : 0.0);
        outColor0 = vec4(texSample.rgb * vVertexColor.rgb, texSample.a);
        outColor1 = vec4(normEnc, nonWaterTag);
        outColor2 = vec4(vLmCoord.x, vLmCoord.y, vVertexColor.a, 1.0);
        // Write non-water translucent blocks (such as minecraft:ice) into colortex13 with
        // additive blending (ONE ONE ONE ONE) so water drawn in front of unbroken ice underwater
        // preserves the ice witness in colortex13.a and never leaks the Snell's window skybox.
        outOpaqueBank = vec4(normEnc, 1.0);
        return;
    }

    vec3 geoNormal = normalize(vWorldNormal);
    float verticalFace = vVerticalCurtain;
    // Classify real side geometry even if the renderer supplies an upward
    // fluid vertex normal. Otherwise a wall receives horizontal-water ripples.
    // Undisplaced coordinates keep this independent of animated vertex height.
    vec3 shapeCross = cross(dFdx(vWorldPos), dFdy(vWorldPos));
    vec3 shapeNormal = shapeCross / max(length(shapeCross), 1e-8);

    if (isEyeInWater == 0 && abs(shapeNormal.y) < 0.25 &&
        abs(geoNormal.y) > 0.70 && dot(shapeCross,shapeCross)>1e-12) {
        geoNormal=shapeNormal;
        if(dot(geoNormal,vPlayerPos)>0.0) geoNormal=-geoNormal;
        verticalFace=1.0;
    }
    // A sloping fluid top also needs its actual face normal when the supplied
    // normal is upward. Keep the outward hemisphere of the supplied normal.
    if (isEyeInWater==0 && abs(geoNormal.y)>0.99 &&
        abs(shapeNormal.y)>=0.25 && abs(shapeNormal.y)<0.985 &&
        dot(shapeCross,shapeCross)>1e-12) {
        geoNormal=dot(shapeNormal,geoNormal)<0.0 ? -shapeNormal : shapeNormal;
    }
    bool slopedTop=isEyeInWater==0 && verticalFace<0.5 &&
        abs(shapeNormal.y)>=0.25 && abs(shapeNormal.y)<0.985 &&
        dot(shapeCross,shapeCross)>1e-12;

    vec2 screenUV = gl_FragCoord.xy / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    float solidRawDepth = texture(depthtex1, screenUV).r;

    vec3 solidViewPos   = reconstructViewPos(screenUV, solidRawDepth);
    vec3 solidPlayerPos = (gbufferModelViewInverse * vec4(solidViewPos, 1.0)).xyz;
    vec3 solidWorldPos  = solidPlayerPos + cameraPosition;

    // Compute both vertical drop and full 3D ray path through the water volume.
    // Using 3D ray distance instead of dot(solidPlayerPos - vPlayerPos, geoNormal)
    // ensures vertical waterfall side faces looking at internal horizontal steps
    // maintain consistent optical thickness and opacity with adjacent cascade faces.
    float verticalWaterDepth = solidRawDepth < 0.999999
        ? max(vWorldPos.y - solidWorldPos.y, 0.0) : 32.0;
    float rayWaterDist = solidRawDepth < 0.999999
        ? max(length(solidPlayerPos - vPlayerPos), 0.0) : 32.0;
    float normalThickness = solidRawDepth < 0.999999
        ? abs(dot(solidPlayerPos - vPlayerPos, geoNormal)) : 32.0;

    float sheetOptics = verticalFace;
    if (isEyeInWater == 0) {
        sheetOptics = max(sheetOptics, 1.0 - smoothstep(0.70, 0.985, abs(shapeNormal.y)));
    }
    // Bound extreme vertical drops when a thin elevated waterfall step looks down past a ledge
    float columnThickness = max(mix(rayWaterDist, normalThickness, 0.35), 0.55 * sheetOptics);
    float boundedPoolDepth = min(verticalWaterDepth, rayWaterDist * 1.15 + 0.35);
    float absorptionDepth = mix(boundedPoolDepth, min(columnThickness, 2.25), sheetOptics * 0.72);

    float time = frameTimeCounter * WIND_SPEED;
    vec2 wp = vWorldPos.xz;
    float viewDist = length(vPlayerPos);

    // Planar coordinates follow the geometric face, including waterfall walls.
    // Never replace a vertical face normal with an upward-facing water normal.
    vec3 tangent = normalize(cross(abs(geoNormal.z) < 0.9
        ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0), geoNormal));
    vec3 bitangent = normalize(cross(geoNormal, tangent));
    vec3 patternPos = vWorldPos;
    patternPos.y += time * 0.85 * verticalFace; // pattern travels downward
    vec2 worldCoord = vec2(dot(patternPos, tangent), dot(patternPos, bitangent));
    vec3 blendedWave = vec3(0.0);
    if (verticalFace >= 0.5) {
        if (isEyeInWater != 0) blendedWave = evaluateFilteredWaveField(worldCoord,time,viewDist);
        else {
            vec3 sheet=waterFallField(vWorldPos,geoNormal,time);
            float visible=1.0-smoothstep(0.15,0.55,
                max(length(dFdx(worldCoord)),length(dFdy(worldCoord))));
            vec3 flowSlope=waterFallAcross(geoNormal)*sheet.x+vec3(0.0,sheet.y,0.0);
            blendedWave.xy=vec2(dot(flowSlope,tangent),dot(flowSlope,bitangent))*visible;
        }
    }

    vec3 viewRayWorld = normalize(vPlayerPos);
    float NdotVGeo = clamp(abs(dot(viewRayWorld, geoNormal)), 0.0, 1.0);

    float grazingDamp = mix(0.25, 1.0, NdotVGeo);
    if (isEyeInWater == 0 && verticalFace < 0.5) {
        grazingDamp = mix(0.55, 1.0, NdotVGeo);
    }
    float normalStrength = (STYLE_SELECTION == 0 ? 0.09 : 0.15) * WATER_WAVE_HEIGHT * grazingDamp;
    vec3 worldWaveNormal = normalize(geoNormal - normalStrength *
        (blendedWave.x * tangent + blendedWave.y * bitangent));
    vec3 coherentWave = vec3(0.0);
    if (verticalFace < 0.5) {
        float footprint = waterFootprint;
        // Soften wave amplitude slightly near block rims where flat source blocks spill onto slopes.
        // Note: waterSurfaceWaves automatically scales wave amplitude to a calmer 0.45x when ACTIVE_WATER_STYLE == 2.
        float slopeTransitionDamp = slopedTop ? 0.72 : 1.0;
        coherentWave = waterSurfaceWaves(vWorldPos.xz, time, footprint) * slopeTransitionDamp;
        vec2 slope = coherentWave.xy;
        worldWaveNormal = normalize(geoNormal - vec3(slope.x, 0.0, slope.y) *
                                   (WATER_WAVE_HEIGHT * grazingDamp * sign(geoNormal.y)));
    }
    vec3 perturbedViewNormal = normalize(mat3(gbufferModelView) * worldWaveNormal);

    float NdotV = clamp(abs(dot(worldWaveNormal, viewRayWorld)), 0.0, 1.0);
    float fresnel = pow(1.0 - NdotV, 3.8);

    vec3 finalWaterColor;
    float finalAlpha;

    // Theme-Aware Relative Biome Water Color Transfer:
    // Measures per-vertex biome water tint (vVertexColor.rgb) relative to vanilla default water (#3F76E4 = 0.247, 0.463, 0.894)
    // so Default Rivers/Oceans keep 100% of their signature Guofeng Celadon-Jade or Xianxia Spirit-Azure palette,
    // while Warm Oceans (#43D5EE), Swamps (#617B64), Mangroves (#3A7A6A), Frozen Oceans (#3938C9), and Modded Biomes
    // shift smoothly and authentically within the active theme!
    const vec3 VANILLA_DEFAULT_WATER = vec3(0.247, 0.463, 0.894);
    // Direct per-channel ratio preserves BOTH hue AND luminance differences between adjacent biomes
    // visible in the same view (e.g. bright teal #45ADF2 on the left vs dark frozen cobalt #3938C9 on the right)!
    vec3 rawBiomeRatio = clamp(vVertexColor.rgb / VANILLA_DEFAULT_WATER, vec3(0.28), vec3(2.15));
    float biomeStrength = clamp(BIOME_TINT_STRENGTH, 0.0, 1.5);
    float chromaAdapt = ((STYLE_SELECTION == 0) ? 0.78 : 0.85) * min(biomeStrength, 1.25);
    if (ACTIVE_WATER_STYLE == 2) {
        chromaAdapt = min(chromaAdapt * 1.12, 0.94);
    }
    vec3 biomeChromaMod = mix(vec3(1.0), rawBiomeRatio, chromaAdapt);

    // Per-vertex biome water detectors from vVertexColor.rgb so two biomes meeting in the middle of a lake
    // display their distinct theme-curated palettes simultaneously side-by-side across the boundary!
    float vColdness = clamp((vVertexColor.b * 0.50 - vVertexColor.g) * 5.0, 0.0, 1.0);
    float vWarmth   = clamp((vVertexColor.g - vVertexColor.b * 0.55) * 3.2, 0.0, 1.0)
                    * clamp((vVertexColor.b - vVertexColor.r * 1.6) * 3.0, 0.0, 1.0);
    float vSwamp    = clamp((vVertexColor.g - vVertexColor.b * 0.82) * 4.5, 0.0, 1.0)
                    * (1.0 - smoothstep(0.45, 0.68, vVertexColor.b));

    float wSwamp  = clamp(max(vSwamp,    inSwampBiome   * 0.35) * biomeStrength, 0.0, 1.0);
    float wSnowy  = clamp(max(vColdness, inSnowyBiome   * 0.35) * biomeStrength, 0.0, 1.0);
    float wWarm   = clamp(vWarmth * biomeStrength, 0.0, 1.0);
    float wBamboo = clamp(inBambooJungle * biomeStrength, 0.0, 1.0);
    float wCherry = clamp(inCherryGrove  * biomeStrength, 0.0, 1.0);
    float wArid   = clamp(inAridBiome    * biomeStrength, 0.0, 1.0);

    if (isEyeInWater == 1) {
        vec3 actualWorldNormal = dot(shapeCross, shapeCross) > 1e-12 ? shapeNormal : geoNormal;
        // 0.0 on horizontal/gently-sloped ceilings; 1.0 on vertical waterfall walls
        float nearExit = 1.0 - smoothstep(0.30, 0.78, abs(actualWorldNormal.y));

        // Evaluate continuous world-space wave ripples for the underwater ceiling so the water surface
        // overhead has visible, tangible wave texture and glints without polygon seams across sloped faces.
        vec3 ceilingWave = waterSurfaceWaves(vWorldPos.xz, time, waterFootprint);
        vec3 continuousCeilingWorldNormal = normalize(vec3(-ceilingWave.x * WATER_WAVE_HEIGHT * 0.85, -1.0, -ceilingWave.y * WATER_WAVE_HEIGHT * 0.85));
        vec3 continuousCeilingViewNormal  = normalize(mat3(gbufferModelView) * continuousCeilingWorldNormal);
        vec3 uwNormalView = normalize(mix(continuousCeilingViewNormal, -perturbedViewNormal, nearExit));

        float uwFresnel = pow(1.0 - clamp(abs(dot(continuousCeilingWorldNormal, viewRayWorld)), 0.0, 1.0), 3.0);

        if (STYLE_SELECTION == 0) {
            vec3 ceilingTint = mix(vec3(0.18, 0.36, 0.38), vec3(0.32, 0.54, 0.52), uwFresnel * 0.65) * biomeChromaMod;
            vec3 wallTint    = vec3(0.24, 0.46, 0.47) * biomeChromaMod;
            finalWaterColor  = mix(ceilingTint, wallTint, nearExit);
            finalAlpha       = clamp(mix(0.56 + uwFresnel * 0.34, 0.70, nearExit), 0.54, 0.92);
        } else {
            vec3 ceilingTint = mix(vec3(0.10, 0.36, 0.46), vec3(0.16, 0.50, 0.60), uwFresnel * 0.75) * biomeChromaMod;
            vec3 wallTint    = vec3(0.12, 0.42, 0.52) * biomeChromaMod;
            finalWaterColor  = mix(ceilingTint, wallTint, nearExit);
            finalAlpha       = clamp(mix(0.58 + uwFresnel * 0.34, 0.70, nearExit), 0.56, 0.92);
        }
        float effWaterTexUW = (WATER_TEXTURE > 0.0) ? WATER_TEXTURE : ((ACTIVE_WATER_STYLE == 2) ? 0.62 : 0.0);
        if (effWaterTexUW > 0.0) {
            float texLuma = dot(texSample.rgb, vec3(0.2126, 0.7152, 0.0722));
            float texContrast = clamp((texLuma - 0.58) * 1.65, -0.35, 0.45);
            vec3 packTint = mix(texSample.rgb * vVertexColor.rgb, texSample.rgb, 0.35);
            vec3 texturedUW = mix(finalWaterColor * (1.0 + texContrast * 0.55), packTint, 0.35);
            finalWaterColor = mix(finalWaterColor, texturedUW, effWaterTexUW);
            finalAlpha = clamp(finalAlpha + effWaterTexUW * 0.10, 0.32, 0.82);
        }
        outColor0 = vec4(finalWaterColor, finalAlpha);
        outColor1 = vec4(uwNormalView * 0.5 + 0.5, 0.90);
        outColor2 = vec4(vLmCoord.x, vLmCoord.y, 1.0, nearExit);
        return;
    }

    if (STYLE_SELECTION == 0) {
        // GUOFENG INK: Celadon-Jade base shifted by relative biome vertex color + curated mineral-ink biome palettes
        float strokeRibbon = smoothstep(0.008, 0.034, coherentWave.z) * 0.45 * (1.0 - verticalFace);

        vec3 shallowCeladon = vec3(0.30, 0.55, 0.54) * biomeChromaMod;
        vec3 deepJadeInk    = vec3(0.10, 0.28, 0.33) * biomeChromaMod;
        vec3 abyssInk       = vec3(0.06, 0.17, 0.20) * biomeChromaMod;

        // Curated Guofeng biome refinements (Jiangnan tea-moss in Swamps, Huaqing slate-indigo in Snowy, Feicui in Warm)
        shallowCeladon = mix(shallowCeladon, vec3(0.24, 0.64, 0.60), wWarm   * 0.50);
        deepJadeInk    = mix(deepJadeInk,    vec3(0.08, 0.34, 0.38), wWarm   * 0.50);

        shallowCeladon = mix(shallowCeladon, vec3(0.34, 0.44, 0.26), wSwamp  * 0.60);
        deepJadeInk    = mix(deepJadeInk,    vec3(0.10, 0.16, 0.09), wSwamp  * 0.65);
        abyssInk       = mix(abyssInk,       vec3(0.06, 0.10, 0.06), wSwamp  * 0.65);

        shallowCeladon = mix(shallowCeladon, vec3(0.16, 0.28, 0.52), wSnowy  * 0.60);
        deepJadeInk    = mix(deepJadeInk,    vec3(0.05, 0.10, 0.26), wSnowy  * 0.65);
        abyssInk       = mix(abyssInk,       vec3(0.03, 0.06, 0.18), wSnowy  * 0.65);

        shallowCeladon = mix(shallowCeladon, vec3(0.26, 0.58, 0.48), wBamboo * 0.42);
        shallowCeladon = mix(shallowCeladon, vec3(0.38, 0.56, 0.60), wCherry * 0.38);
        shallowCeladon = mix(shallowCeladon, vec3(0.28, 0.56, 0.52), wArid   * 0.35);

        float depthBlend = clamp(1.0 - exp(-absorptionDepth * 0.52), 0.0, 1.0);
        finalWaterColor  = mix(shallowCeladon, deepJadeInk, depthBlend);
        finalWaterColor  = mix(finalWaterColor, vec3(0.78, 0.84, 0.80), strokeRibbon * 0.20);
        finalAlpha       = clamp(0.60 + depthBlend * 0.28 + fresnel * 0.22, 0.0, 0.94);

        float extendedDepth = (1.0 - exp(-absorptionDepth * 0.26)) * 0.72 +
                              (1.0 - exp(-absorptionDepth * 0.05)) * 0.28;
        vec3 depthColor = mix(shallowCeladon, abyssInk, extendedDepth);
        depthColor      = mix(depthColor, vec3(0.78, 0.84, 0.80), strokeRibbon * 0.20);
        float depthAlpha = clamp(0.54 + extendedDepth * 0.36 + fresnel * 0.22, 0.0, 0.94);
        finalWaterColor = mix(depthColor, finalWaterColor, sheetOptics * 0.55);
        finalAlpha      = mix(depthAlpha, finalAlpha, sheetOptics * 0.55);
    } else {
        // XIANXIA MIST: Spirit-Jade to Sapphire base shifted by relative biome vertex color + spirit-realm biome palettes
        vec3 shallowJade  = vec3(0.10, 0.48, 0.56) * biomeChromaMod;
        vec3 deepSapphire = vec3(0.03, 0.20, 0.36) * biomeChromaMod;
        vec3 abyssSapphire = vec3(0.02, 0.11, 0.22) * biomeChromaMod;

        // Curated Xianxia biome refinements (Spirit-spring turquoise in Warm, Lotus olive-emerald in Swamps, Glacial cobalt in Snowy)
        shallowJade   = mix(shallowJade,   vec3(0.12, 0.64, 0.68), wWarm   * 0.55);
        deepSapphire  = mix(deepSapphire,  vec3(0.04, 0.28, 0.42), wWarm   * 0.55);

        shallowJade   = mix(shallowJade,   vec3(0.24, 0.44, 0.26), wSwamp  * 0.60);
        deepSapphire  = mix(deepSapphire,  vec3(0.06, 0.15, 0.09), wSwamp  * 0.65);
        abyssSapphire = mix(abyssSapphire, vec3(0.03, 0.09, 0.05), wSwamp  * 0.65);

        shallowJade   = mix(shallowJade,   vec3(0.10, 0.22, 0.62), wSnowy  * 0.62);
        deepSapphire  = mix(deepSapphire,  vec3(0.03, 0.07, 0.30), wSnowy  * 0.68);
        abyssSapphire = mix(abyssSapphire, vec3(0.02, 0.04, 0.20), wSnowy  * 0.68);

        shallowJade   = mix(shallowJade,   vec3(0.12, 0.54, 0.48), wBamboo * 0.45);
        shallowJade   = mix(shallowJade,   vec3(0.24, 0.56, 0.68), wCherry * 0.40);
        shallowJade   = mix(shallowJade,   vec3(0.14, 0.56, 0.60), wArid   * 0.38);

        float depthBlend = clamp(1.0 - exp(-absorptionDepth * 0.50), 0.0, 1.0);
        finalWaterColor  = mix(shallowJade, deepSapphire, depthBlend);
        finalAlpha       = clamp(0.58 + depthBlend * 0.30 + fresnel * 0.26, 0.0, 0.94);

        float shelfBlend    = 1.0 - exp(-absorptionDepth * 0.24);
        float abyssBlend    = 1.0 - exp(-absorptionDepth * 0.045);
        float extendedDepth = shelfBlend * 0.72 + abyssBlend * 0.28;
        vec3 depthColor     = mix(shallowJade, abyssSapphire, extendedDepth);
        float depthAlpha    = clamp(0.52 + extendedDepth * 0.38 + fresnel * 0.26, 0.0, 0.94);
        finalWaterColor = mix(depthColor, finalWaterColor, sheetOptics * 0.55);
        finalAlpha      = mix(depthAlpha, finalAlpha, sheetOptics * 0.55);
    }

    float effWaterTex = (WATER_TEXTURE > 0.0) ? WATER_TEXTURE : ((ACTIVE_WATER_STYLE == 2) ? 0.62 : 0.0);
    if (effWaterTex > 0.0) {
        // Harmonious authentic Minecraft / Resource-Pack water surface texture (gtexture = texSample)
        // with distance mip-damping so the vanilla/pack texture reads clearly without overpowering shallow riverbeds.
        float texLuma = dot(texSample.rgb, vec3(0.2126, 0.7152, 0.0722));
        float texPattern = clamp(1.0 + (texLuma - 0.60) * 1.55, 0.72, 1.32);
        float distTexFade = exp(-viewDist * 0.018);
        vec3 vanillaTexColor = texSample.rgb * mix(vec3(1.0), vVertexColor.rgb, 0.72);
        vec3 baseTint = max(finalWaterColor, ((STYLE_SELECTION == 0) ? vec3(0.12, 0.32, 0.34) : vec3(0.08, 0.28, 0.42)) * biomeChromaMod);
        vec3 authenticTexWater = mix(
            baseTint * texPattern,
            vanillaTexColor * clamp(0.90 + (texLuma - 0.60) * 1.35, 0.65, 1.38),
            0.45
        );
        finalWaterColor = mix(finalWaterColor, authenticTexWater, effWaterTex * distTexFade);
        finalAlpha = clamp(finalAlpha + effWaterTex * distTexFade * 0.08, 0.0, 0.92);
    }

    outColor0 = vec4(finalWaterColor, finalAlpha);
    outColor1 = vec4(perturbedViewNormal * 0.5 + 0.5, 0.90);
    // Spillway geometry is distinct from level water even when wave normals
    // tilt through the reflection prepass's horizontal-normal threshold.
    float fluidHeight = fract(vWorldPos.y + 0.001);
    bool thinFlowTop = verticalFace < 0.5 && !slopedTop && fluidHeight > 0.02 && fluidHeight < 0.75;
    // Keep surface foam subtle and restricted to genuine sloped flowing faces and the very lowest run-out tips.
    float tipFade = smoothstep(0.04, 0.12, fluidHeight)
        * (1.0 - smoothstep(0.18, 0.38, fluidHeight));
    float slopeFade = smoothstep(0.15, 0.35, fluidHeight)
        * (1.0 - smoothstep(0.65, 0.88, fluidHeight)) * 0.45;
    float surfaceFoam = max(tipFade, slopedTop ? max(tipFade, slopeFade) : 0.0);
    float fluidTag = slopedTop ? (0.25 - 0.05 * surfaceFoam)
        : (thinFlowTop ? (0.125 - 0.0625 * surfaceFoam) : verticalFace);
    outColor2 = vec4(vLmCoord.x, vLmCoord.y, flowDirection, fluidTag);
}
