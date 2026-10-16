#version 330 compatibility
#define CLOUD_TYPE 0 // [0 1 2 3]
in vec2 vTexCoord;
in vec4 vColor;
uniform sampler2D gtexture;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor0;

void main() {
    #if CLOUD_TYPE != 3
    discard;
    #else
    vec4 c = texture(gtexture, vTexCoord) * vColor;
    if (c.a < 0.05) discard;
    outColor0 = c;
    #endif
}
