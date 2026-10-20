#version 330 compatibility
in vec2 vTexCoord;
in vec4 vVertexColor;
uniform sampler2D gtexture;
uniform int entityId;
uniform int renderStage;

/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 outShadowColor0;
layout(location = 1) out vec4 outAtmosphericDepth;
/*
const int shadowcolor1Format = R32F;
*/
const vec4 shadowcolor1ClearColor = vec4(1.0);
const bool shadowcolor1Clear = true;

void main() {
    vec4 texSample = texture(gtexture, vTexCoord);
    if (texSample.a < 0.15) {
        discard;
    }
    outShadowColor0 = vec4(texSample.rgb * vVertexColor.rgb, texSample.a);
    // Opaque terrain is drawn before entities. Alpha blending preserves that
    // depth behind the player and transparent panes without changing shadowtex.
    bool atmosphericCaster = entityId != 9001;
#ifdef MC_RENDER_STAGE_TERRAIN_TRANSLUCENT
    atmosphericCaster = atmosphericCaster && renderStage != MC_RENDER_STAGE_TERRAIN_TRANSLUCENT;
#endif
    outAtmosphericDepth = vec4(vec3(gl_FragCoord.z), float(atmosphericCaster));
}
