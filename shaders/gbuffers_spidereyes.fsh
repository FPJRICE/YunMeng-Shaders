#version 330 compatibility
#include "/lib/camera_options.glsl"
in vec2 vTexCoord;
in vec4 vVertexColor;
in vec3 vViewNormal;

uniform sampler2D gtexture;

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
    ivec2 gTexSize   = textureSize(gtexture, 0);
    ivec2 texelCoord = clamp(ivec2(vTexCoord * vec2(gTexSize)), ivec2(0), max(gTexSize - 1, ivec2(0)));
    vec4 rawTex      = texelFetch(gtexture, texelCoord, 0);
    vec4 texSample   = texture(gtexture, vTexCoord) * vVertexColor;
    float rawPeak    = max(rawTex.r, max(rawTex.g, rawTex.b));
    float peakChannel = max(texSample.r, max(texSample.g, texSample.b));
    // Discard near-black socket/pupil pixels (< 0.14) in additive *_eyes.png overlays
    // so dark pixels meant to be invisible under additive GL_ONE blending never overwrite the mob face:
    if (rawPeak < 0.14 || peakChannel < 0.05 || texSample.a < 0.05) {
        discard;
    }
    outOpaqueBank = vec4(0.0);
#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
    outMotion = vec4(0.0);
#endif
    vec3 viewNormal = normalize(gl_FrontFacing ? vViewNormal : -vViewNormal);
#if EMISSIVE_EYES_MODE == 0
    outColor0 = vec4(texSample.rgb, 1.0);
    outColor1 = vec4(viewNormal * 0.5 + 0.5, 0.10);
    outColor2 = vec4(0.0, 0.25, 1.0, 0.0);
#else
    float minChannel = min(rawTex.r, min(rawTex.g, rawTex.b));
    float chromaSpan = rawPeak - minChannel;
    float targetEmissivePeak = clamp(mix(0.45, 0.96, smoothstep(0.14, 0.85, rawPeak)), 0.45, 0.96);
    vec3 eyePigment = (rawTex.rgb / max(rawPeak, 1e-4)) * targetEmissivePeak;
    if (chromaSpan > 0.02) {
        vec3 dewhitened = max(rawTex.rgb - minChannel * 0.38, vec3(0.0));
        float newPeak   = max(dewhitened.r, max(dewhitened.g, dewhitened.b));
        eyePigment      = (dewhitened / max(newPeak, 1e-4)) * targetEmissivePeak;
    }

    outColor0 = vec4(eyePigment, 1.0);
    outColor1 = vec4(viewNormal * 0.5 + 0.5, 0.36);
    outColor2 = vec4(1.0, 1.0, 1.0, 1.0);
#endif
}
