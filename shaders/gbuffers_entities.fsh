#version 330 compatibility
#include "/lib/camera_options.glsl"
in vec2 vTexCoord;
in vec2 vLmCoord;
in vec3 vViewNormal;
in vec4 vVertexColor;

uniform sampler2D gtexture;
uniform vec4 entityColor;

#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
/* RENDERTARGETS: 0,1,2,5 */
layout(location = 3) out vec4 outMotion;
#else
/* RENDERTARGETS: 0,1,2 */
#endif
layout(location = 0) out vec4 outColor0;
layout(location = 1) out vec4 outColor1;
layout(location = 2) out vec4 outColor2;

void main() {
#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
    outMotion = vec4(0.0);
#endif
    vec4 texSample = texture(gtexture, vTexCoord) * vVertexColor;
    if (texSample.a < 0.12) {
        discard;
    }

    vec3 albedo = mix(texSample.rgb, entityColor.rgb, entityColor.a);
    vec3 viewNormal = normalize(gl_FrontFacing ? vViewNormal : -vViewNormal);

    outColor0 = vec4(albedo, 1.0);
    outColor1 = vec4(viewNormal * 0.5 + 0.5, 0.10);
    outColor2 = vec4(min(vLmCoord.x, 0.92), max(vLmCoord.y, 0.15), 1.0, 0.0);
}
